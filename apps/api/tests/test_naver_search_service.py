"""Tests for the governed Naver review/mention collector.

No real network calls or DB writes are ever made. All Naver API responses are
stubbed via monkeypatch; all governance/DB/persistence functions are stubbed.
The atomicity test uses a rollback-aware fake connection that models the
transaction boundary so receipts + aggregates are verified to commit/rollback
as ONE unit.
"""

from __future__ import annotations

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
    ReviewSourceRecord,
    ReviewSourceRegistration,
)
from apps.api.app.services.review_mention_ingest import ReviewMentionPlace
from apps.api.app.tools import run_naver_review_collect as tool

# -- shared fixtures / helpers -------------------------------------------------

NAVER_LINK = "https://blog.naver.com/post123/456"
PLACE_NAME = "테스트 미술관"


@pytest.fixture(autouse=True)
def _naver_creds(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NAVER_CLIENT_ID", "test-cid")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "test-csec")


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
    keyword: str = PLACE_NAME,
) -> TransientNaverPost:
    return TransientNaverPost(
        provider=provider,
        external_key=svc._opaque_external_key(
            provider=provider, link=link, postdate=postdate, place_id=place_id
        ),
        keyword=keyword,
        place_id=place_id,
        region=region,
        category=category,
        title=title,
        description=description,
        link=link,
        postdate=postdate,
        created_at_source=datetime(2026, 8, 1, tzinfo=UTC),
        content_sha256=svc._content_sha256(
            provider=provider,
            link=link,
            postdate=postdate,
            place_id=place_id,
            title=title,
            description=description,
        ),
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
    accepted_record_shas: list[str] | None = None,
) -> ReviewIngestResult:
    shas = accepted_record_shas or []
    accepted_records = tuple(
        ReviewSourceRecord(
            source_name=svc.SOURCE_NAME,
            provider=svc.EXPECTED_PROVIDER,
            external_key=f"naver_naver_blog_sha256:{sha}",
            license_class="licensed",
            terms_version=svc.EXPECTED_TERMS_VERSION,
            content_sha256=sha,
            received_at=datetime(2026, 8, 1, tzinfo=UTC),
            category="attraction",
            match_confidence=0.92,
            is_organic=True,
        )
        for sha in shas
    )
    accepted = tuple(
        ApprovedReviewAggregate(
            source_name=svc.SOURCE_NAME,
            aggregate_key=f"sha256:{sha[:16]}",
            category="attraction",
            match_confidence=0.92,
        )
        for sha in shas
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
    return ReviewIngestResult(
        run=run, accepted=accepted, accepted_records=accepted_records, quarantined=()
    )


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


# -- fake connection for atomicity tests (models commit/rollback boundary) -----


class _FakeCursor:
    def __init__(self, conn: _FakeConn) -> None:
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class _FakeConn:
    """Models a psycopg2 connection's transaction boundary.

    On clean ``with conn:`` exit: moves pending receipts/aggregates to committed
    lists. On exception: clears pending state (rollback). This lets the atomicity
    test verify that no receipts survive a failed aggregate upsert.
    """

    def __init__(self) -> None:
        self.committed = False
        self.rolled_back = False
        self.committed_receipts: list = []
        self.committed_aggregates: list = []
        self._pending_receipts: list = []
        self._pending_aggregates: list = []

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self)

    def close(self) -> None:
        pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, *args):
        if exc_type is None:
            self.committed = True
            self.committed_receipts.extend(self._pending_receipts)
            self.committed_aggregates.extend(self._pending_aggregates)
            self._pending_receipts = []
            self._pending_aggregates = []
        else:
            self.rolled_back = True
            self._pending_receipts = []
            self._pending_aggregates = []
        return False


def _setup_tool_monkeypatch(
    monkeypatch: pytest.MonkeyPatch,
    *,
    places: list[ReviewMentionPlace] | None = None,
    collection: PlaceCollectionResult | None = None,
    collection_fn=None,
    fake_conn: _FakeConn | None = None,
    gate_error: ReviewGovernanceError | None = None,
) -> _FakeConn:
    """Wire up the tool's external dependencies for unit testing."""
    conn = fake_conn or _FakeConn()
    monkeypatch.setattr(tool, "_open_connection", lambda dsn, ct: conn)

    if gate_error is not None:

        def _raise(*a, **kw):
            raise gate_error

        monkeypatch.setattr(tool, "load_active_review_source", _raise)
    else:
        reg = _registration()
        monkeypatch.setattr(tool, "load_active_review_source", lambda *a, **kw: reg)

    monkeypatch.setattr(
        tool, "_read_places_on_cursor", lambda cur, limit: places or [_fake_place()]
    )
    if collection_fn is not None:
        monkeypatch.setattr(tool, "collect_mentions_for_place", collection_fn)
    else:
        monkeypatch.setattr(
            tool, "collect_mentions_for_place", lambda **kw: collection or _make_collection()
        )
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")
    return conn


