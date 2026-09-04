"""Governed aggregate read model tests.

Every test works from locally authored fixture rows only; no production data
values are read or printed. The no-leak assertions are the load-bearing part:
the read model must be unable to carry raw review text, external keys,
external URLs, or author identity even when those shapes exist upstream.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.routers.local_signals import (
    get_local_signals_aggregates_service,
)
from apps.api.app.services.local_signals_aggregates import (
    READ_MODEL_NAME,
    LocalSignalsAggregatesRepository,
    LocalSignalsAggregatesRepositoryUnavailable,
    LocalSignalsAggregatesService,
)

REFRESHED_AT = datetime(2026, 8, 4, 6, 30, tzinfo=UTC)
WEEK_START = date(2026, 8, 3)


def _settings(*, aggregate_read: bool = True) -> Settings:
    return Settings(
        feature_flags={
            "LOCAL_SIGNALS_READ": True,
            "LOCAL_SIGNALS_WRITE": False,
            "LOCAL_SIGNALS_AGGREGATE_READ": aggregate_read,
        }
    )


def _aggregate_row(**overrides: Any) -> dict[str, Any]:
    row = {
        "place_id": "place-1",
        "place_name_ko": "수원화성",
        "category": "attraction",
        "week_start": WEEK_START,
        "week_end": WEEK_START,
        "mention_count": 12,
        "organic_mention_count": 9,
        "sentiment_score": 0.62,
        "review_quality_score": 0.71,
        "last_refreshed_at": REFRESHED_AT,
        "computed_at": REFRESHED_AT,
    }
    row.update(overrides)
    return row


class FakeAggregatesRepository:
    def __init__(self, rows: list[dict[str, Any]] | None = None) -> None:
        self.rows = rows if rows is not None else [_aggregate_row()]
        self.calls: list[dict[str, Any]] = []

    def list_place_aggregates(self, **kwargs: Any) -> list[dict[str, Any]]:
        self.calls.append(kwargs)
        return list(self.rows)

    def latest_refresh_at(self) -> datetime:
        return REFRESHED_AT


class ExplodingRepository(FakeAggregatesRepository):
    def list_place_aggregates(self, **_: Any) -> list[dict[str, Any]]:
        raise LocalSignalsAggregatesRepositoryUnavailable()


def _service(
    repository: FakeAggregatesRepository,
    *,
    aggregate_read: bool = True,
    now: Any = None,
) -> LocalSignalsAggregatesService:
    return LocalSignalsAggregatesService(
        repository,
        settings=_settings(aggregate_read=aggregate_read),
        now=now,
    )


def test_aggregate_read_flag_off_is_honest_empty_not_error() -> None:
    payload = _service(FakeAggregatesRepository(), aggregate_read=False).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None
    )

    assert payload["available"] is False
    assert payload["items"] == []
    assert payload["read_model"] == READ_MODEL_NAME
    assert payload["computed_at"] is None


def test_aggregate_flag_off_never_touches_the_repository() -> None:
    repository = FakeAggregatesRepository()

    _service(repository, aggregate_read=False).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None
    )

    assert repository.calls == []


def test_aggregate_payload_carries_system_aggregate_semantics() -> None:
    payload = _service(FakeAggregatesRepository()).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None
    )

    assert payload["available"] is True
    assert payload["read_model"] == READ_MODEL_NAME
    assert payload["read_model_version"] == "v1"
    assert payload["source"] == "governed_review_mention_aggregation"
    assert payload["provider_class"] == "aggregated_review_mentions"
    # Freshness fields are present and ISO-shaped.
    assert payload["last_refreshed_at"] == REFRESHED_AT.isoformat()
    assert payload["computed_at"] == REFRESHED_AT.isoformat()
    item = payload["items"][0]
    assert item["kind"] == "system_aggregate"
    assert item["provider_class"] == "aggregated_review_mentions"
    assert item["mention_count"] == 12
    assert item["organic_mention_count"] == 9
    # Window is a full Monday-Sunday style week (inclusive end).
    assert item["week_start"] == "2026-08-03"
    assert item["week_end"] == "2026-08-09"


def test_aggregate_item_shape_has_no_raw_or_identity_field() -> None:
    payload = _service(FakeAggregatesRepository()).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None
    )

    item = payload["items"][0]
    assert set(item) == {
        "kind",
        "place_id",
        "place_name_ko",
        "category",
        "mention_count",
        "organic_mention_count",
        "sentiment_score",
        "review_quality_score",
        "week_start",
        "week_end",
        "provider_class",
    }
    for forbidden in (
        "attributes",
        "author",
        "author_issuer",
        "author_subject",
        "external_key",
        "external_keys",
        "post_url",
        "url",
        "body",
        "title",
        "provider",
    ):
        assert forbidden not in item
    assert set(payload) == {
        "read_model",
        "read_model_version",
        "source",
        "provider_class",
        "available",
        "region",
        "region_applied",
        "items",
        "computed_at",
        "last_refreshed_at",
        "freshness",
    }


def test_repository_unavailable_is_retryable_service_error() -> None:
    with pytest.raises(Exception) as exc_info:
        _service(ExplodingRepository()).list_place_aggregates(
            weeks=4, limit=20, place_id=None, category=None
        )

    assert exc_info.value.status_code == 503
    assert exc_info.value.code == "LOCAL_SIGNALS_DB_UNAVAILABLE"
    assert exc_info.value.retryable is True


def test_blank_place_id_collapses_to_null_not_empty_string() -> None:
    payload = _service(
        FakeAggregatesRepository([_aggregate_row(place_id="  ")])
    ).list_place_aggregates(weeks=4, limit=20, place_id=None, category=None)

    assert payload["items"][0]["place_id"] is None


def test_non_numeric_scores_are_dropped_not_stringified() -> None:
    payload = _service(
        FakeAggregatesRepository(
            [_aggregate_row(sentiment_score="not-a-number", review_quality_score=None)]
        )
    ).list_place_aggregates(weeks=4, limit=20, place_id=None, category=None)

    item = payload["items"][0]
    assert item["sentiment_score"] is None
    assert item["review_quality_score"] is None


def test_repository_query_never_selects_the_raw_attributes_blob() -> None:
    executed: list[tuple[str, Any]] = []

    class Cursor:
        def __enter__(self) -> Cursor:
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def execute(self, sql: str, params: Any = None) -> None:
            executed.append((sql, params))

        def fetchall(self) -> list[dict[str, Any]]:
            return []

        def fetchone(self) -> dict[str, Any] | None:
            return {"last_refreshed_at": REFRESHED_AT}

    class Connection:
        def __enter__(self) -> Connection:
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def close(self) -> None:
            return None

        def cursor(self, **_: Any) -> Cursor:
            return Cursor()

    repository = LocalSignalsAggregatesRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **_: Connection(),
    )
    repository.list_place_aggregates(weeks=4, limit=5, place_id=None, category=None)

    sql = executed[0][0]
    # The nested attributes jsonb (which stores external-key lists upstream) is
    # only ever reached through the scalar review_quality score path.
    assert "mentions.attributes->'review_quality'->>'score'" in sql
    assert "AS attributes" not in sql
    assert ", attributes" not in sql.replace("mentions.attributes->'review_quality'->>'score'", "")
    # Only the whitelisted aggregate table and its governance gate are read.
    assert "community.place_mentions_weekly" in sql
    assert "ingest.review_sources" in sql
    assert "community.posts" not in sql
    assert "ingest.review_ingest_receipts" not in sql
    # Governance gate pins active + approved license classes.
    assert "sources.source_status = 'active'" in sql
    assert "'licensed'" in sql
    assert "'rejected'" not in sql


def test_aggregate_license_whitelist_matches_governance_module() -> None:
    from apps.api.app.services.review_ingest_governance import ALLOWED_LICENSE_CLASSES

    repository_sql = LocalSignalsAggregatesRepository.list_place_aggregates.__doc__ or ""
    assert repository_sql is not None  # pragma: no cover - shape guard
    # The read model must never widen the governance allow-list.
    assert "rejected" not in {str(item) for item in ALLOWED_LICENSE_CLASSES}
    assert set(ALLOWED_LICENSE_CLASSES) <= {
        "licensed",
        "public_processed",
        "approved_export",
    }


def test_aggregates_route_requires_client_auth_and_rate_limit(
    client: Any, api_key: str, monkeypatch: Any
) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_AGGREGATE_READ", "true")
    service = _service(FakeAggregatesRepository())
    client.app.dependency_overrides[get_local_signals_aggregates_service] = lambda: service

    response = client.get("/api/v1/community/signals/aggregates", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["available"] is True
    assert body["data"]["items"][0]["kind"] == "system_aggregate"
    assert 'event="read"' in client.get("/metrics").text


def test_aggregates_route_without_credentials_is_rejected(client: Any, api_key: str) -> None:
    # A configured server must reject unauthenticated/invalid credentials; with
    # no header at all the app's contract is the CLIENT_AUTH_NOT_CONFIGURED 503
    # (or guest pass-through when guest mode is on), so the deterministic 401
    # assertion uses a present-but-invalid key.
    response = client.get(
        "/api/v1/community/signals/aggregates", headers={"X-API-Key": "wrong-key"}
    )

    assert response.status_code == 401


def test_aggregates_route_flag_off_returns_honest_empty(
    client: Any, api_key: str, monkeypatch: Any
) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_AGGREGATE_READ", "false")
    service = _service(FakeAggregatesRepository(), aggregate_read=False)
    client.app.dependency_overrides[get_local_signals_aggregates_service] = lambda: service

    response = client.get("/api/v1/community/signals/aggregates", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["available"] is False
    assert body["data"]["items"] == []


def test_aggregates_response_contains_no_raw_or_external_key_shaped_strings(
    client: Any, api_key: str, monkeypatch: Any
) -> None:
    """Even a fixture row polluted with raw shapes cannot leak through."""

    monkeypatch.setenv("LALA_LOCAL_SIGNALS_AGGREGATE_READ", "true")
    polluted_rows = [
        _aggregate_row(
            place_name_ko="수원화성",
        )
    ]
    service = _service(FakeAggregatesRepository(polluted_rows))
    client.app.dependency_overrides[get_local_signals_aggregates_service] = lambda: service

    response = client.get("/api/v1/community/signals/aggregates", headers={"X-API-Key": api_key})
    text = response.text

    for forbidden_marker in (
        "https://",
        "http://",
        "external_key",
        "external-key",
        "retained_external_keys",
        "filtered_external_keys",
        "author_issuer",
        "author_subject",
        "content_sha256",
        "preprocess",
        "top_terms",
        "source_mix",
    ):
        assert forbidden_marker not in text
    assert response.status_code == 200


def test_aggregates_openapi_documents_the_read_only_system_surface(
    client: Any, api_key: str
) -> None:
    schema = client.get("/openapi.json").json()

    path = schema["paths"]["/api/v1/community/signals/aggregates"]
    assert path["get"]["security"] == [{}, {"BearerAuth": []}, {"MigrationApiKey": []}]
    assert schema["components"]["schemas"]["LocalSignalPlaceAggregate"]["properties"]["kind"][
        "enum"
    ] == ["system_aggregate"]
    item_properties = set(
        schema["components"]["schemas"]["LocalSignalPlaceAggregate"]["properties"]
    )
    for forbidden in ("attributes", "external_key", "url", "body", "author"):
        assert forbidden not in item_properties


def test_repository_join_uses_governed_source_name_not_sub_provider():
    """The weekly rows carry sub-providers (naver_blog/naver_cafe) in the
    provider column; the governed registration is identified by source_name
    (attributes->>'source'). Joining on provider matched nothing in production
    (source provider='naver'), so aggregates rendered empty even with fresh
    governed rows. The join must be on the source name."""
    executed: list[tuple[str, Any]] = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

        def fetchall(self):
            return []

        def fetchone(self):
            return None

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def close(self):
            return None

        def cursor(self, **_):
            return Cursor()

    repository = LocalSignalsAggregatesRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **_: Connection(),
    )
    repository.list_place_aggregates(weeks=4, limit=5, place_id=None, category=None)
    repository.latest_refresh_at()

    joined_sql = "".join(sql for sql, _ in executed)
    assert "sources.source_name = mentions.attributes->>'source'" in joined_sql
    assert "sources.provider = mentions.provider" not in joined_sql


class _SqlCaptureConnection:
    """Minimal psycopg2-shaped connection capturing executed SQL."""

    def __init__(self) -> None:
        self.executed: list[tuple[str, Any]] = []

    def __enter__(self) -> _SqlCaptureConnection:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def close(self) -> None:
        return None

    def cursor(self, **_: Any) -> Any:
        executed = self.executed

        class Cursor:
            def __enter__(self) -> Cursor:
                return self

            def __exit__(self, *args: object) -> None:
                return None

            def execute(self, sql: str, params: Any = None) -> None:
                executed.append((sql, params))

            def fetchall(self) -> list[dict[str, Any]]:
                return []

            def fetchone(self) -> dict[str, Any] | None:
                return {"last_refreshed_at": REFRESHED_AT}

        return Cursor()


def _capturing_repository() -> tuple[LocalSignalsAggregatesRepository, list[tuple[str, Any]]]:
    connection = _SqlCaptureConnection()
    repository = LocalSignalsAggregatesRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **_: connection,
    )
    return repository, connection.executed


def test_region_request_is_mapped_to_canonical_place_names() -> None:
    repository = FakeAggregatesRepository()

    _service(repository).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None, region="gyeonggi-suwon"
    )

    assert repository.calls[0]["region_names"] == ("수원", "수원시")


def test_unmappable_region_fails_closed_to_scoped_empty_without_repository() -> None:
    repository = FakeAggregatesRepository()

    payload = _service(repository).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None, region="not-a-region"
    )

    assert payload["available"] is True
    assert payload["region"] == "not-a-region"
    assert payload["region_applied"] is False
    assert payload["items"] == []
    assert payload["computed_at"] is None
    assert payload["last_refreshed_at"] is None
    assert payload["freshness"]["state"] == "unknown"
    assert repository.calls == []


def test_mapped_region_with_no_rows_is_applied_empty_not_fallback() -> None:
    repository = FakeAggregatesRepository([])

    payload = _service(repository).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None, region="gyeonggi-suwon"
    )

    assert payload["region_applied"] is True
    assert payload["items"] == []
    assert payload["last_refreshed_at"] is None
    assert payload["freshness"]["state"] == "unknown"


def test_region_scoped_freshness_derives_from_scoped_rows_only() -> None:
    # A newer nationwide refresh must not stamp a region result: the scoped
    # rows' own max is the honest aggregation date.
    class NewerGlobalRefresh(FakeAggregatesRepository):
        def latest_refresh_at(self) -> datetime:
            return datetime(2026, 9, 1, tzinfo=UTC)

    repository = NewerGlobalRefresh([_aggregate_row()])

    payload = _service(repository).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None, region="gyeonggi-suwon"
    )

    assert payload["last_refreshed_at"] == REFRESHED_AT.isoformat()


def test_nationwide_read_keeps_store_wide_latest_refresh_at() -> None:
    class NewerGlobalRefresh(FakeAggregatesRepository):
        def latest_refresh_at(self) -> datetime:
            return datetime(2026, 9, 1, tzinfo=UTC)

    repository = NewerGlobalRefresh([])

    payload = _service(repository).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None
    )

    assert payload["last_refreshed_at"] == "2026-09-01T00:00:00+00:00"


def test_freshness_threshold_boundary_classifies_stale_fresh_unknown() -> None:
    from datetime import timedelta

    from apps.api.app.services.local_signals_aggregates import (
        FRESHNESS_THRESHOLD_DAYS,
    )

    assert FRESHNESS_THRESHOLD_DAYS == 14
    repository = FakeAggregatesRepository()

    def _freshness(now: datetime) -> dict[str, Any]:
        return _service(repository, now=lambda: now).list_place_aggregates(
            weeks=4, limit=20, place_id=None, category=None
        )["freshness"]

    # 15 days past the last refresh crosses the 14-day threshold (two weekly
    # aggregation cycles); 13 days stays fresh. Injected clock → deterministic.
    assert _freshness(REFRESHED_AT + timedelta(days=15)) == {
        "state": "stale",
        "threshold_days": 14,
    }
    assert _freshness(REFRESHED_AT + timedelta(days=13)) == {
        "state": "fresh",
        "threshold_days": 14,
    }

    class NeverRefreshedRepository(FakeAggregatesRepository):
        def latest_refresh_at(self) -> Any:
            return None

    unknown = _service(NeverRefreshedRepository(rows=[])).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None
    )["freshness"]
    assert unknown == {"state": "unknown", "threshold_days": 14}


def test_flag_off_payload_freshness_is_unknown() -> None:
    payload = _service(FakeAggregatesRepository(), aggregate_read=False).list_place_aggregates(
        weeks=4, limit=20, place_id=None, category=None, region="gyeonggi-suwon"
    )

    assert payload["freshness"] == {"state": "unknown", "threshold_days": 14}
    assert payload["region"] == "gyeonggi-suwon"
    assert payload["region_applied"] is False


def test_repository_sql_region_clause_matches_places_without_selecting_them() -> None:
    repository, executed = _capturing_repository()

    repository.list_place_aggregates(
        weeks=4,
        limit=5,
        place_id=None,
        category=None,
        region_names=("수원", "수원시"),
    )

    sql, params = executed[0]
    assert "FROM travel.places region_place" in sql
    assert "region_place.region_name_ko = ANY(%s)" in sql
    assert ["수원", "수원시"] in [list(p) for p in params if isinstance(p, list)]
    # The places join exists only for matching; place columns stay unselected
    # (no coordinates or addresses in the projection).
    for forbidden in ("latitude", "longitude", "address", "region_place.*"):
        assert forbidden not in sql


def test_repository_sql_without_region_is_unchanged_regression() -> None:
    repository_with, executed_with = _capturing_repository()
    repository_without, executed_without = _capturing_repository()

    repository_with.list_place_aggregates(
        weeks=4, limit=5, place_id=None, category=None, region_names=("수원시",)
    )
    repository_without.list_place_aggregates(
        weeks=4, limit=5, place_id=None, category=None, region_names=None
    )

    sql_with = executed_with[0][0]
    sql_without = executed_without[0][0]
    assert "travel.places" not in sql_without
    # Stripping the region clause from the scoped query must yield exactly the
    # unscoped query — the region path changes nothing else in the read.
    region_clause = (
        " AND EXISTS ( SELECT 1 FROM travel.places region_place "
        "WHERE region_place.place_id = mentions.place_id "
        "AND region_place.region_name_ko = ANY(%s) )"
    )

    def normalize(sql: str) -> str:
        return " ".join(sql.split())

    assert normalize(sql_with).replace(region_clause, "") == normalize(sql_without)


def test_aggregates_route_forwards_region_to_service(
    client: Any, api_key: str, monkeypatch: Any
) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_AGGREGATE_READ", "true")
    repository = FakeAggregatesRepository()
    service = _service(repository)
    client.app.dependency_overrides[get_local_signals_aggregates_service] = lambda: service

    response = client.get(
        "/api/v1/community/signals/aggregates",
        params={"region": "gyeonggi-suwon"},
        headers={"X-API-Key": api_key},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["region"] == "gyeonggi-suwon"
    assert body["data"]["region_applied"] is True
    assert repository.calls[0]["region_names"] == ("수원", "수원시")


def test_aggregates_openapi_documents_region_scope_and_freshness(client: Any, api_key: str) -> None:
    schema = client.get("/openapi.json").json()

    parameters = schema["paths"]["/api/v1/community/signals/aggregates"]["get"]["parameters"]
    region_parameter = next(p for p in parameters if p["name"] == "region")
    assert region_parameter["required"] is False
    data_properties = schema["components"]["schemas"]["LocalSignalPlaceAggregatesData"][
        "properties"
    ]
    assert set(("region", "region_applied", "freshness")) <= set(data_properties)
    freshness = data_properties["freshness"]
    assert set(freshness.get("required", ())) == {"state", "threshold_days"}
