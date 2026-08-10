"""Tests for the governed Naver review/mention collector.

No real network calls or DB writes are ever made. All Naver API responses are
stubbed via monkeypatch; all governance/DB/persistence functions are stubbed.
"""

from __future__ import annotations

import hashlib
import io
import json
import urllib.error
from datetime import UTC, datetime

import pytest

from apps.api.app.services import naver_search_service as svc
from apps.api.app.services.naver_search_service import (
    AcquisitionOutcome,
    PlaceCollectionResult,
    TransientNaverPost,
)
from apps.api.app.services.review_ingest_governance import (
    ApprovedReviewAggregate,
    ReviewGovernanceError,
    ReviewIngestResult,
    ReviewIngestRunSummary,
    ReviewSourceRegistration,
)
from apps.api.app.services.review_mention_ingest import ReviewMentionPlace
from apps.api.app.tools import run_naver_review_collect as tool

# -- shared fixtures / helpers -------------------------------------------------

NAVER_LINK = "https://blog.naver.com/post123/456"
PLACE_NAME = "테스트 미술관"


def _registration(
    license_class: str = "licensed",
    terms_version: str = svc.EXPECTED_TERMS_VERSION,
) -> ReviewSourceRegistration:
    return ReviewSourceRegistration(
        source_name=svc.SOURCE_NAME,
        provider=svc.EXPECTED_PROVIDER,
        license_class=license_class,  # type: ignore[arg-type]
        terms_version=terms_version,
        collection_method="naver_search_openapi",
        retention_policy="aggregate_only_no_raw_text",
        redaction_policy="no_raw_text_no_pii",
    )


def _make_outcome(
    provider: str = "naver_blog",
    category: str = "ok",
    retryable: bool = False,
    http_status: int | None = None,
    attempted_count: int = 1,
) -> AcquisitionOutcome:
    return AcquisitionOutcome(
        provider=provider,
        category=category,  # type: ignore[arg-type]
        retryable=retryable,
        http_status=http_status,
        attempted_count=attempted_count,
    )


def _make_post(
    *,
    provider: str = "naver_blog",
    title: str = "좋은 전시 해설",
    description: str = "전시가 정말 좋았습니다",
    link: str = NAVER_LINK,
    postdate: str = "20260801",
    place_id: str = "place-1",
    region: str = "서울",
    category: str = "attraction",
) -> TransientNaverPost:
    cleaned_title = title
    cleaned_desc = description
    sha = hashlib.sha256(f"{cleaned_title} {cleaned_desc}".encode()).hexdigest()
    return TransientNaverPost(
        provider=provider,
        external_key=svc._opaque_external_key(provider, link, postdate),
        keyword=PLACE_NAME,
        place_id=place_id,
        region=region,
        category=category,
        title=title,
        description=description,
        link=link,
        postdate=postdate,
        created_at_source=datetime(2026, 8, 1, tzinfo=UTC),
        content_sha256=sha,
    )


def _make_collection(
    *,
    posts: list[TransientNaverPost] | None = None,
    outcomes: tuple[AcquisitionOutcome, ...] | None = None,
    place_id: str = "place-1",
    place_name: str = PLACE_NAME,
    region: str = "서울",
    category: str = "attraction",
) -> PlaceCollectionResult:
    if posts is None:
        posts = [_make_post()]
    if outcomes is None:
        outcomes = (_make_outcome(),)
    return PlaceCollectionResult(
        place_id=place_id,
        place_name=place_name,
        region=region,
        category=category,
        keyword=place_name,
        outcomes=outcomes,
        posts=tuple(posts),
    )


def _fake_place(
    place_id: str = "place-1",
    name_ko: str = PLACE_NAME,
    category: str = "attraction",
) -> ReviewMentionPlace:
    return ReviewMentionPlace(
        place_id=place_id,
        name_ko=name_ko,
        category=category,
        region_name_ko="서울",
    )