# == Service: compatibility helpers ===========================================


def test_clean():
    assert svc._clean("<b>x</b>") == "x"


def test_parse_date():
    assert svc._parse_date("20260704") is not None


# == Service: opaque place-aware full digests =================================


def test_opaque_external_key_stable():
    a = svc._opaque_external_key(
        provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="p1"
    )
    b = svc._opaque_external_key(
        provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="p1"
    )
    assert a == b
    assert a.startswith("naver_naver_blog_sha256:")


def test_opaque_external_key_excludes_raw_url():
    key = svc._opaque_external_key(
        provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="p1"
    )
    assert "blog.naver.com" not in key
    assert "post123" not in key
    assert "https" not in key


def test_external_key_is_full_64_hex():
    """P2 fix: digest is full 64 hex chars, not truncated to 16."""
    key = svc._opaque_external_key(
        provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="p1"
    )
    digest = key.split(":", 1)[1]
    assert len(digest) == 64
    assert all(c in "0123456789abcdef" for c in digest)


def test_content_sha256_is_hex64():
    sha = svc._content_sha256(
        provider="naver_blog",
        link=NAVER_LINK,
        postdate="20260801",
        place_id="p1",
        title="전시",
        description="좋은 전시",
    )
    assert len(sha) == 64
    assert all(c in "0123456789abcdef" for c in sha)


def test_content_sha256_place_aware():
    """P1b fix: same post for two places yields distinct content_sha256."""
    sha1 = svc._content_sha256(
        provider="naver_blog",
        link=NAVER_LINK,
        postdate="20260801",
        place_id="place-1",
        title="전시",
        description="좋았다",
    )
    sha2 = svc._content_sha256(
        provider="naver_blog",
        link=NAVER_LINK,
        postdate="20260801",
        place_id="place-2",
        title="전시",
        description="좋았다",
    )
    assert sha1 != sha2


def test_external_key_place_aware():
    """P1b fix: same post for two places yields distinct external_key."""
    key1 = svc._opaque_external_key(
        provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="place-1"
    )
    key2 = svc._opaque_external_key(
        provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="place-2"
    )
    assert key1 != key2


def test_same_post_same_place_identical():
    """Deterministic: same input+place always produces the same keys."""
    kwargs = dict(provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id="p1")
    assert svc._opaque_external_key(**kwargs) == svc._opaque_external_key(**kwargs)


# == Service: acquire_provider typed failures =================================


def test_acquire_ok_returns_posts_with_provenance(monkeypatch):
    monkeypatch.setattr(svc, "_fetch_items", lambda *a, **kw: [_api_item()])
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
        assert "blog.naver.com" not in post.external_key
        digest = post.external_key.split(":", 1)[1]
        assert len(digest) == 64


# == Tool: DG-1 gate fail-closed ===============================================


@pytest.mark.parametrize(
    ("gate_error", "expected_code"),
    [
        (
            ReviewGovernanceError("source_not_registered", "not registered"),
            "source_not_registered",
        ),
        (
            ReviewGovernanceError("source_disabled", "disabled"),
            "source_disabled",
        ),
        (
            ReviewGovernanceError("source_license_rejected", "rejected"),
            "source_license_rejected",
        ),
        (
            ReviewGovernanceError("source_provider_mismatch", "wrong provider"),
            "source_provider_mismatch",
        ),
        (
            ReviewGovernanceError("source_terms_mismatch", "wrong terms"),
            "source_terms_mismatch",
        ),
    ],
    ids=["not_registered", "disabled", "rejected", "provider_mismatch", "terms_mismatch"],
)
def test_dg1_gate_fail_closed(monkeypatch, capsys, gate_error, expected_code):
    """Gate failure => no acquisition, no write, governance code surfaced."""
    acquire_calls: list[dict] = []
    monkeypatch.setattr(
        tool,
        "collect_mentions_for_place",
        lambda **kw: acquire_calls.append(kw) or _make_collection(),
    )
    monkeypatch.setattr(
        tool, "govern_review_ingest_on_cursor", lambda cur, **kw: _fake_ingest_result()
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", lambda cur, aggs: 0)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    _setup_tool_monkeypatch(monkeypatch, gate_error=gate_error)

    rc = tool.main(["--preview", "--json"])
    assert rc == 2
    out = json.loads(capsys.readouterr().out)
    assert out["ok"] is False
    assert out["governance_code"] == expected_code
    assert acquire_calls == []


# == Tool: non-mutating preview ===============================================


def test_non_mutating_preview_no_writes(monkeypatch, capsys):
    write_calls: list[str] = []

    def fake_govern(cur, **kw):
        write_calls.append("govern")
        return _fake_ingest_result()

    monkeypatch.setattr(tool, "govern_review_ingest_on_cursor", fake_govern)
    monkeypatch.setattr(
        tool,
        "insert_review_mention_aggregates_on_cursor",
        lambda cur, aggs: write_calls.append("insert") or 0,
    )
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: write_calls.append("job_run"))
    _setup_tool_monkeypatch(monkeypatch)

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    assert write_calls == []


