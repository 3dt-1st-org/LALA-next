from __future__ import annotations

import base64
import binascii
import copy
import hashlib
import json
import re
from collections.abc import Callable, Iterator, Mapping
from contextlib import closing, contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from threading import Condition, Lock
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.local_signals import (
    LocalSignalCommentCreate,
    LocalSignalReportCreate,
)
from apps.api.app.services.request_identity import request_hash


class LocalSignalsRepositoryUnavailable(RuntimeError):
    """The Local Signals store cannot be reached."""


class LocalSignalsRepository:
    """PostgreSQL access for the additive LS-1 Local Signals contract.

    Public reads start from community.local_signal_public. This keeps author
    identity, moderation internals, capability hashes, and aggregate metadata
    out of the query boundary by construction.
    """

    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    def list_public_signals(
        self,
        *,
        language: str,
        region: str | None,
        place_id: str | None,
        kind: str | None,
        limit: int,
        cursor: tuple[datetime, UUID] | None,
        sort: str,
    ) -> list[dict[str, Any]]:
        where, params = _public_filters(
            language=language,
            region=region,
            place_id=place_id,
            kind=kind,
            cursor=cursor,
            sort=sort,
        )
        order_by = (
            "useful_count DESC, p.published_at DESC, p.id DESC"
            if sort == "useful"
            else "p.published_at DESC, p.id DESC"
        )
        sql = f"""
            SELECT
                p.id,
                p.kind,
                p.source_language,
                p.title,
                p.body,
                p.locality_level,
                p.locality_code,
                p.commercial_disclosure,
                p.observation_date,
                p.published_at,
                COALESCE(
                    json_agg(
                        DISTINCT jsonb_build_object(
                            'place_id', links.place_id,
                            'relation', links.relation
                        )
                    ) FILTER (WHERE links.place_id IS NOT NULL),
                    '[]'::json
                ) AS place_links,
                translation.body AS translation_body,
                translation.translation_method,
                translation.translator_version,
                translation.source_content_hash,
                translation.provenance,
                translation.review_state,
                translation.reviewed_at,
                (
                    SELECT count(*)::int
                    FROM community.local_signal_reactions reaction
                    WHERE reaction.signal_id = p.id
                ) AS reaction_count,
                (
                    SELECT count(*)::int
                    FROM community.local_signal_comments comment
                    WHERE comment.signal_id = p.id
                      AND comment.status = 'published'
                ) AS comment_count,
                (
                    SELECT count(*)::int
                    FROM community.local_signal_reactions useful
                    WHERE useful.signal_id = p.id
                      AND useful.reaction_type = 'useful'
                ) AS useful_count
            FROM community.local_signal_public p
            LEFT JOIN community.local_signal_places links
              ON links.signal_id = p.id
            LEFT JOIN LATERAL (
                SELECT
                    available.body,
                    available.translation_method,
                    available.translator_version,
                    available.source_content_hash,
                    available.provenance,
                    available.review_state,
                    available.reviewed_at
                FROM community.local_signal_translations available
                WHERE available.signal_id = p.id
                  AND available.target_language = %s
                  AND available.review_state = 'available'
                  AND p.source_language <> %s
                ORDER BY available.reviewed_at DESC NULLS LAST, available.created_at DESC
                LIMIT 1
            ) translation ON TRUE
            WHERE {" AND ".join(where)}
            GROUP BY
                p.id,
                p.kind,
                p.source_language,
                p.title,
                p.body,
                p.locality_level,
                p.locality_code,
                p.commercial_disclosure,
                p.observation_date,
                p.published_at,
                translation.body,
                translation.translation_method,
                translation.translator_version,
                translation.source_content_hash,
                translation.provenance,
                translation.review_state,
                translation.reviewed_at
            ORDER BY {order_by}
            LIMIT %s
        """
        with self._cursor() as cur:
            cur.execute(sql, (language, language, *params, limit))
            return list(cur.fetchall())

    def get_public_signal(
        self,
        *,
        signal_id: UUID,
        language: str,
    ) -> dict[str, Any] | None:
        where, params = _public_filters(
            language=language,
            region=None,
            place_id=None,
            kind=None,
            cursor=None,
            sort="recent",
        )
        sql = f"""
            SELECT
                p.id,
                p.kind,
                p.source_language,
                p.title,
                p.body,
                p.locality_level,
                p.locality_code,
                p.commercial_disclosure,
                p.observation_date,
                p.published_at,
                COALESCE(
                    json_agg(
                        DISTINCT jsonb_build_object(
                            'place_id', links.place_id,
                            'relation', links.relation
                        )
                    ) FILTER (WHERE links.place_id IS NOT NULL),
                    '[]'::json
                ) AS place_links,
                translation.body AS translation_body,
                translation.translation_method,
                translation.translator_version,
                translation.source_content_hash,
                translation.provenance,
                translation.review_state,
                translation.reviewed_at,
                (
                    SELECT count(*)::int
                    FROM community.local_signal_reactions reaction
                    WHERE reaction.signal_id = p.id
                ) AS reaction_count,
                (
                    SELECT count(*)::int
                    FROM community.local_signal_comments comment
                    WHERE comment.signal_id = p.id
                      AND comment.status = 'published'
                ) AS comment_count
            FROM community.local_signal_public p
            LEFT JOIN community.local_signal_places links
              ON links.signal_id = p.id
            LEFT JOIN LATERAL (
                SELECT
                    available.body,
                    available.translation_method,
                    available.translator_version,
                    available.source_content_hash,
                    available.provenance,
                    available.review_state,
                    available.reviewed_at
                FROM community.local_signal_translations available
                WHERE available.signal_id = p.id
                  AND available.target_language = %s
                  AND available.review_state = 'available'
                  AND p.source_language <> %s
                ORDER BY available.reviewed_at DESC NULLS LAST, available.created_at DESC
                LIMIT 1
            ) translation ON TRUE
            WHERE p.id = %s
              AND {" AND ".join(where)}
            GROUP BY
                p.id,
                p.kind,
                p.source_language,
                p.title,
                p.body,
                p.locality_level,
                p.locality_code,
                p.commercial_disclosure,
                p.observation_date,
                p.published_at,
                translation.body,
                translation.translation_method,
                translation.translator_version,
                translation.source_content_hash,
                translation.provenance,
                translation.review_state,
                translation.reviewed_at
        """
        with self._cursor() as cur:
            cur.execute(sql, (language, language, str(signal_id), *params))
            return cur.fetchone()

    def public_signal_exists(self, *, signal_id: UUID) -> bool:
        with self._cursor() as cur:
            cur.execute(
                "SELECT EXISTS (SELECT 1 FROM community.local_signal_public WHERE id = %s)",
                (str(signal_id),),
            )
            row = cur.fetchone()
            return bool(row and next(iter(row.values())))

    def list_public_comments(
        self,
        *,
        signal_id: UUID,
        language: str,
        limit: int,
        cursor: tuple[datetime, UUID] | None,
    ) -> list[dict[str, Any]]:
        where = [
            "comment.signal_id = %s",
            "comment.status = 'published'",
            "comment.source_language = %s",
        ]
        params: list[Any] = [str(signal_id), language]
        if cursor is not None:
            where.append(
                "(comment.created_at > %s OR (comment.created_at = %s AND comment.id > %s))"
            )
            params.extend((cursor[0], cursor[0], str(cursor[1])))
        sql = f"""
            SELECT comment.id, comment.source_language, comment.body, comment.created_at
            FROM community.local_signal_comments comment
            WHERE {" AND ".join(where)}
              AND EXISTS (
                  SELECT 1
                  FROM community.local_signal_public signal
                  WHERE signal.id = comment.signal_id
              )
            ORDER BY comment.created_at ASC, comment.id ASC
            LIMIT %s
        """
        with self._cursor() as cur:
            cur.execute(sql, (*params, limit))
            return list(cur.fetchall())

    def get_signal_for_owner(self, *, signal_id: UUID) -> dict[str, Any] | None:
        sql = """
            SELECT
                signal.id,
                signal.author_issuer,
                signal.author_subject,
                signal.kind,
                signal.status,
                signal.moderation_state,
                signal.visibility,
                signal.source_language,
                signal.title,
                signal.body,
                signal.locality_level,
                signal.locality_code,
                signal.commercial_disclosure,
                signal.observation_date,
                signal.published_at,
                signal.aggregate_opt_in,
                signal.created_at,
                signal.updated_at,
                COALESCE(
                    (
                        SELECT json_agg(
                            jsonb_build_object(
                                'place_id', links.place_id,
                                'relation', links.relation
                            )
                        )
                        FROM community.local_signal_places links
                        WHERE links.signal_id = signal.id
                    ),
                    '[]'::json
                ) AS place_links
            FROM community.local_signals signal
            WHERE signal.id = %s
        """
        with self._cursor() as cur:
            cur.execute(sql, (str(signal_id),))
            return cur.fetchone()

    def create_draft(
        self,
        *,
        issuer: str,
        subject: str,
        values: Mapping[str, Any],
    ) -> dict[str, Any]:
        sql = """
            INSERT INTO community.local_signals
                (
                    author_issuer,
                    author_subject,
                    kind,
                    status,
                    moderation_state,
                    visibility,
                    source_language,
                    title,
                    body,
                    locality_level,
                    locality_code,
                    commercial_disclosure,
                    observation_date,
                    aggregate_opt_in
                )
            VALUES (%s, %s, %s, 'draft', 'unreviewed', 'private',
                    %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING
                id, kind, status, moderation_state, visibility, source_language,
                title, body, locality_level, locality_code,
                commercial_disclosure, observation_date
        """
        with self._cursor() as cur:
            cur.execute(
                sql,
                (
                    issuer,
                    subject,
                    values["kind"],
                    values["source_language"],
                    values["title"],
                    values["body"],
                    values["locality_level"],
                    values["locality_code"],
                    values["commercial_disclosure"],
                    values["observation_date"],
                    values["aggregate_opt_in"],
                ),
            )
            row = cur.fetchone()
            if row is None:
                raise LocalSignalsRepositoryUnavailable()
            self._replace_links(cur, row["id"], values)
            if values.get("route_snapshot_ref"):
                cur.execute(
                    """
                    INSERT INTO community.local_signal_routes(signal_id, route_snapshot_ref)
                    VALUES (%s, %s)
                    ON CONFLICT (signal_id) DO UPDATE
                    SET route_snapshot_ref = EXCLUDED.route_snapshot_ref
                    """,
                    (str(row["id"]), values["route_snapshot_ref"]),
                )
            return dict(row)

    def update_draft(
        self,
        *,
        signal_id: UUID,
        values: Mapping[str, Any],
    ) -> dict[str, Any] | None:
        update_values = {
            key: value
            for key, value in values.items()
            if key not in {"place_links", "route_snapshot_ref"} and value is not None
        }
        assignments = ", ".join(f"{key} = %s" for key in update_values) or "updated_at = updated_at"
        params = [*update_values.values(), str(signal_id)]
        sql = f"""
            UPDATE community.local_signals
            SET {assignments}, updated_at = now()
            WHERE id = %s AND status = 'draft'
            RETURNING
                id, kind, status, moderation_state, visibility, source_language,
                title, body, locality_level, locality_code,
                commercial_disclosure, observation_date
        """
        with self._cursor() as cur:
            cur.execute(sql, tuple(params))
            row = cur.fetchone()
            if row is None:
                return None
            if "place_links" in values and values["place_links"] is not None:
                cur.execute(
                    "DELETE FROM community.local_signal_places WHERE signal_id = %s",
                    (str(signal_id),),
                )
                self._replace_links(cur, row["id"], values)
            if "route_snapshot_ref" in values and values["route_snapshot_ref"] is not None:
                cur.execute(
                    """
                    INSERT INTO community.local_signal_routes(signal_id, route_snapshot_ref)
                    VALUES (%s, %s)
                    ON CONFLICT (signal_id) DO UPDATE
                    SET route_snapshot_ref = EXCLUDED.route_snapshot_ref
                    """,
                    (str(signal_id), values["route_snapshot_ref"]),
                )
            return dict(row)

    def submit_signal(self, *, signal_id: UUID, issuer: str, subject: str) -> dict[str, Any] | None:
        sql = """
            UPDATE community.local_signals
            SET status = 'submitted',
                moderation_state = 'pending',
                visibility = 'pending_review',
                updated_at = now()
            WHERE id = %s
              AND author_issuer = %s
              AND author_subject = %s
              AND status = 'draft'
            RETURNING
                id, kind, status, moderation_state, visibility, source_language,
                title, body, locality_level, locality_code,
                commercial_disclosure, observation_date
        """
        with self._cursor() as cur:
            cur.execute(sql, (str(signal_id), issuer, subject))
            row = cur.fetchone()
            if row is not None:
                cur.execute(
                    """
                    INSERT INTO community.local_signal_moderation_actions
                        (target_type, target_id, action_type, reason_code,
                         actor_issuer, actor_subject, policy_version)
                    VALUES ('signal', %s, 'submit', 'deterministic_policy_passed',
                            %s, %s, 'local-signals-policy-v1')
                    """,
                    (str(signal_id), issuer, subject),
                )
            return dict(row) if row is not None else None

    def delete_signal(self, *, signal_id: UUID, issuer: str, subject: str) -> dict[str, Any] | None:
        sql = """
            UPDATE community.local_signals
            SET status = 'deleted', visibility = 'private', updated_at = now()
            WHERE id = %s
              AND author_issuer = %s
              AND author_subject = %s
              AND status <> 'deleted'
            RETURNING
                id, kind, status, moderation_state, visibility, source_language,
                title, body, locality_level, locality_code,
                commercial_disclosure, observation_date
        """
        with self._cursor() as cur:
            cur.execute(sql, (str(signal_id), issuer, subject))
            row = cur.fetchone()
            return dict(row) if row is not None else None

    def set_reaction(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        reaction_type: str,
        active: bool,
    ) -> bool:
        with self._cursor() as cur:
            if active:
                cur.execute(
                    """
                    INSERT INTO community.local_signal_reactions
                        (signal_id, issuer, subject, reaction_type)
                    SELECT %s, %s, %s, %s
                    WHERE EXISTS (
                        SELECT 1 FROM community.local_signal_public WHERE id = %s
                    )
                    ON CONFLICT DO NOTHING
                    RETURNING signal_id
                    """,
                    (str(signal_id), issuer, subject, reaction_type, str(signal_id)),
                )
            else:
                cur.execute(
                    """
                    DELETE FROM community.local_signal_reactions
                    WHERE signal_id = %s AND issuer = %s AND subject = %s
                      AND reaction_type = %s
                    RETURNING signal_id
                    """,
                    (str(signal_id), issuer, subject, reaction_type),
                )
            return cur.fetchone() is not None

    def set_save(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        active: bool,
    ) -> bool:
        with self._cursor() as cur:
            if active:
                cur.execute(
                    """
                    INSERT INTO community.local_signal_saves(signal_id, issuer, subject)
                    SELECT %s, %s, %s
                    WHERE EXISTS (
                        SELECT 1 FROM community.local_signal_public WHERE id = %s
                    )
                    ON CONFLICT DO NOTHING
                    RETURNING signal_id
                    """,
                    (str(signal_id), issuer, subject, str(signal_id)),
                )
            else:
                cur.execute(
                    """
                    DELETE FROM community.local_signal_saves
                    WHERE signal_id = %s AND issuer = %s AND subject = %s
                    RETURNING signal_id
                    """,
                    (str(signal_id), issuer, subject),
                )
            return cur.fetchone() is not None

    def create_comment(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        values: Mapping[str, Any],
    ) -> dict[str, Any] | None:
        sql = """
            INSERT INTO community.local_signal_comments
                (signal_id, author_issuer, author_subject,
                 source_language, body, status, depth)
            SELECT %s, %s, %s, %s, %s, 'submitted', 0
            WHERE EXISTS (
                SELECT 1 FROM community.local_signal_public WHERE id = %s
            )
            RETURNING id, signal_id, source_language, body, status, created_at
        """
        with self._cursor() as cur:
            cur.execute(
                sql,
                (
                    str(signal_id),
                    issuer,
                    subject,
                    values["source_language"],
                    values["body"],
                    str(signal_id),
                ),
            )
            row = cur.fetchone()
            return dict(row) if row is not None else None

    def create_report(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        reason_code: str,
    ) -> UUID | None:
        sql = """
            INSERT INTO community.local_signal_reports
                (target_type, target_id, reporter_issuer, reporter_subject, reason_code)
            SELECT 'signal', %s, %s, %s, %s
            WHERE EXISTS (
                SELECT 1 FROM community.local_signals
                WHERE id = %s AND status <> 'deleted'
            )
            ON CONFLICT (
                reporter_issuer,
                reporter_subject,
                target_type,
                target_id,
                reason_code
            ) WHERE status IN ('open', 'triaged')
            DO UPDATE SET reason_code = EXCLUDED.reason_code
            RETURNING id
        """
        with self._cursor() as cur:
            cur.execute(
                sql,
                (str(signal_id), issuer, subject, reason_code, str(signal_id)),
            )
            row = cur.fetchone()
            return row["id"] if row else None

    def _replace_links(self, cur: Any, signal_id: UUID, values: Mapping[str, Any]) -> None:
        for link in values.get("place_links") or []:
            cur.execute(
                """
                INSERT INTO community.local_signal_places(signal_id, place_id, relation)
                VALUES (%s, %s, %s)
                ON CONFLICT DO NOTHING
                """,
                (str(signal_id), link["place_id"], link["relation"]),
            )

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise LocalSignalsRepositoryUnavailable()
        try:
            from psycopg2.extras import RealDictCursor
        except Exception as exc:
            raise LocalSignalsRepositoryUnavailable() from exc
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor(cursor_factory=RealDictCursor) as cur:
                        yield cur
        except LocalSignalsRepositoryUnavailable:
            raise
        except Exception as exc:
            raise LocalSignalsRepositoryUnavailable() from exc


