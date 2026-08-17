"""Governed aggregate read model for the Local Signals surface.

This module exposes one thing: per-place weekly review-mention aggregates from
``community.place_mentions_weekly``, and only from a source whose governance
registration is currently approved. It exists so the Local Signals tab can show
honest system aggregates without any raw user or third-party content.

Whitelist decision (single approved source table):
- Read source is ``community.place_mentions_weekly`` only. It is the one
  review-mention aggregate table the repository already produces
  (``review_mention_ingest``), so no new data source is invented here.
- Approval gate is the existing governance registration
  ``ingest.review_sources``: a row is readable only when its ``provider`` maps
  to an ``active`` registration whose ``license_class`` is in the governance
  module's allowed classes. No parallel allow-list is introduced.
- ``community.local_signal_aggregate_eligibility`` is intentionally NOT the
  gate: it is keyed on ``signal_id`` for first-party Local Signals with
  contributor opt-in, which is a different domain from review mentions.

Safety invariants:
- The SELECT names its columns explicitly. The nested ``attributes`` jsonb blob
  is never selected; only the scalar ``attributes->'review_quality'->>'score'``
  is read, reshaped server-side into a float. ``attributes`` contains
  ``preprocess.retained_external_keys`` / ``filtered_external_keys`` lists, so
  selecting it would leak external keys into the read model.
- No external key, external URL, author identity, raw text, or per-review row
  ever reaches the output shape.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator, Mapping
from contextlib import closing, contextmanager
from datetime import date, timedelta
from typing import Any

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.review_ingest_governance import ALLOWED_LICENSE_CLASSES

READ_MODEL_NAME = "local_signals_place_aggregates"
READ_MODEL_VERSION = "v1"
# The aggregate table stores one row per (week, place, provider, category).
# A consumer sees one card per place, so providers are summed into one row.
_MAX_ITEMS = 50

_LICENSE_CLASSES_SQL = ", ".join(repr(license_class) for license_class in ALLOWED_LICENSE_CLASSES)


class LocalSignalsAggregatesRepositoryUnavailable(RuntimeError):
    """The governed aggregate store cannot be reached."""


class LocalSignalsAggregatesRepository:
    """Read-only PostgreSQL access for the governed aggregate read model."""

    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    def list_place_aggregates(
        self,
        *,
        weeks: int,
        limit: int,
        place_id: str | None,
        category: str | None,
    ) -> list[dict[str, Any]]:
        """Return approved place aggregates rolled up per place and week.

        Explicit column projection only: ``mentions.attributes`` is never
        selected, so the nested external-key lists cannot enter the read model.
        """

        sql = f"""
            SELECT
                NULLIF(TRIM(mentions.place_id), '') AS place_id,
                mentions.place_name_ko,
                mentions.category,
                mentions.week_start,
                (mentions.week_start + INTERVAL '6 days')::date AS week_end,
                SUM(mentions.mention_count)::int AS mention_count,
                SUM(mentions.organic_mention_count)::int AS organic_mention_count,
                AVG(mentions.sentiment_score) AS sentiment_score,
                MAX(
                    (mentions.attributes->'review_quality'->>'score')::double precision
                ) AS review_quality_score,
                MAX(mentions.updated_at) AS last_refreshed_at,
                MIN(mentions.updated_at) AS computed_at
            FROM community.place_mentions_weekly mentions
            JOIN ingest.review_sources sources
              ON sources.source_name = mentions.attributes->>'source'
            WHERE sources.source_status = 'active'
              AND sources.license_class IN ({_LICENSE_CLASSES_SQL})
              AND mentions.week_start >= (CURRENT_DATE - (%s::int * 7) * INTERVAL '1 day')
        """
        params: list[Any] = [weeks]
        if place_id:
            sql += " AND mentions.place_id = %s"
            params.append(place_id)
        if category:
            sql += " AND mentions.category = %s"
            params.append(category)
        sql += """
            GROUP BY
                mentions.place_id,
                mentions.place_name_ko,
                mentions.category,
                mentions.week_start
            ORDER BY mentions.week_start DESC, SUM(mentions.mention_count) DESC
            LIMIT %s
        """
        params.append(limit)
        with self._cursor() as cur:
            cur.execute(sql, tuple(params))
            return list(cur.fetchall())

    def latest_refresh_at(self) -> Any:
        sql = f"""
            SELECT MAX(mentions.updated_at) AS last_refreshed_at
            FROM community.place_mentions_weekly mentions
            JOIN ingest.review_sources sources
              ON sources.source_name = mentions.attributes->>'source'
            WHERE sources.source_status = 'active'
              AND sources.license_class IN ({_LICENSE_CLASSES_SQL})
        """
        with self._cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()
            if row is None:
                return None
            return row["last_refreshed_at"] if isinstance(row, Mapping) else row[0]

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise LocalSignalsAggregatesRepositoryUnavailable()
        try:
            from psycopg2.extras import RealDictCursor
        except Exception as exc:
            raise LocalSignalsAggregatesRepositoryUnavailable() from exc
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor(cursor_factory=RealDictCursor) as cur:
                        yield cur
        except LocalSignalsAggregatesRepositoryUnavailable:
            raise
        except Exception as exc:
            raise LocalSignalsAggregatesRepositoryUnavailable() from exc


def _connect(*, dsn: str, connect_timeout: int) -> object:
    try:
        import psycopg2
    except Exception as exc:
        raise LocalSignalsAggregatesRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


class LocalSignalsAggregatesService:
    """Flag-gated, honest-empty aggregate read model."""

    def __init__(
        self,
        repository: LocalSignalsAggregatesRepository,
        *,
        settings: Settings | None = None,
    ) -> None:
        self._repository = repository
        self._settings = settings or get_settings()

    def _aggregate_read_enabled(self) -> bool:
        return bool(self._settings.feature_flags.get("LOCAL_SIGNALS_AGGREGATE_READ", False))

    def list_place_aggregates(
        self,
        *,
        weeks: int,
        limit: int,
        place_id: str | None,
        category: str | None,
    ) -> dict[str, Any]:
        # Default-safe: governance flag off is an honest unavailable result with
        # zero items, never an error and never fabricated rows.
        if not self._aggregate_read_enabled():
            return _unavailable_payload()
        try:
            rows = self._repository.list_place_aggregates(
                weeks=weeks,
                limit=limit,
                place_id=place_id,
                category=category,
            )
            refreshed = self._repository.latest_refresh_at()
        except LocalSignalsAggregatesRepositoryUnavailable as exc:
            # A closed gate is honest-empty; an unreachable store is a retryable
            # service error so the client can show its error state, matching the
            # sibling read path's LOCAL_SIGNALS_DB_UNAVAILABLE contract.
            raise _database_unavailable() from exc
        return {
            "read_model": READ_MODEL_NAME,
            "read_model_version": READ_MODEL_VERSION,
            "source": "governed_review_mention_aggregation",
            "provider_class": "aggregated_review_mentions",
            "available": True,
            "items": [_aggregate_item(row) for row in rows],
            "computed_at": _max_datetime(
                refreshed,
                *(row["computed_at"] for row in rows),
            ),
            "last_refreshed_at": _iso_or_none(refreshed),
        }


def _aggregate_item(row: Mapping[str, Any]) -> dict[str, Any]:
    week_start = row["week_start"]
    week_end = week_start + timedelta(days=6) if isinstance(week_start, date) else None
    place_id = row.get("place_id")
    if isinstance(place_id, str):
        place_id = place_id.strip() or None
    return {
        "kind": "system_aggregate",
        "place_id": place_id,
        "place_name_ko": row["place_name_ko"],
        "category": row["category"],
        "mention_count": int(row["mention_count"] or 0),
        "organic_mention_count": (
            int(row["organic_mention_count"])
            if row.get("organic_mention_count") is not None
            else None
        ),
        "sentiment_score": _score_or_none(row.get("sentiment_score")),
        "review_quality_score": _score_or_none(row.get("review_quality_score")),
        "week_start": _iso_or_none(week_start),
        "week_end": _iso_or_none(week_end),
        "provider_class": "aggregated_review_mentions",
    }


def _score_or_none(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return round(float(value), 4)
    except (TypeError, ValueError):
        return None


def _iso_or_none(value: Any) -> str | None:
    if value is None:
        return None
    return value.isoformat() if hasattr(value, "isoformat") else str(value)


def _max_datetime(*values: Any) -> str | None:
    candidates = [value for value in values if value is not None]
    if not candidates:
        return None
    return _iso_or_none(max(candidates))


def _unavailable_payload() -> dict[str, Any]:
    return {
        "read_model": READ_MODEL_NAME,
        "read_model_version": READ_MODEL_VERSION,
        "source": "governed_review_mention_aggregation",
        "provider_class": "aggregated_review_mentions",
        "available": False,
        "items": [],
        "computed_at": None,
        "last_refreshed_at": None,
    }


def _database_unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="LOCAL_SIGNALS_DB_UNAVAILABLE",
        message="Local Signals storage is temporarily unavailable.",
        retryable=True,
    )
