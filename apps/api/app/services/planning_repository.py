from __future__ import annotations

import json
from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from datetime import date
from typing import Any

from apps.api.app.core.config import Settings, get_settings

# Persisted-envelope version. Independent of canonical-SQL migration numbering:
# bumping this makes every older persisted plan read as version-mismatch -> null
# (D8), mirroring the Flutter cross-tab envelope version discipline.
PLANNING_ENVELOPE_VERSION = 1
TRIP_OVERRIDE_SCHEMA_VERSION = 1

# The four durable plan-slot periods (planner_service._PERIOD_ORDER). A persisted
# visit keys on this string, not a synthetic numeric index.
SLOT_PERIODS = ("morning", "lunch", "afternoon", "dinner")


class PlanningRepositoryUnavailable(RuntimeError):
    """The planning action store cannot be reached."""


class TripPreferenceOverrideRevisionConflict(RuntimeError):
    """The caller tried to overwrite a newer date-scoped override."""


class PlanningRepository:
    """Raw-SQL access for the V5-A planning action tables.

    A sibling module to the other class-based repositories: it imports the shared
    connection style and is injectable for tests (no DB is stood up in CI). Every
    query is scoped by the caller's ``(issuer, subject)`` pair, so cross-user
    isolation holds by construction (A6) and all user input is bound as a
    parameter, never concatenated (A3/D4).
    """

    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise PlanningRepositoryUnavailable()
        try:
            from psycopg2.extras import RealDictCursor
        except Exception as exc:  # pragma: no cover - psycopg2 optional in CI
            raise PlanningRepositoryUnavailable() from exc
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor(cursor_factory=RealDictCursor) as cur:
                        yield cur
        except (PlanningRepositoryUnavailable, TripPreferenceOverrideRevisionConflict):
            raise
        except Exception as exc:  # pragma: no cover - DB unreachable in CI
            raise PlanningRepositoryUnavailable() from exc

    # -- saved places (D2) ------------------------------------------------

    def list_saved_places(self, *, issuer: str, subject: str) -> list[dict[str, Any]]:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT place_id, source, saved_at
                FROM planning.user_saved_places
                WHERE issuer = %s AND subject = %s
                ORDER BY saved_at
                """,
                (issuer, subject),
            )
            rows = cur.fetchall()
        return [_saved_place_row(row) for row in rows]

    def set_saved_place(
        self,
        *,
        issuer: str,
        subject: str,
        place_id: str,
        source: str,
        active: bool,
    ) -> dict[str, Any]:
        # Idempotent toggle: the composite PK makes repeat-save a no-op delta
        # and DELETE is naturally idempotent, so save -> unsaved -> save never
        # leaves a duplicate row (A4).
        with self._cursor() as cur:
            if active:
                cur.execute(
                    """
                    INSERT INTO planning.user_saved_places (issuer, subject, place_id, source)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (issuer, subject, place_id) DO NOTHING
                    RETURNING place_id
                    """,
                    (issuer, subject, place_id, source),
                )
            else:
                cur.execute(
                    """
                    DELETE FROM planning.user_saved_places
                    WHERE issuer = %s AND subject = %s AND place_id = %s
                    RETURNING place_id
                    """,
                    (issuer, subject, place_id),
                )
            changed = cur.fetchone() is not None
        return {"place_id": place_id, "saved": active, "changed": changed}

    # -- persisted plan (D1/D8) -------------------------------------------

    def save_plan(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
        envelope: dict[str, Any],
    ) -> dict[str, Any]:
        # Upsert one plan per user per day. The envelope is serialized here, not
        # by a client toJson, and rebound through a version guard on read.
        with self._cursor() as cur:
            cur.execute(
                """
                INSERT INTO planning.user_plans
                    (issuer, subject, plan_date, schema_version, envelope)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (issuer, subject, plan_date) DO UPDATE
                    SET schema_version = EXCLUDED.schema_version,
                        envelope = EXCLUDED.envelope,
                        updated_at = now()
                RETURNING plan_date, schema_version, updated_at
                """,
                (issuer, subject, plan_date, PLANNING_ENVELOPE_VERSION, _as_json(envelope)),
            )
            row = cur.fetchone()
        return {
            "plan_date": row["plan_date"].isoformat() if row else plan_date.isoformat(),
            "schema_version": row["schema_version"] if row else PLANNING_ENVELOPE_VERSION,
            "updated_at": row["updated_at"].isoformat() if row and row.get("updated_at") else None,
        }

    def load_plan(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
    ) -> dict[str, Any] | None:
        # Read path is fail-soft: corrupt envelope -> null, future/mismatched
        # schema_version -> null, missing row -> null (A7/A8/D8/D9). Never raises
        # on data shape.
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT schema_version, envelope, updated_at
                FROM planning.user_plans
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                """,
                (issuer, subject, plan_date),
            )
            row = cur.fetchone()
        if row is None:
            return None
        if row.get("schema_version") != PLANNING_ENVELOPE_VERSION:
            return None
        plan = _decode_envelope(row.get("envelope"))
        if plan is None:
            return None
        return {
            "plan_date": plan_date.isoformat(),
            "schema_version": row["schema_version"],
            "plan": plan,
            "updated_at": row["updated_at"].isoformat() if row.get("updated_at") else None,
        }

    def list_plans(
        self,
        *,
        issuer: str,
        subject: str,
        before: date | None,
        limit: int,
    ) -> list[dict[str, Any]]:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT
                    plan.plan_date,
                    plan.schema_version,
                    plan.envelope,
                    plan.updated_at,
                    (
                        SELECT count(*)
                        FROM planning.slot_visits AS visit
                        WHERE visit.issuer = plan.issuer
                          AND visit.subject = plan.subject
                          AND visit.plan_date = plan.plan_date
                          AND visit.status = 'visited'
                    ) AS visited_count
                FROM planning.user_plans AS plan
                WHERE plan.issuer = %s
                  AND plan.subject = %s
                  AND (%s::date IS NULL OR plan.plan_date < %s::date)
                ORDER BY plan.plan_date DESC
                LIMIT %s
                """,
                (issuer, subject, before, before, limit),
            )
            rows = cur.fetchall()
        return [summary for row in rows if (summary := _plan_summary_row(row)) is not None]

    def delete_plan(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
    ) -> dict[str, Any]:
        with self._cursor() as cur:
            cur.execute(
                """
                DELETE FROM planning.slot_visits
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                """,
                (issuer, subject, plan_date),
            )
            cur.execute(
                """
                DELETE FROM planning.trip_preference_overrides
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                """,
                (issuer, subject, plan_date),
            )
            cur.execute(
                """
                DELETE FROM planning.user_plans
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                RETURNING plan_date
                """,
                (issuer, subject, plan_date),
            )
            changed = cur.fetchone() is not None
        return {"plan_date": plan_date.isoformat(), "deleted": changed}

    # -- trip preference overrides (S-22) --------------------------------

    def get_trip_preference_override(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
    ) -> dict[str, Any] | None:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT schema_version, revision, payload, updated_at
                FROM planning.trip_preference_overrides
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                """,
                (issuer, subject, plan_date),
            )
            row = cur.fetchone()
        return _trip_override_row(row, plan_date=plan_date)

    def put_trip_preference_override(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
        expected_revision: int,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT revision
                FROM planning.trip_preference_overrides
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                FOR UPDATE
                """,
                (issuer, subject, plan_date),
            )
            existing = cur.fetchone()
            if existing is None:
                if expected_revision != 0:
                    raise TripPreferenceOverrideRevisionConflict()
                cur.execute(
                    """
                    INSERT INTO planning.trip_preference_overrides
                        (issuer, subject, plan_date, schema_version, revision, payload)
                    VALUES (%s, %s, %s, %s, 1, %s)
                    ON CONFLICT (issuer, subject, plan_date) DO NOTHING
                    RETURNING schema_version, revision, payload, updated_at
                    """,
                    (
                        issuer,
                        subject,
                        plan_date,
                        TRIP_OVERRIDE_SCHEMA_VERSION,
                        _as_json(payload),
                    ),
                )
                inserted = cur.fetchone()
                if inserted is None:
                    raise TripPreferenceOverrideRevisionConflict()
                return _required_trip_override_row(inserted, plan_date=plan_date)

            current_revision = int(existing["revision"])
            if current_revision != expected_revision:
                raise TripPreferenceOverrideRevisionConflict()
            cur.execute(
                """
                UPDATE planning.trip_preference_overrides
                SET schema_version = %s,
                    revision = revision + 1,
                    payload = %s,
                    updated_at = now()
                WHERE issuer = %s
                  AND subject = %s
                  AND plan_date = %s
                  AND revision = %s
                RETURNING schema_version, revision, payload, updated_at
                """,
                (
                    TRIP_OVERRIDE_SCHEMA_VERSION,
                    _as_json(payload),
                    issuer,
                    subject,
                    plan_date,
                    expected_revision,
                ),
            )
            updated = cur.fetchone()
            if updated is None:
                raise TripPreferenceOverrideRevisionConflict()
            return _required_trip_override_row(updated, plan_date=plan_date)

    def delete_trip_preference_override(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
    ) -> dict[str, Any]:
        with self._cursor() as cur:
            cur.execute(
                """
                DELETE FROM planning.trip_preference_overrides
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                RETURNING plan_date
                """,
                (issuer, subject, plan_date),
            )
            changed = cur.fetchone() is not None
        return {"plan_date": plan_date.isoformat(), "deleted": changed}

    # -- slot visits / check-in (D3) --------------------------------------

    def set_slot_visit(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
        slot_period: str,
        place_id: str | None,
        status: str,
        reason_code: str | None = None,
        use_for_recommendations: bool = False,
    ) -> dict[str, Any]:
        # Idempotent check-in: the per-slot composite PK means re-check-in updates
        # the same row in place, never a duplicate (A5).
        if status not in ("planned", "visited", "not_visited"):
            raise ValueError("status must be 'planned', 'visited', or 'not_visited'")
        if slot_period not in SLOT_PERIODS:
            raise ValueError("slot_period is not a known plan period")
        if reason_code is not None and status != "not_visited":
            raise ValueError("reason_code is only valid for not_visited")
        with self._cursor() as cur:
            cur.execute(
                """
                INSERT INTO planning.slot_visits
                    (
                        issuer, subject, plan_date, slot_period, place_id, status,
                        reason_code, use_for_recommendations, visited_at, confirmed_at
                    )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s,
                    CASE WHEN %s = 'visited' THEN now() ELSE NULL END,
                    CASE WHEN %s = 'planned' THEN NULL ELSE now() END
                )
                ON CONFLICT (issuer, subject, plan_date, slot_period) DO UPDATE
                    SET place_id = EXCLUDED.place_id,
                        status = EXCLUDED.status,
                        reason_code = EXCLUDED.reason_code,
                        use_for_recommendations = EXCLUDED.use_for_recommendations,
                        visited_at = CASE
                            WHEN EXCLUDED.status = 'visited' THEN now()
                            ELSE NULL
                        END,
                        confirmed_at = CASE
                            WHEN EXCLUDED.status = 'planned' THEN NULL
                            ELSE now()
                        END,
                        updated_at = now()
                RETURNING
                    slot_period, place_id, status, reason_code,
                    use_for_recommendations, visited_at, confirmed_at
                """,
                (
                    issuer,
                    subject,
                    plan_date,
                    slot_period,
                    place_id,
                    status,
                    reason_code,
                    use_for_recommendations if status != "planned" else False,
                    status,
                    status,
                ),
            )
            row = cur.fetchone()
        return {
            "slot_period": row["slot_period"] if row else slot_period,
            "place_id": row["place_id"] if row else place_id,
            "status": row["status"] if row else status,
            "reason_code": row.get("reason_code") if row else reason_code,
            "use_for_recommendations": bool(
                row.get("use_for_recommendations", False)
                if row
                else use_for_recommendations and status != "planned"
            ),
            "visited_at": row["visited_at"].isoformat() if row and row.get("visited_at") else None,
            "confirmed_at": (
                row["confirmed_at"].isoformat() if row and row.get("confirmed_at") else None
            ),
        }

    def list_slot_visits(
        self,
        *,
        issuer: str,
        subject: str,
        plan_date: date,
    ) -> list[dict[str, Any]]:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT
                    slot_period, place_id, status, reason_code,
                    use_for_recommendations, visited_at, confirmed_at
                FROM planning.slot_visits
                WHERE issuer = %s AND subject = %s AND plan_date = %s
                ORDER BY slot_period
                """,
                (issuer, subject, plan_date),
            )
            rows = cur.fetchall()
        return [_slot_visit_row(row) for row in rows]


