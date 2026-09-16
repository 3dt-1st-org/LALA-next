from __future__ import annotations

import argparse
from datetime import UTC, date, datetime

from apps.api.app.services import review_attribute_batch, weather_service
from apps.api.app.services.ai_completion import DEFAULT_JSON_GENERATION_PARAMS
from apps.api.app.services.official_paging import OfficialPage, run_official_paged_fetch
from apps.api.app.tools import batch_helpers


def test_official_paged_fetch_preserves_last_total_and_request_counts():
    class Response:
        status_code = 200

        def __init__(self, page_no: int) -> None:
            self.page_no = page_no

    seen: list[dict] = []

    def fake_get(url, *, params, timeout):
        seen.append({"url": url, "params": params, "timeout": timeout})
        return Response(int(params["pageNo"]))

    result = run_official_paged_fetch(
        source="kcisa",
        url="https://example.test/provider",
        service_key="secret-key",  # pragma: allowlist secret - synthetic request fixture
        rows=4,
        page_size=2,
        timeout=7,
        http_get=fake_get,
        response_payload=lambda response: response,
        build_params=lambda page_no, num_rows, key: {
            "serviceKey": key,
            "pageNo": page_no,
            "numOfRows": num_rows,
        },
        parse_page=lambda response: OfficialPage(
            items=(f"item-{response.page_no}-1", f"item-{response.page_no}-2"),
            total_count=10 if response.page_no == 1 else 8,
        ),
    )

    assert result.request_count == 2
    assert result.raw_count == 4
    assert result.total_count == 8
    assert result.partial_run is True
    assert seen[0]["params"]["serviceKey"] == "secret-key"  # pragma: allowlist secret


def test_weather_merge_uses_public_provider_seam_and_keeps_air_quality_distinct(monkeypatch):
    monkeypatch.setattr(weather_service.db_repository, "fetch_latest_weather", lambda **kw: None)
    monkeypatch.setattr(
        weather_service.weather_providers,
        "fetch_official_weather_pair",
        lambda **kw: (
            {
                "lat": kw["lat"],
                "lng": kw["lng"],
                "location": "기상청 격자",
                "temp": "21",
                "icon": "partly-cloudy",
                "dust": {"grade": "unknown"},
                "forecast": [],
                "outdoor_status": "good",
                "force": kw["force"],
                "location_match": True,
                "record_time": "2026-09-16T09:00:00+09:00",
                "source": weather_service.KMA_SOURCE,
            },
            {
                "sido_name": "서울",
                "location": "중구",
                "record_time": "2026-09-16 09:00",
                "dust": {"grade": "bad", "pm10": "88", "pm25": "21"},
            },
        ),
    )

    payload = weather_service.current_weather(lat=37.56, lng=126.97)

    assert payload["source"] == f"{weather_service.KMA_SOURCE}+{weather_service.AIRKOREA_SOURCE}"
    assert payload["weather_outdoor_status"] == "good"
    assert payload["air_quality_outdoor_status"] == "bad"
    assert payload["outdoor_status"] == "bad"
    assert payload["location"] == "중구"


def test_ai_generation_params_copy_response_format_per_request():
    first = DEFAULT_JSON_GENERATION_PARAMS.to_request_kwargs()
    first["response_format"]["type"] = "mutated"
    second = DEFAULT_JSON_GENERATION_PARAMS.to_request_kwargs()

    assert second["response_format"] == {"type": "json_object"}
    assert second["temperature"] == 0.1
    assert second["max_completion_tokens"] == 4000


def test_cli_lifecycle_redacts_and_records_failed_apply(monkeypatch):
    args = argparse.Namespace(apply=True)
    started_at = datetime(2026, 9, 16, 1, 0, tzinfo=UTC)
    recorded: list[dict] = []

    monkeypatch.setattr(
        batch_helpers,
        "duration_ms",
        lambda started, finished: int((finished - started).total_seconds() * 1000),
    )

    error_message = batch_helpers.redact_cli_error(
        RuntimeError(
            "failed with postgresql://user:secret@example/db"  # pragma: allowlist secret
        ),
        "secret",
    )
    batch_helpers.record_apply_job_failure(
        args=args,
        dsn="postgresql://user:secret@example/db",  # pragma: allowlist secret
        job_name="example-job",
        started_at=started_at,
        error_message=error_message,
        connect_timeout=5,
        record_job_run=lambda **kw: recorded.append(kw),
    )

    assert "secret" not in error_message
    assert recorded[0]["status"] == "failed"
    assert recorded[0]["job_name"] == "example-job"
    assert recorded[0]["error_message"] == error_message


def test_review_apply_rows_are_pure_and_do_not_persist_raw_text():
    candidate = review_attribute_batch.ReviewAttributeCandidate(
        mention_id="11111111-1111-1111-1111-111111111111",
        week_start=date(2026, 9, 14),
        place_id="place-1",
        place_name_ko="샘플",
        provider="blog",
        category="restaurant",
        mention_count=5,
        organic_mention_count=5,
        sentiment_score=0.2,
        attributes={"top_terms": ["맛있"]},
        posts=({"title": "원문 제목", "body": "원문 본문"},),
        source_content_sha256="abc",
        source_name="src",
        license_class="permissive",
        terms_version="v1",
    )
    enrichment = review_attribute_batch.ReviewAttributeEnrichment(
        mention_id=candidate.mention_id,
        schema_version=review_attribute_batch.PROMPT_VERSION,
        sentiment_score=0.3,
        sentiment_confidence=0.8,
        attribute_scores={"taste": 0.9},
        attribute_confidence_avg=0.8,
        evidence_terms={"taste": ["원문"]},
        summary_ko="원문 요약",
        reason="raw reason",
        source_method="openai",
        source_content_sha256="abc",
    )

    rows = review_attribute_batch.build_review_attribute_apply_rows(
        candidates=[candidate],
        enrichments=[enrichment],
        source_method="openai",
    )

    assert len(rows) == 1
    payload = rows[0].review_attributes
    assert "evidence_terms" not in payload
    assert "summary_ko" not in payload
    assert "reason" not in payload
    assert rows[0].review_quality is not None