# == Tool: redaction (no raw text in stdout) ==================================


def test_preview_redaction_no_raw_text(monkeypatch, capsys):
    ad_post = _make_post(title="네이버 블로그 광고", description=NAVER_LINK, link=NAVER_LINK)
    result = _make_collection(posts=[ad_post])
    _setup_tool_monkeypatch(monkeypatch, collection=result)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    stdout = capsys.readouterr().out
    assert NAVER_LINK not in stdout
    assert "blog.naver.com" not in stdout
    assert "광고" not in stdout
    assert "네이버 블로그" not in stdout


def test_apply_redaction_no_raw_text(monkeypatch, capsys):
    organic_post = _make_post(title="좋은 전시 해설", description="전시가 정말 좋았습니다")
    result = _make_collection(posts=[organic_post])
    sha = organic_post.content_sha256
    _setup_tool_monkeypatch(monkeypatch, collection=result)
    monkeypatch.setattr(
        tool,
        "govern_review_ingest_on_cursor",
        lambda cur, **kw: _fake_ingest_result(processed=1, accepted_record_shas=[sha]),
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", lambda cur, aggs: 1)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
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
    posts = [
        _make_post(title=f"전시 해설 {i}", description=f"내용 {i}", link=f"{NAVER_LINK}/{i}")
        for i in range(3)
    ]
    result = _make_collection(posts=posts)
    first_sha = posts[0].content_sha256
    _setup_tool_monkeypatch(monkeypatch, collection=result)
    monkeypatch.setattr(
        tool,
        "govern_review_ingest_on_cursor",
        lambda cur, **kw: _fake_ingest_result(
            processed=1, duplicate=2, quarantined=0, accepted_record_shas=[first_sha]
        ),
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", lambda cur, aggs: 1)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["processed"] == 1
    assert out["duplicate"] == 2
    assert out["quarantined"] == 0
    assert out["organic"] == 3
    assert out["candidates"] == 3


# == Tool: ad-filtering excludes ads from organic =============================


def test_ad_filtered_excluded_from_organic(monkeypatch, capsys):
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
    _setup_tool_monkeypatch(monkeypatch, collection=result)

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["candidates"] == 2
    assert out["ad_filtered_out"] == 1
    assert out["organic"] == 1


# == Tool: idempotency ========================================================


def test_idempotent_rerun_zero_new_aggregates(monkeypatch, capsys):
    organic_post = _make_post(title="좋은 전시 해설", description="전시가 좋았습니다")
    result = _make_collection(posts=[organic_post])
    _setup_tool_monkeypatch(monkeypatch, collection=result)

    insert_calls: list = []

    def fake_insert(cur, aggregates):
        insert_calls.append(list(aggregates))
        return 0

    monkeypatch.setattr(
        tool,
        "govern_review_ingest_on_cursor",
        lambda cur, **kw: _fake_ingest_result(processed=0, duplicate=1),
    )
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", fake_insert)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["processed"] == 0
    assert out["duplicate"] == 1
    assert out["aggregated"] == 0
    assert out["inserted_rows"] == 0
    assert len(insert_calls) == 1
    assert insert_calls[0] == []


# == Tool: atomicity / idempotent recovery (P1a fix) =========================


def test_atomicity_rollback_and_recovery(monkeypatch, capsys):
    """Receipts + aggregates commit/rollback as ONE unit. A failed aggregate
    upsert rolls back ALL receipts; a clean re-run fully recovers."""
    organic_post = _make_post(title="좋은 전시 해설", description="전시가 정말 좋았습니다")
    result = _make_collection(posts=[organic_post])
    fake_conn = _FakeConn()
    _setup_tool_monkeypatch(monkeypatch, collection=result, fake_conn=fake_conn)

    insert_call_count = {"n": 0}

    def fake_govern(cur, **kw):
        records = kw.get("records", [])
        cur.conn._pending_receipts.extend(records)
        return _fake_ingest_result(
            processed=len(records),
            accepted_record_shas=[r["content_sha256"] for r in records],
        )

    def fake_insert(cur, aggregates):
        insert_call_count["n"] += 1
        if insert_call_count["n"] == 1:
            raise RuntimeError("aggregate upsert exploded")
        cur.conn._pending_aggregates.extend(aggregates)
        return len(aggregates)

    monkeypatch.setattr(tool, "govern_review_ingest_on_cursor", fake_govern)
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", fake_insert)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    # --- First run: aggregate upsert fails -> rollback ---
    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 2
    assert fake_conn.rolled_back
    assert len(fake_conn.committed_receipts) == 0
    assert len(fake_conn.committed_aggregates) == 0

    # --- Second run: succeeds -> commit (full recovery) ---
    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    assert len(fake_conn.committed_receipts) > 0
    assert len(fake_conn.committed_aggregates) > 0


# == Tool: two-place same-post provenance (P1b fix) ===========================


def test_two_places_same_post_both_aggregated(monkeypatch, capsys):
    """The same Naver post for two distinct places yields two DISTINCT
    content_sha256/external_key, two accepted records, and BOTH places get an
    aggregate."""
    place1 = _fake_place(place_id="place-1", name_ko="장소1미술관")
    place2 = _fake_place(place_id="place-2", name_ko="장소2미술관")

    post1 = _make_post(
        place_id="place-1",
        keyword="장소1미술관",
        title="좋은 전시 해설",
        description="전시가 정말 좋았습니다",
    )
    post2 = _make_post(
        place_id="place-2",
        keyword="장소2미술관",
        title="좋은 전시 해설",
        description="전시가 정말 좋았습니다",
    )
    assert post1.content_sha256 != post2.content_sha256
    assert post1.external_key != post2.external_key

    def fake_collect(**kw):
        pid = kw.get("place_id")
        if pid == "place-1":
            return _make_collection(posts=[post1], place_id="place-1", place_name="장소1미술관")
        return _make_collection(posts=[post2], place_id="place-2", place_name="장소2미술관")

    _setup_tool_monkeypatch(monkeypatch, places=[place1, place2], collection_fn=fake_collect)

    inserted_aggregates: list = []

    def fake_govern(cur, **kw):
        records = kw.get("records", [])
        return _fake_ingest_result(
            processed=len(records),
            accepted_record_shas=[r["content_sha256"] for r in records],
        )

    def fake_insert(cur, aggregates):
        inserted_aggregates.extend(aggregates)
        return len(aggregates)

    monkeypatch.setattr(tool, "govern_review_ingest_on_cursor", fake_govern)
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", fake_insert)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT])
    assert rc == 0
    place_ids = {agg.place_id for agg in inserted_aggregates}
    assert place_ids == {"place-1", "place-2"}


# == Tool: partial-failure degradation (P-add fix) ============================


def test_partial_failure_degraded(monkeypatch, capsys):
    """One provider ok + one provider failed -> status degraded, healthy data
    still aggregated."""
    ok = _make_outcome(provider="naver_blog", category="ok")
    failed = _make_outcome(
        provider="naver_cafe", category="quota_exceeded", retryable=True, http_status=429
    )
    organic_post = _make_post()
    result = _make_collection(posts=[organic_post], outcomes=(ok, failed))
    _setup_tool_monkeypatch(monkeypatch, collection=result)

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["status"] == "degraded"
    assert out["failure_tally"]["naver_cafe"]["quota_exceeded"] == 1
    assert out["failure_tally"]["naver_blog"]["ok"] == 1


def test_all_providers_failed(monkeypatch, capsys):
    """All providers failed -> status failed."""
    failed1 = _make_outcome(provider="naver_blog", category="auth_missing")
    failed2 = _make_outcome(provider="naver_cafe", category="network_error", retryable=True)
    result = _make_collection(posts=(), outcomes=(failed1, failed2))
    _setup_tool_monkeypatch(monkeypatch, collection=result)

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["status"] == "failed"


def test_clean_run_succeeded(monkeypatch, capsys):
    """All providers ok/empty, no quarantine -> status succeeded."""
    ok = _make_outcome(provider="naver_blog", category="ok")
    empty = _make_outcome(provider="naver_cafe", category="empty", attempted_count=0)
    organic_post = _make_post()
    result = _make_collection(posts=[organic_post], outcomes=(ok, empty))
    _setup_tool_monkeypatch(monkeypatch, collection=result)

    rc = tool.main(["--preview", "--json"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["status"] == "succeeded"