def _connect(*, dsn: str, connect_timeout: int) -> object:
    try:
        import psycopg2
    except Exception as exc:  # pragma: no cover - psycopg2 optional in CI
        raise PlanningRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def get_planning_repository() -> PlanningRepository:
    return PlanningRepository(get_settings())


def _as_json(value: dict[str, Any]) -> Any:
    from psycopg2.extras import Json

    return Json(value)


def _decode_envelope(value: Any) -> dict[str, Any] | None:
    # jsonb may arrive already parsed (dict) or as a string; either way a
    # non-dict or unparseable payload degrades to None, never raises.
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except (ValueError, TypeError):
            return None
        return decoded if isinstance(decoded, dict) else None
    return None


def _saved_place_row(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "place_id": row["place_id"],
        "source": row["source"],
        "saved_at": row["saved_at"].isoformat() if row.get("saved_at") else None,
    }


def _slot_visit_row(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "slot_period": row["slot_period"],
        "place_id": row.get("place_id"),
        "status": row["status"],
        "reason_code": row.get("reason_code"),
        "use_for_recommendations": bool(row.get("use_for_recommendations", False)),
        "visited_at": row["visited_at"].isoformat() if row.get("visited_at") else None,
        "confirmed_at": row["confirmed_at"].isoformat() if row.get("confirmed_at") else None,
    }