def _fake_ingest_result(
    *,
    processed: int = 0,
    duplicate: int = 0,
    quarantined: int = 0,
    accepted_shas: list[str] | None = None,
) -> ReviewIngestResult:
    accepted: list[ApprovedReviewAggregate] = []
    for sha in accepted_shas or []:
        accepted.append(
            ApprovedReviewAggregate(
                source_name=svc.SOURCE_NAME,
                aggregate_key=f"sha256:{sha[:16]}",
                category="attraction",
                match_confidence=0.92,
            )
        )
    run = ReviewIngestRunSummary(
        run_key="naver_search|2026-08-04|review-ingest-governance-v1",
        source_name=svc.SOURCE_NAME,
        provider=svc.EXPECTED_PROVIDER,
        license_class="licensed",
        terms_version=svc.EXPECTED_TERMS_VERSION,
        schema_version="review-ingest-governance-v1",
        received_count=processed + duplicate + quarantined,
        processed_count=processed,
        duplicate_count=duplicate,
        quarantined_count=quarantined,
        failure_category="none",
        status="succeeded",
    )
    return ReviewIngestResult(run=run, accepted=tuple(accepted), quarantined=())


def _stub_api_items(*items: dict) -> list[dict]:
    return list(items)


def _api_item(
    title: str = "좋은 전시",
    description: str = "전시 해설",
    link: str = NAVER_LINK,
    postdate: str = "20260801",
) -> dict:
    return {
        "title": title,
        "description": description,
        "link": link,
        "postdate": postdate,
    }