def _connect(*, dsn: str, connect_timeout: int) -> object:
    try:
        import psycopg2
    except Exception as exc:
        raise LocalSignalsRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def _public_filters(
    *,
    language: str,
    region: str | None,
    place_id: str | None,
    kind: str | None,
    cursor: SignalCursor | None,
    sort: str,
) -> tuple[list[str], list[Any]]:
    where = [
        "(p.source_language = %s OR EXISTS ("
        "SELECT 1 FROM community.local_signal_translations available_translation "
        "WHERE available_translation.signal_id = p.id "
        "AND available_translation.target_language = %s "
        "AND available_translation.review_state = 'available'))"
    ]
    params: list[Any] = [language, language]
    if region:
        where.append("p.locality_code = %s")
        params.append(region)
    if place_id:
        where.append(
            "EXISTS (SELECT 1 FROM community.local_signal_places place_filter "
            "WHERE place_filter.signal_id = p.id AND place_filter.place_id = %s)"
        )
        params.append(place_id)
    if kind:
        where.append("p.kind = %s")
        params.append(kind)
    if cursor is not None:
        if cursor.sort != sort:
            raise _invalid_cursor()
        if sort == "useful":
            if cursor.useful_count is None:
                raise _invalid_cursor()
            where.append(
                "("
                f"{_USEFUL_COUNT_SQL} < %s "
                "OR ("
                f"{_USEFUL_COUNT_SQL} = %s "
                "AND (p.published_at < %s "
                "OR (p.published_at = %s AND p.id < %s))"
                ")"
                ")"
            )
            params.extend(
                (
                    cursor.useful_count,
                    cursor.useful_count,
                    cursor.published_at,
                    cursor.published_at,
                    str(cursor.signal_id),
                )
            )
        else:
            where.append("(p.published_at < %s OR (p.published_at = %s AND p.id < %s))")
            params.extend((cursor.published_at, cursor.published_at, str(cursor.signal_id)))
    return where, params