def _plan_summary_row(row: dict[str, Any]) -> dict[str, Any] | None:
    if row.get("schema_version") != PLANNING_ENVELOPE_VERSION:
        return None
    plan = _decode_envelope(row.get("envelope"))
    if plan is None:
        return None
    slots = plan.get("slots")
    slot_count = len(slots) if isinstance(slots, list) else 0
    region = plan.get("region") if isinstance(plan.get("region"), str) else None
    if region is None and isinstance(slots, list):
        for slot in slots:
            if not isinstance(slot, dict):
                continue
            place = slot.get("place")
            if not isinstance(place, dict):
                continue
            for key in ("region_ko", "region_en"):
                value = place.get(key)
                if isinstance(value, str) and value.strip():
                    region = value.strip()
                    break
            if region is not None:
                break
    return {
        "plan_date": row["plan_date"].isoformat(),
        "schema_version": row["schema_version"],
        "region": region,
        "slot_count": slot_count,
        "visited_count": int(row.get("visited_count") or 0),
        "updated_at": row["updated_at"].isoformat() if row.get("updated_at") else None,
    }


def _trip_override_row(
    row: dict[str, Any] | None,
    *,
    plan_date: date,
) -> dict[str, Any] | None:
    if row is None:
        return None
    return _required_trip_override_row(row, plan_date=plan_date)


def _required_trip_override_row(
    row: dict[str, Any],
    *,
    plan_date: date,
) -> dict[str, Any]:
    payload = row.get("payload")
    if (
        row.get("schema_version") != TRIP_OVERRIDE_SCHEMA_VERSION
        or not isinstance(row.get("revision"), int)
        or not isinstance(payload, dict)
        or row.get("updated_at") is None
    ):
        raise PlanningRepositoryUnavailable()
    return {
        "plan_date": plan_date.isoformat(),
        "schema_version": TRIP_OVERRIDE_SCHEMA_VERSION,
        "revision": row["revision"],
        "override": payload,
        "updated_at": row["updated_at"].isoformat(),
    }