# Set credentials so acquire_provider doesn't short-circuit on missing creds.
@pytest.fixture(autouse=True)
def _naver_creds(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NAVER_CLIENT_ID", "test-cid")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "test-csec")


# == Service: compatibility helpers (existing) ================================


def test_clean():
    assert svc._clean("<b>x</b>") == "x"


def test_parse_date():
    assert svc._parse_date("20260704") is not None


# == Service: opaque identity =================================================


def test_opaque_external_key_stable():
    a = svc._opaque_external_key("naver_blog", NAVER_LINK, "20260801")
    b = svc._opaque_external_key("naver_blog", NAVER_LINK, "20260801")
    assert a == b
    assert a.startswith("naver_naver_blog_sha256:")


def test_opaque_external_key_excludes_raw_url():
    key = svc._opaque_external_key("naver_blog", NAVER_LINK, "20260801")
    # The raw URL must never appear in the opaque identity.
    assert "blog.naver.com" not in key
    assert "post123" not in key
    assert "https" not in key


def test_content_sha256_is_hex64():
    sha = svc._content_sha256("전시", "좋은 전시")
    assert len(sha) == 64
    assert all(c in "0123456789abcdef" for c in sha)


# == Service: acquire_provider typed failures =================================


def test_acquire_ok_returns_posts_with_provenance(monkeypatch):
    monkeypatch.setattr(
        svc,
        "_fetch_items",
        lambda *a, **kw: _stub_api_items(_api_item()),
    )
    outcome, posts = svc.acquire_provider(
        endpoint="blog",
        provider="naver_blog",
        query=PLACE_NAME,
        place_id="place-1",
        region="서울",
        category="attraction",
    )
    assert outcome.category == "ok"
    assert outcome.attempted_count == 1
    assert len(posts) == 1
    post = posts[0]
    assert post.place_id == "place-1"
    assert post.region == "서울"
    assert post.category == "attraction"
    assert post.keyword == PLACE_NAME


def test_acquire_auth_missing_no_credentials(monkeypatch):
    monkeypatch.delenv("NAVER_CLIENT_ID", raising=False)
    monkeypatch.delenv("NAVER_CLIENT_SECRET", raising=False)
    outcome, posts = svc.acquire_provider(
        endpoint="blog",
        provider="naver_blog",
        query=PLACE_NAME,
        place_id="place-1",
        region="서울",
        category="attraction",
    )
    assert outcome.category == "auth_missing"
    assert outcome.retryable is False
    assert posts == []


@pytest.mark.parametrize(
    ("exc_factory", "expected_category", "expected_retryable"),
    [
        (
            lambda: urllib.error.HTTPError("u", 401, "Unauthorized", {}, io.BytesIO(b"")),
            "auth_missing",
            False,
        ),
        (
            lambda: urllib.error.HTTPError("u", 403, "Forbidden", {}, io.BytesIO(b"")),
            "auth_missing",
            False,
        ),
        (
            lambda: urllib.error.HTTPError("u", 429, "Too Many", {}, io.BytesIO(b"")),
            "quota_exceeded",
            True,
        ),
        (
            lambda: urllib.error.HTTPError("u", 500, "Server Error", {}, io.BytesIO(b"")),
            "network_error",
            True,
        ),
        (
            lambda: urllib.error.URLError("timeout"),
            "network_error",
            True,
        ),
        (
            lambda: TimeoutError("timed out"),
            "network_error",
            True,
        ),
        (
            lambda: json.JSONDecodeError("msg", "doc", 0),
            "parse_error",
            False,
        ),
    ],
    ids=["http401", "http403", "http429", "http500", "urlerror", "timeout", "jsondecode"],
)
def test_acquire_provider_failure_categories(
    monkeypatch, exc_factory, expected_category, expected_retryable
):
    def raising_fetch(*a, **kw):
        raise exc_factory()

    monkeypatch.setattr(svc, "_fetch_items", raising_fetch)
    outcome, posts = svc.acquire_provider(
        endpoint="blog",
        provider="naver_blog",
        query=PLACE_NAME,
        place_id="place-1",
        region="서울",
        category="attraction",
    )
    assert outcome.category == expected_category
    assert outcome.retryable is expected_retryable
    assert posts == []
    # No raw payload fields on the outcome.
    for field in ("title", "body", "post_url", "url", "payload", "raw"):
        assert not hasattr(outcome, field) or getattr(outcome, field) is None


def test_acquire_empty_results(monkeypatch):
    monkeypatch.setattr(svc, "_fetch_items", lambda *a, **kw: [])
    outcome, posts = svc.acquire_provider(
        endpoint="blog",
        provider="naver_blog",
        query=PLACE_NAME,
        place_id="place-1",
        region="서울",
        category="attraction",
    )
    assert outcome.category == "empty"
    assert posts == []


def test_outcome_has_no_raw_payload_fields():
    """AcquisitionOutcome must never carry raw text/URL data."""
    outcome = _make_outcome()
    raw_fields = {"title", "body", "post_url", "url", "payload", "raw_text", "description"}
    assert not (raw_fields & set(outcome.__dataclass_fields__))


# == Service: collect_mentions_for_place ======================================


def test_collect_mentions_provenance_and_two_outcomes(monkeypatch):
    blog_items = [_api_item(title="전시 해설")]
    cafe_items = [_api_item(title="좋은 카페")]

    def fake_fetch(endpoint, query, display, timeout, cid, csec):
        return blog_items if endpoint == "blog" else cafe_items

    monkeypatch.setattr(svc, "_fetch_items", fake_fetch)
    result = svc.collect_mentions_for_place(
        place_id="place-1",
        place_name=PLACE_NAME,
        region="서울",
        category="attraction",
    )
    assert len(result.outcomes) == 2
    assert {o.provider for o in result.outcomes} == {"naver_blog", "naver_cafe"}
    assert all(o.category == "ok" for o in result.outcomes)
    for post in result.posts:
        assert post.place_id == "place-1"
        assert post.region == "서울"
        assert post.category == "attraction"
        # Raw URL never in external_key.
        assert "blog.naver.com" not in post.external_key


# == Tool: DG-1 gate fail-closed ===============================================


@pytest.mark.parametrize(
    ("gate_func", "expected_code"),
    [
        (
            lambda: ReviewGovernanceError("source_not_registered", "not registered"),
            "source_not_registered",
        ),
        (
            lambda: ReviewGovernanceError("source_disabled", "disabled"),
            "source_disabled",
        ),
        (
            lambda: ReviewGovernanceError("source_license_rejected", "rejected"),
            "source_license_rejected",
        ),
        (
            lambda: ReviewGovernanceError("source_provider_mismatch", "wrong provider"),
            "source_provider_mismatch",
        ),
        (
            lambda: ReviewGovernanceError("source_terms_mismatch", "wrong terms"),
            "source_terms_mismatch",
        ),
    ],
    ids=["not_registered", "disabled", "rejected", "provider_mismatch", "terms_mismatch"],
)
def test_dg1_gate_fail_closed(monkeypatch, capsys, gate_func, expected_code):
    """Gate failure ⇒ no acquisition, no write, governance code surfaced."""
    acquire_calls: list[dict] = []

    def fake_gate(**kw):
        raise gate_func()

    monkeypatch.setattr(tool, "_check_gate", fake_gate)
    monkeypatch.setattr(
        tool,
        "collect_mentions_for_place",
        lambda **kw: acquire_calls.append(kw) or _make_collection(),
    )
    monkeypatch.setattr(tool, "persist_review_ingest_run", lambda **kw: _fake_ingest_result())
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", lambda **kw: 0)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")

    rc = tool.main(["--preview", "--json"])
    assert rc == 2
    out = json.loads(capsys.readouterr().out)
    assert out["ok"] is False
    assert out["governance_code"] == expected_code
    # Acquisition was never called.
    assert acquire_calls == []