@dataclass(frozen=True)
class SignalCursor:
    sort: str
    published_at: datetime
    signal_id: UUID
    useful_count: int | None = None


_SIGNAL_SORTS = frozenset({"recent", "useful"})
_USEFUL_COUNT_SQL = """(
    SELECT count(*)::int
    FROM community.local_signal_reactions useful_cursor
    WHERE useful_cursor.signal_id = p.id
      AND useful_cursor.reaction_type = 'useful'
)"""


class _IdempotencyStore:
    def __init__(self) -> None:
        self._condition = Condition(Lock())
        self._values: dict[str, _IdempotencyEntry] = {}

    def run(
        self,
        *,
        actor_key: str,
        operation: str,
        idempotency_key: str,
        payload: Mapping[str, Any],
        callback: Callable[[], dict[str, Any]],
    ) -> dict[str, Any]:
        key = hashlib.sha256(f"{actor_key}:{operation}:{idempotency_key}".encode()).hexdigest()
        payload_digest = request_hash(dict(payload))
        with self._condition:
            existing = self._values.get(key)
            if existing is not None:
                if existing.payload_digest != payload_digest:
                    raise ServiceError(
                        status_code=409,
                        code="IDEMPOTENCY_KEY_REUSED",
                        message="The idempotency key was already used for another request.",
                        retryable=False,
                    )
                while not existing.completed:
                    self._condition.wait()
                if existing.error is not None:
                    raise existing.error
                return copy.deepcopy(existing.result)
            existing = _IdempotencyEntry(payload_digest=payload_digest)
            self._values[key] = existing

        try:
            result = callback()
        except Exception as exc:
            with self._condition:
                existing.error = exc
                existing.completed = True
                self._values.pop(key, None)
                self._condition.notify_all()
            raise

        with self._condition:
            existing.result = copy.deepcopy(result)
            existing.completed = True
            self._condition.notify_all()
        return result

    def clear(self) -> None:
        with self._condition:
            self._values.clear()