# == Tool: non-mutating preview ===============================================


def test_non_mutating_preview_no_writes(monkeypatch, capsys):
    write_calls: list[str] = []

    monkeypatch.setattr(tool, "_check_gate", lambda **kw: _registration())
    monkeypatch.setattr(tool, "_read_places", lambda **kw: [_fake_place()])
    monkeypatch.setattr(tool, "collect_mentions_for_place", lambda **kw: _make_collection())

    def guard_persist(**kw):
        write_calls.append("persist")

    def guard_insert(**kw):
        write_calls.append("insert")

    def guard_job_run(**kw):
        write_calls.append("job_run")

    monkeypatch.setattr(tool, "persist_review_ingest_run", guard_persist)
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", guard_insert)
    monkeypatch.setattr(tool, "record_job_run", guard_job_run)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    assert write_calls == []


# == Tool: redaction (no raw text in stdout) ==================================


def test_preview_redaction_no_raw_text(monkeypatch, capsys):
    """Preview stdout must contain no title/body/url — counts only."""
    ad_post = _make_post(title="네이버 블로그 광고", description=NAVER_LINK, link=NAVER_LINK)
    result = _make_collection(posts=[ad_post])
    monkeypatch.setattr(tool, "_check_gate", lambda **kw: _registration())
    monkeypatch.setattr(tool, "_read_places", lambda **kw: [_fake_place()])
    monkeypatch.setattr(tool, "collect_mentions_for_place", lambda **kw: result)
    monkeypatch.setattr(tool, "persist_review_ingest_run", lambda **kw: _fake_ingest_result())
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", lambda **kw: 0)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    stdout = capsys.readouterr().out
    assert NAVER_LINK not in stdout
    assert "blog.naver.com" not in stdout
    assert "광고" not in stdout
    assert "네이버 블로그" not in stdout


def test_apply_redaction_no_raw_text(monkeypatch, capsys):
    """Apply stdout must contain no title/body/url — counts only."""
    organic_post = _make_post(title="좋은 전시 해설", description="전시가 정말 좋았습니다")
    result = _make_collection(posts=[organic_post])
    sha = organic_post.content_sha256
    monkeypatch.setattr(tool, "_check_gate", lambda **kw: _registration())
    monkeypatch.setattr(tool, "_read_places", lambda **kw: [_fake_place()])
    monkeypatch.setattr(tool, "collect_mentions_for_place", lambda **kw: result)
    monkeypatch.setattr(
        tool,
        "persist_review_ingest_run",
        lambda **kw: _fake_ingest_result(processed=1, accepted_shas=[sha]),
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", lambda **kw: 1)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    stdout = capsys.readouterr().out
    assert "좋은 전시" not in stdout
    assert "전시가" not in stdout
    assert NAVER_LINK not in stdout
    assert "blog.naver.com" not in stdout


# == Tool: accurate counts from governance result ============================


def test_accurate_counts_from_governance_result(monkeypatch, capsys):
    """processed/duplicate/quarantined come from the stub, not len(records)."""
    # 3 posts but governance reports 1 processed, 2 duplicate.
    posts = [
        _make_post(title=f"전시 해설 {i}", description=f"내용 {i}", link=f"{NAVER_LINK}/{i}")
        for i in range(3)
    ]
    result = _make_collection(posts=posts)
    first_sha = posts[0].content_sha256
    monkeypatch.setattr(tool, "_check_gate", lambda **kw: _registration())
    monkeypatch.setattr(tool, "_read_places", lambda **kw: [_fake_place()])
    monkeypatch.setattr(tool, "collect_mentions_for_place", lambda **kw: result)
    monkeypatch.setattr(
        tool,
        "persist_review_ingest_run",
        lambda **kw: _fake_ingest_result(
            processed=1, duplicate=2, quarantined=0, accepted_shas=[first_sha]
        ),
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", lambda **kw: 1)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["processed"] == 1
    assert out["duplicate"] == 2
    assert out["quarantined"] == 0
    # organic is the pre-governance retained count (all 3 here).
    assert out["organic"] == 3
    assert out["candidates"] == 3


# == Tool: ad-filtering excludes ads from organic =============================


def test_ad_filtered_excluded_from_organic(monkeypatch, capsys):
    """Ad-bearing candidates must be excluded from the organic count."""
    ad_post = _make_post(
        title="협찬 광고 체험단",
        description="제공받아 작성한 광고입니다",
        link=f"{NAVER_LINK}/ad",
    )
    organic_post = _make_post(
        title="좋은 전시 해설",
        description="전시가 정말 좋았습니다",
        link=f"{NAVER_LINK}/org",
    )
    result = _make_collection(posts=[ad_post, organic_post])
    monkeypatch.setattr(tool, "_check_gate", lambda **kw: _registration())
    monkeypatch.setattr(tool, "_read_places", lambda **kw: [_fake_place()])
    monkeypatch.setattr(tool, "collect_mentions_for_place", lambda **kw: result)
    monkeypatch.setattr(tool, "persist_review_ingest_run", lambda **kw: _fake_ingest_result())
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", lambda **kw: 0)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["candidates"] == 2
    assert out["ad_filtered_out"] == 1
    assert out["organic"] == 1


# == Tool: idempotency ========================================================


def test_idempotent_rerun_zero_new_aggregates(monkeypatch, capsys):
    """Re-running the same window ⇒ 0 processed, accurate duplicate, 0 aggregates."""
    organic_post = _make_post(title="좋은 전시 해설", description="전시가 좋았습니다")
    result = _make_collection(posts=[organic_post])
    monkeypatch.setattr(tool, "_check_gate", lambda **kw: _registration())
    monkeypatch.setattr(tool, "_read_places", lambda **kw: [_fake_place()])
    monkeypatch.setattr(tool, "collect_mentions_for_place", lambda **kw: result)

    insert_calls: list = []

    def fake_insert(**kw):
        insert_calls.append(kw.get("aggregates", ()))
        return 0

    monkeypatch.setattr(
        tool,
        "persist_review_ingest_run",
        lambda **kw: _fake_ingest_result(processed=0, duplicate=1),
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates", fake_insert)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["processed"] == 0
    assert out["duplicate"] == 1
    assert out["aggregated"] == 0
    assert out["inserted_rows"] == 0
    # insert was called with zero aggregates.
    assert len(insert_calls) == 1
    assert insert_calls[0] == []