@dataclass
class _IdempotencyEntry:
    payload_digest: str
    completed: bool = False
    result: dict[str, Any] | None = None
    error: Exception | None = None


_IDEMPOTENCY_STORE = _IdempotencyStore()


def reset_local_signals_state_for_tests() -> None:
    _IDEMPOTENCY_STORE.clear()


_EMAIL_PATTERN = re.compile(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b")
_PHONE_PATTERN = re.compile(r"(?<!\d)(?:\+?82[- .]?)?0?1[0-9][-. ]?\d{3,4}[- .]?\d{4}(?!\d)")
_COORDINATE_PATTERN = re.compile(
    r"(?<!\w)[+-]?(?:[0-8]?\d(?:\.\d{3,})?|90(?:\.0+)?)\s*[,/]\s*"
    r"[+-]?(?:1[0-7]\d|[1-9]?\d(?:\.\d{3,})?|180(?:\.0+)?)(?!\w)"
)
_TOKEN_PATTERN = re.compile(r"(?i)\b(?:bearer|authorization|id[_ -]?token|access[_ -]?token)\b")
_PROMOTION_PATTERN = re.compile(r"(?i)\b(?:sponsored|paid|gifted|ad|협찬|광고|제공받)\b")
_UNSAFE_LIVE_PATTERN = re.compile(
    r"(?i)(?:live location|real[- ]time location|실시간 위치|즉석 만남)"
)


def validate_local_signal_policy(
    *,
    title: str,
    body: str,
    locality_level: str,
    commercial_disclosure: str,
) -> None:
    """Reject deterministic PII/policy hazards without echoing matched text."""

    text = f"{title}\n{body}"
    if _EMAIL_PATTERN.search(text) or _PHONE_PATTERN.search(text):
        raise ServiceError(
            status_code=422,
            code="CONTENT_POLICY_BLOCKED",
            message="The signal contains contact information that cannot be published.",
            retryable=False,
        )
    if _COORDINATE_PATTERN.search(text):
        raise ServiceError(
            status_code=422,
            code="LOCATION_TOO_PRECISE",
            message="Exact coordinates cannot be included in a Local Signal.",
            retryable=False,
        )
    if _TOKEN_PATTERN.search(text):
        raise ServiceError(
            status_code=422,
            code="CONTENT_POLICY_BLOCKED",
            message="Credentials and access tokens cannot be included.",
            retryable=False,
        )
    if _UNSAFE_LIVE_PATTERN.search(text):
        raise ServiceError(
            status_code=422,
            code="CONTENT_POLICY_BLOCKED",
            message="Live-location or meet-up coordination is not supported.",
            retryable=False,
        )
    if _PROMOTION_PATTERN.search(text) and commercial_disclosure == "none":
        raise ServiceError(
            status_code=422,
            code="DISCLOSURE_REQUIRED",
            message="Commercial or sponsored content requires disclosure.",
            retryable=False,
        )
    if locality_level == "none" and "place" in text.lower():
        raise ServiceError(
            status_code=422,
            code="INVALID_LOCALITY",
            message="A locality is required for this Local Signal.",
            retryable=False,
        )


class LocalSignalsService:
    def __init__(
        self,
        repository: LocalSignalsRepository,
        *,
        settings: Settings | None = None,
    ) -> None:
        self._repository = repository
        self._settings = settings or get_settings()

    def ensure_read_enabled(self) -> None:
        if not self._settings.feature_flags.get("LOCAL_SIGNALS_READ", False):
            raise ServiceError(
                status_code=503,
                code="LOCAL_SIGNALS_DISABLED",
                message="Local Signals is currently unavailable.",
                retryable=False,
            )

    def ensure_write_enabled(self) -> None:
        if not self._settings.feature_flags.get("LOCAL_SIGNALS_WRITE", False):
            raise ServiceError(
                status_code=503,
                code="LOCAL_SIGNALS_DISABLED",
                message="Local Signals writing is currently unavailable.",
                retryable=False,
            )

    def list_public(
        self,
        *,
        language: str,
        region: str | None,
        place_id: str | None,
        kind: str | None,
        limit: int,
        cursor: str | None,
        sort: str,
    ) -> dict[str, Any]:
        self.ensure_read_enabled()
        cursor_value = decode_signal_cursor(cursor, sort=sort) if cursor else None
        try:
            rows = self._repository.list_public_signals(
                language=language,
                region=region,
                place_id=place_id,
                kind=kind,
                limit=limit + 1,
                cursor=cursor_value,
                sort=sort,
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        has_more = len(rows) > limit
        page = rows[:limit]
        next_cursor = encode_signal_cursor(page[-1], sort=sort) if has_more and page else None
        return {
            "items": [_public_item(row, language) for row in page],
            "next_cursor": next_cursor,
            "has_more": has_more,
            "context": {
                "language": language,
                "locality_level": "district" if region else None,
                "locality_code": region,
                "kind": kind,
                "sort": sort,
            },
        }

    def get_public(self, *, signal_id: UUID, language: str) -> dict[str, Any]:
        self.ensure_read_enabled()
        try:
            row = self._repository.get_public_signal(signal_id=signal_id, language=language)
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found()
        return _public_item(row, language)

    def list_comments(
        self,
        *,
        signal_id: UUID,
        language: str,
        limit: int,
        cursor: str | None,
    ) -> dict[str, Any]:
        self.ensure_read_enabled()
        cursor_value = decode_comment_cursor(cursor) if cursor else None
        try:
            rows = self._repository.list_public_comments(
                signal_id=signal_id,
                language=language,
                limit=limit + 1,
                cursor=cursor_value,
            )
            signal = self._repository.get_public_signal(signal_id=signal_id, language=language)
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if signal is None:
            raise _not_found()
        has_more = len(rows) > limit
        page = rows[:limit]
        next_cursor = encode_comment_cursor(page[-1]) if has_more and page else None
        return {
            "items": [_public_comment(row) for row in page],
            "next_cursor": next_cursor,
            "has_more": has_more,
            "context": {
                "language": language,
                "locality_level": None,
                "locality_code": None,
                "kind": None,
                "sort": "recent",
            },
        }

    def create_draft(
        self,
        *,
        issuer: str,
        subject: str,
        values: Mapping[str, Any],
        idempotency_key: str,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        validate_local_signal_policy(
            title=values["title"],
            body=values["body"],
            locality_level=values["locality_level"],
            commercial_disclosure=values["commercial_disclosure"],
        )
        self._validate_locality(values)
        return _IDEMPOTENCY_STORE.run(
            actor_key=f"{issuer}:{subject}",
            operation="create_draft",
            idempotency_key=idempotency_key,
            payload=_json_safe(values),
            callback=lambda: self._create_draft(issuer, subject, values),
        )

    def update_draft(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        values: Mapping[str, Any],
        idempotency_key: str,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        current = self._owned_signal(signal_id, issuer, subject)
        if current["status"] != "draft":
            raise _invalid_transition()
        merged = dict(current)
        merged.update({key: value for key, value in values.items() if value is not None})
        validate_local_signal_policy(
            title=merged["title"],
            body=merged["body"],
            locality_level=merged["locality_level"],
            commercial_disclosure=merged["commercial_disclosure"],
        )
        self._validate_locality(merged)
        return _IDEMPOTENCY_STORE.run(
            actor_key=f"{issuer}:{subject}",
            operation=f"update_draft:{signal_id}",
            idempotency_key=idempotency_key,
            payload=_json_safe(values),
            callback=lambda: self._update_draft(signal_id, values),
        )

    def submit(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        current = self._owned_signal(signal_id, issuer, subject)
        if current["status"] != "draft":
            raise _invalid_transition()
        validate_local_signal_policy(
            title=current["title"],
            body=current["body"],
            locality_level=current["locality_level"],
            commercial_disclosure=current["commercial_disclosure"],
        )
        return _IDEMPOTENCY_STORE.run(
            actor_key=f"{issuer}:{subject}",
            operation=f"submit:{signal_id}",
            idempotency_key=idempotency_key,
            payload={"signal_id": str(signal_id)},
            callback=lambda: self._submit(signal_id, issuer, subject),
        )

    def delete(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        self._owned_signal(signal_id, issuer, subject)
        return _IDEMPOTENCY_STORE.run(
            actor_key=f"{issuer}:{subject}",
            operation=f"delete:{signal_id}",
            idempotency_key=idempotency_key,
            payload={"signal_id": str(signal_id)},
            callback=lambda: self._delete(signal_id, issuer, subject),
        )

    def set_reaction(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        reaction_type: str,
        active: bool,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        try:
            changed = self._repository.set_reaction(
                signal_id=signal_id,
                issuer=issuer,
                subject=subject,
                reaction_type=reaction_type,
                active=active,
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if not changed and not self._public_signal_exists(signal_id):
            raise _not_found()
        return {"signal_id": str(signal_id), "reaction_type": reaction_type, "active": active}

    def set_save(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        active: bool,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        try:
            changed = self._repository.set_save(
                signal_id=signal_id,
                issuer=issuer,
                subject=subject,
                active=active,
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if not changed and not self._public_signal_exists(signal_id):
            raise _not_found()
        return {"signal_id": str(signal_id), "saved": active}

    def create_comment(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        values: LocalSignalCommentCreate,
        idempotency_key: str,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        validate_local_signal_policy(
            title="",
            body=values.body,
            locality_level="district",
            commercial_disclosure="none",
        )
        return _IDEMPOTENCY_STORE.run(
            actor_key=f"{issuer}:{subject}",
            operation=f"comment:{signal_id}",
            idempotency_key=idempotency_key,
            payload=values.model_dump(mode="json"),
            callback=lambda: self._create_comment(signal_id, issuer, subject, values),
        )

    def create_report(
        self,
        *,
        signal_id: UUID,
        issuer: str,
        subject: str,
        body: LocalSignalReportCreate,
        idempotency_key: str,
    ) -> dict[str, Any]:
        self.ensure_write_enabled()
        return _IDEMPOTENCY_STORE.run(
            actor_key=f"{issuer}:{subject}",
            operation=f"report:{signal_id}",
            idempotency_key=idempotency_key,
            payload=body.model_dump(mode="json"),
            callback=lambda: self._create_report(signal_id, issuer, subject, body),
        )

    def _create_draft(self, issuer: str, subject: str, values: Mapping[str, Any]) -> dict[str, Any]:
        try:
            row = self._repository.create_draft(issuer=issuer, subject=subject, values=values)
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return _mutation_payload(row)

    def _update_draft(self, signal_id: UUID, values: Mapping[str, Any]) -> dict[str, Any]:
        try:
            row = self._repository.update_draft(signal_id=signal_id, values=values)
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _invalid_transition()
        return _mutation_payload(row)

    def _submit(self, signal_id: UUID, issuer: str, subject: str) -> dict[str, Any]:
        try:
            row = self._repository.submit_signal(
                signal_id=signal_id,
                issuer=issuer,
                subject=subject,
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _invalid_transition()
        return _mutation_payload(row)

    def _delete(self, signal_id: UUID, issuer: str, subject: str) -> dict[str, Any]:
        try:
            row = self._repository.delete_signal(
                signal_id=signal_id,
                issuer=issuer,
                subject=subject,
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_owner()
        return _mutation_payload(row)

    def _create_comment(
        self,
        signal_id: UUID,
        issuer: str,
        subject: str,
        values: LocalSignalCommentCreate,
    ) -> dict[str, Any]:
        try:
            row = self._repository.create_comment(
                signal_id=signal_id,
                issuer=issuer,
                subject=subject,
                values=values.model_dump(),
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found()
        return {
            "id": str(row["id"]),
            "signal_id": str(row["signal_id"]),
            "status": row["status"],
            "source_language": row["source_language"],
            "created_at": _iso(row["created_at"]),
        }

    def _create_report(
        self,
        signal_id: UUID,
        issuer: str,
        subject: str,
        body: LocalSignalReportCreate,
    ) -> dict[str, Any]:
        try:
            case_id = self._repository.create_report(
                signal_id=signal_id,
                issuer=issuer,
                subject=subject,
                reason_code=body.reason_code,
            )
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if case_id is None:
            raise _not_found()
        return {"case_id": str(case_id), "status": "open"}

    def _owned_signal(self, signal_id: UUID, issuer: str, subject: str) -> dict[str, Any]:
        try:
            row = self._repository.get_signal_for_owner(signal_id=signal_id)
        except LocalSignalsRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found()
        if row.get("author_issuer") != issuer or row.get("author_subject") != subject:
            raise _not_owner()
        return row

    def _public_signal_exists(self, signal_id: UUID) -> bool:
        checker = getattr(self._repository, "public_signal_exists", None)
        if checker is not None:
            try:
                return bool(checker(signal_id=signal_id))
            except LocalSignalsRepositoryUnavailable as exc:
                raise _database_unavailable() from exc
        return self._repository.get_public_signal(signal_id=signal_id, language="ko") is not None

    @staticmethod
    def _validate_locality(values: Mapping[str, Any]) -> None:
        locality_level = values["locality_level"]
        links = values.get("place_links") or []
        if locality_level == "place" and not any(link["relation"] == "primary" for link in links):
            raise ServiceError(
                status_code=422,
                code="INVALID_PLACE_LINK",
                message="A primary canonical place link is required at place precision.",
                retryable=False,
            )
        if locality_level == "none" and links:
            raise ServiceError(
                status_code=422,
                code="INVALID_LOCALITY",
                message="A signal without locality cannot include a place link.",
                retryable=False,
            )


def _encode_signal_cursor(row: Mapping[str, Any], *, sort: str) -> str:
    if sort not in _SIGNAL_SORTS:
        raise _invalid_cursor()
    payload: dict[str, Any] = {
        "v": 1,
        "s": sort,
        "t": _timestamp_to_cursor_value(row["published_at"]),
        "i": str(row["id"]),
    }
    if sort == "useful":
        useful_count = row.get("useful_count")
        if not isinstance(useful_count, int) or isinstance(useful_count, bool) or useful_count < 0:
            raise _invalid_cursor()
        payload["u"] = useful_count
    return _encode_opaque_cursor(payload)


def encode_signal_cursor(row: Mapping[str, Any], *, sort: str = "recent") -> str:
    return _encode_signal_cursor(row, sort=sort)


def encode_comment_cursor(row: Mapping[str, Any]) -> str:
    return _encode_opaque_cursor(
        {
            "v": 1,
            "k": "comment",
            "t": _timestamp_to_cursor_value(row["created_at"]),
            "i": str(row["id"]),
        }
    )


def decode_signal_cursor(value: str, *, sort: str) -> SignalCursor:
    if sort not in _SIGNAL_SORTS:
        raise _invalid_cursor()
    decoded = _decode_opaque_cursor(value)
    expected_keys = {"v", "s", "t", "i"}
    if sort == "useful":
        expected_keys.add("u")
    if set(decoded) != expected_keys or decoded.get("v") != 1 or decoded.get("s") != sort:
        raise _invalid_cursor()
    try:
        timestamp = _timestamp_from_cursor_value(decoded["t"])
        identifier = UUID(decoded["i"])
        useful_count = decoded.get("u")
        if sort == "useful" and (
            not isinstance(useful_count, int) or isinstance(useful_count, bool) or useful_count < 0
        ):
            raise ValueError("cursor useful count is invalid")
        return SignalCursor(
            sort=sort,
            published_at=timestamp,
            signal_id=identifier,
            useful_count=useful_count,
        )
    except (ValueError, TypeError, KeyError, OverflowError) as exc:
        raise _invalid_cursor() from exc


def decode_comment_cursor(value: str) -> tuple[datetime, UUID]:
    decoded = _decode_opaque_cursor(value)
    if set(decoded) != {"v", "k", "t", "i"} or decoded.get("v") != 1:
        raise _invalid_cursor()
    try:
        timestamp = _timestamp_from_cursor_value(decoded["t"])
        if decoded["k"] != "comment":
            raise ValueError("comment cursor is invalid")
        return timestamp, UUID(decoded["i"])
    except (ValueError, TypeError, KeyError, OverflowError) as exc:
        raise _invalid_cursor() from exc


def _encode_opaque_cursor(payload: Mapping[str, Any]) -> str:
    encoded = json.dumps(dict(payload), separators=(",", ":"), allow_nan=False).encode("utf-8")
    return base64.urlsafe_b64encode(encoded).decode("ascii").rstrip("=")


def _timestamp_to_cursor_value(value: datetime) -> int:
    if value.tzinfo is None:
        raise _invalid_cursor()
    normalized = value.astimezone(UTC)
    epoch = datetime(1970, 1, 1, tzinfo=UTC)
    delta = normalized - epoch
    return (delta.days * 86_400 + delta.seconds) * 1_000_000 + delta.microseconds


def _timestamp_from_cursor_value(value: Any) -> datetime:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("cursor timestamp is invalid")
    return datetime(1970, 1, 1, tzinfo=UTC) + timedelta(microseconds=value)


def _decode_opaque_cursor(value: str) -> dict[str, Any]:
    if not isinstance(value, str) or not value or len(value) > 128:
        raise _invalid_cursor()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise _invalid_cursor()
    try:
        padded = value + "=" * (-len(value) % 4)
        decoded = json.loads(
            base64.b64decode(padded.encode("ascii"), altchars=b"-_", validate=True),
            parse_constant=lambda _: (_ for _ in ()).throw(ValueError("invalid JSON constant")),
        )
    except (ValueError, TypeError, binascii.Error, json.JSONDecodeError) as exc:
        raise _invalid_cursor() from exc
    if not isinstance(decoded, dict):
        raise _invalid_cursor()
    return decoded


def _invalid_cursor() -> ServiceError:
    return ServiceError(
        status_code=422,
        code="INVALID_CURSOR",
        message="The pagination cursor is invalid.",
        retryable=False,
    )


def _public_item(row: Mapping[str, Any], language: str) -> dict[str, Any]:
    source_language = row["source_language"]
    translated = source_language != language and row.get("translation_body")
    translation = None
    if translated:
        translation = {
            "source_language": source_language,
            "target_language": language,
            "body": row["translation_body"],
            "method": row["translation_method"],
            "translator_version": row["translator_version"],
            "source_content_hash": row["source_content_hash"],
            "provenance": row["provenance"],
            "review_state": row["review_state"],
            "reviewed_at": row.get("reviewed_at"),
        }
    return {
        "id": str(row["id"]),
        "kind": row["kind"],
        "source_language": source_language,
        "display_language": language,
        "title": row["title"],
        "body": row["translation_body"] if translated else row["body"],
        "locality_level": row["locality_level"],
        "locality_code": row.get("locality_code"),
        "commercial_disclosure": row["commercial_disclosure"],
        "observation_date": row["observation_date"],
        "published_at": _iso(row["published_at"]),
        "place_links": _place_links(row.get("place_links") or []),
        "translation": translation,
        "translation_available": source_language == language or translated is not None,
        "reaction_count": int(row.get("reaction_count") or 0),
        "comment_count": int(row.get("comment_count") or 0),
    }


def _public_comment(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(row["id"]),
        "source_language": row["source_language"],
        "body": row["body"],
        "created_at": _iso(row["created_at"]),
    }


def _mutation_payload(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(row["id"]),
        "kind": row["kind"],
        "status": row["status"],
        "moderation_state": row["moderation_state"],
        "visibility": row["visibility"],
        "source_language": row["source_language"],
        "title": row["title"],
        "body": row["body"],
        "locality_level": row["locality_level"],
        "locality_code": row.get("locality_code"),
        "commercial_disclosure": row["commercial_disclosure"],
        "observation_date": row["observation_date"],
        "place_links": _place_links(row.get("place_links") or []),
    }


def _place_links(value: Any) -> list[dict[str, str]]:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return []
    return [
        {"place_id": str(link["place_id"]), "relation": str(link["relation"])}
        for link in value
        if isinstance(link, Mapping) and link.get("place_id") and link.get("relation")
    ]


def _json_safe(values: Mapping[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(dict(values), default=str))


def _iso(value: Any) -> str:
    return value.isoformat() if hasattr(value, "isoformat") else str(value)


def _database_unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="LOCAL_SIGNALS_DB_UNAVAILABLE",
        message="Local Signals storage is temporarily unavailable.",
        retryable=True,
    )


def _not_found() -> ServiceError:
    return ServiceError(
        status_code=404,
        code="CONTENT_NOT_FOUND",
        message="Local Signal was not found.",
        retryable=False,
    )


def _not_owner() -> ServiceError:
    return ServiceError(
        status_code=403,
        code="NOT_OWNER",
        message="The authenticated user does not own this Local Signal.",
        retryable=False,
    )


def _invalid_transition() -> ServiceError:
    return ServiceError(
        status_code=409,
        code="INVALID_STATUS_TRANSITION",
        message="The Local Signal is not in a client-editable state.",
        retryable=False,
    )
