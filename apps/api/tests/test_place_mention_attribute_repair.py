from __future__ import annotations

import hashlib
import json
import sys
from types import SimpleNamespace

from apps.api.app.services import place_mention_attribute_repair as repair
from apps.api.app.services import review_mention_ingest
from apps.api.app.tools import run_place_mention_attribute_repair as tool

# Obviously-fake test hosts only (example.invalid) so no fixture string can
# trip detect-secrets with a real-looking secret.
_FAKE_URL_A = "https://example.invalid/post/123?x=1"
_FAKE_URL_B = "https://example.invalid/post/456?q=ad#section"


# --- detection: recursive, value-form, mixed safe+unsafe ---


def test_detects_url_shaped_values_at_any_depth():
    attributes = {
        "preprocess": {
            "retained_external_keys": [_FAKE_URL_A, "not-a-url-key-1"],
            "nested": {"filtered_external_keys": [_FAKE_URL_B]},
        },
        "top_terms": ["커피", "디저트"],
        "organic_review_count": 3,
    }

    findings = repair.find_unsafe_values(attributes, provider="naver_blog")

    paths = {tuple(finding.path) for finding in findings}
    assert len(findings) == 2
    assert ("preprocess", "retained_external_keys", "0") in paths
    assert ("preprocess", "nested", "filtered_external_keys", "0") in paths
    # Detection is by VALUE form, not key allowlist: any key, any depth.
    assert repair.is_url_shaped(_FAKE_URL_A)
    assert repair.is_url_shaped("www.example.invalid/path")
    assert not repair.is_url_shaped("not-a-url-key-1")
    assert not repair.is_url_shaped(123)
    assert not repair.is_url_shaped(None)


def test_detects_bare_authority_and_scheme_forms():
    assert repair.is_url_shaped("http://example.invalid/a")
    assert repair.is_url_shaped("ftp://files.example.invalid/x.txt")
    assert repair.is_url_shaped("example.invalid/path")
    assert repair.is_url_shaped("www.example.invalid")
    assert not repair.is_url_shaped("호암미술관")
    assert not repair.is_url_shaped("naver_blog")


def test_redaction_replaces_urls_with_provider_scoped_digests():
    attributes = {
        "preprocess": {"retained_external_keys": [_FAKE_URL_A, "plain-key"]},
        "top_terms": ["커피"],
    }

    repaired, changed = repair.redact_unsafe_values(attributes, provider="naver_blog")

    assert changed is True
    values = repaired["preprocess"]["retained_external_keys"]
    assert values == [repair.safe_digest("naver_blog", _FAKE_URL_A), "plain-key"]
    serialized = json.dumps(repaired, ensure_ascii=False)
    assert "example.invalid" not in serialized
    assert _FAKE_URL_A not in serialized
    # Safe sibling data untouched.
    assert repaired["top_terms"] == ["커피"]


def test_repair_digest_matches_the_s1_ingest_digest_exactly():
    """Consumer compatibility: the repair must write the SAME digest the S1
    ingest writes, because review_attribute_batch joins on that digest."""
    provider = "naver_blog"
    assert repair.safe_digest(provider, _FAKE_URL_A) == (
        review_mention_ingest.external_key_sha256(provider, _FAKE_URL_A)
    )
    # And the fail-closed bound agrees with the S1 constant.
    assert repair._HASH_INPUT_MAX == review_mention_ingest._EXTERNAL_KEY_HASH_INPUT_MAX


def test_redaction_is_idempotent():
    attributes = {"preprocess": {"retained_external_keys": [_FAKE_URL_A]}}
    once, _ = repair.redact_unsafe_values(attributes, provider="naver_blog")

    twice, changed_again = repair.redact_unsafe_values(once, provider="naver_blog")

    assert changed_again is False
    assert once == twice
    assert repair.find_unsafe_values(once, provider="naver_blog") == []


def test_over_bound_value_is_dropped_not_truncate_hashed():
    """Material over 4096 chars must be dropped — never collide with a prefix."""
    provider = "naver_blog"
    bound = repair._HASH_INPUT_MAX
    over = "https://example.invalid/overbound?" + "z" * bound
    at_limit = "https://example.invalid/at-limit/" + "k" * (
        bound - len(provider) - len("https://example.invalid/at-limit/") - 1
    )  # material exactly at the bound

    assert len(f"{provider}|{at_limit}") == bound
    assert repair.safe_digest(provider, at_limit) is not None
    assert repair.safe_digest(provider, over) is None

    attributes = {"preprocess": {"retained_external_keys": [over, at_limit]}}
    repaired, _ = repair.redact_unsafe_values(attributes, provider=provider)
    values = repaired["preprocess"]["retained_external_keys"]
    # Over-bound slot is REMOVED (no placeholder residue); at-limit digested.
    assert values == [repair.safe_digest(provider, at_limit)]
    assert over not in json.dumps(repaired)
    assert len(values) == 1


def test_two_long_keys_sharing_prefix_cannot_collide():
    """The controller-audit defect class: 4097-char keys sharing a 4096 prefix."""
    provider = "naver_blog"
    bound = repair._HASH_INPUT_MAX
    prefix_len = bound - len(provider) - 1 - len("https://example.invalid/p/")
    prefix = "https://example.invalid/p/" + "z" * prefix_len
    key_a = prefix + "a"  # material 4097
    key_b = prefix + "b"  # material 4097, same 4096-char prefix

    # Both over-bound -> both dropped -> neither can alias the other's digest.
    assert repair.safe_digest(provider, key_a) is None
    assert repair.safe_digest(provider, key_b) is None
    repaired, _ = repair.redact_unsafe_values(
        {"preprocess": {"retained_external_keys": [key_a, key_b]}}, provider=provider
    )
    serialized = json.dumps(repaired)
    assert key_a not in serialized and key_b not in serialized
    assert "example.invalid" not in serialized


def test_drop_prunes_emptied_container_but_preserves_preexisting_empty():
    provider = "naver_blog"
    bound = repair._HASH_INPUT_MAX
    over = "https://example.invalid/only-overbound?" + "z" * bound

    attributes = {
        "preprocess": {"retained_external_keys": [over]},  # emptied by the drop
        "already_empty": [],
        "prune_me": [over],  # array emptied by the drop
    }

    repaired, changed = repair.redact_unsafe_values(attributes, provider=provider)

    assert changed is True
    # Keys whose containers were EMPTIED BY THE DROP are pruned entirely —
    # no empty-string residue and no emptied container left behind.
    assert "preprocess" not in repaired
    assert "prune_me" not in repaired
    assert repaired == {"already_empty": []}
    # A container that was empty BEFORE repair stays as-is (no rewrite).
    assert repaired["already_empty"] == []


# --- row planning + aggregate-safe report shape ---


def test_plan_row_repair_reports_counts_and_checksums_only():
    attributes = {
        "preprocess": {
            "retained_external_keys": [_FAKE_URL_A, _FAKE_URL_B],
            "schema_version": "review-mention-preprocess-v1",
        },
        "organic_review_count": 3,
    }

    plan = repair.plan_row_repair(
        mention_id="11111111-1111-1111-1111-111111111111",
        place_id="place-1",
        week_start="2026-06-22",
        provider="naver_blog",
        attributes=attributes,
    )

    assert plan is not None
    assert plan.unsafe_value_count == 2
    assert plan.replace_count == 2
    assert plan.drop_count == 0
    assert plan.before_sha256 != plan.after_sha256
    serialized = json.dumps(
        [{"path": list(f.path), "digest": f.digest} for f in plan.findings],
        ensure_ascii=False,
    )
    assert "example.invalid" not in serialized  # paths + digests only, never values

    summary = repair.summarize_row_plans([plan], scanned_row_count=5)
    assert summary["scanned_row_count"] == 5
    assert summary["affected_row_count"] == 1
    assert summary["unsafe_value_count"] == 2
    assert summary["field_breakdown"] == {"preprocess": 2}
    assert "example.invalid" not in json.dumps(summary)


def test_clean_row_produces_no_plan():
    attributes = {"preprocess": {"retained_external_keys": ["abc123", "def456"]}}

    assert (
        repair.plan_row_repair(
            mention_id="m",
            place_id="p",
            week_start="2026-06-22",
            provider="naver_blog",
            attributes=attributes,
        )
        is None
    )


# --- CLI: plan/scan/apply contract via fake cursor ---


class _Cursor:
    """Fake psycopg2 cursor backed by an in-memory row list.

    In apply mode the UPDATE is applied to the in-memory rows, so the tool's
    post-apply re-scan observes the repaired state (unsafe_after == 0) exactly
    like production would.
    """

    def __init__(self, rows, apply_mode=False):
        self._rows = [list(row) for row in rows]
        self._apply_mode = apply_mode
        self.executed: list[tuple[str, tuple]] = []
        self.rowcount = 0
        self._next = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def execute(self, sql, params=None):
        self.executed.append((sql, params))
        if not self._apply_mode:
            self.rowcount = 0
            return
        if sql.strip().startswith("UPDATE"):
            for row in self._rows:
                if row[0] == params[1]:
                    row[4] = json.loads(params[0])
            self.rowcount = 1
            return
        if "FOR UPDATE" in sql:
            # The locked per-row re-read: return the live in-memory attributes.
            self._next = None
            for row in self._rows:
                if row[0] == params[0]:
                    self._next = (row[4],)
                    break
            return
        self.rowcount = 0

    def fetchall(self):
        return [tuple(row) for row in self._rows]

    def fetchone(self):
        return self._next


class _Connection:
    def __init__(self, cursor):
        self._cursor = cursor

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def cursor(self):
        return self._cursor

    def close(self):
        pass


def _patch_psycopg2(monkeypatch, connection):
    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda *a, **k: connection)
    )


def _unsafe_row():
    return (
        "11111111-1111-1111-1111-111111111111",
        "place-1",
        "2026-06-22",
        "naver_blog",
        {"preprocess": {"retained_external_keys": [_FAKE_URL_A, _FAKE_URL_B]}},
    )


def _clean_row():
    return (
        "22222222-2222-2222-2222-222222222222",
        "place-2",
        "2026-06-22",
        "naver_blog",
        {"preprocess": {"retained_external_keys": ["abc123"]}},
    )


def test_tool_plan_mode_never_touches_db(capsys):
    exit_code = tool.main(["--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert tool.CONFIRM_ENV in payload["apply_required_env"]
    assert "--confirm-count <N>" in payload["apply_required_args"]
    assert "--backup-ref <s3-or-path>" in payload["apply_required_args"]


def test_tool_scan_reports_counts_and_no_values(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    cursor = _Cursor([_unsafe_row(), _clean_row()])
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--scan", "--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "scan"
    assert payload["db_mutation"] is False
    assert payload["scanned_row_count"] == 2
    assert payload["affected_row_count"] == 1
    assert payload["unsafe_value_count"] == 2
    assert payload["replace_action_count"] == 2
    assert payload["drop_action_count"] == 0
    assert payload["field_breakdown"] == {"preprocess": 2}
    serialized = json.dumps(payload, ensure_ascii=False)
    assert "example.invalid" not in serialized
    assert _FAKE_URL_A not in serialized
    # Read-only: no UPDATE executed.
    assert not any(sql.strip().startswith("UPDATE") for sql, _ in cursor.executed)


def test_tool_scan_writes_sanitized_report_artifact(monkeypatch, capsys, tmp_path):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    report_path = tmp_path / "repair-report.json"
    cursor = _Cursor([_unsafe_row()])
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--scan", "--json", "--report", str(report_path)])

    assert exit_code == 0
    artifact = json.loads(report_path.read_text(encoding="utf-8"))
    assert artifact["mode"] == "scan"
    assert artifact["unsafe_value_count"] == 2
    serialized = json.dumps(artifact, ensure_ascii=False)
    assert "example.invalid" not in serialized
    assert _FAKE_URL_A not in serialized


def test_tool_apply_refuses_every_missing_guard(monkeypatch, capsys):
    """Two-man rule: each guard missing alone must refuse with exit 2."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    connected = []
    connection = _Connection(_Cursor([_unsafe_row()], apply_mode=True))

    def connect(dsn, connect_timeout):
        connected.append(dsn)
        return connection

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))

    # 1. env confirmation missing (count + backup-ref present).
    monkeypatch.delenv(tool.CONFIRM_ENV, raising=False)
    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert tool.CONFIRM_ENV in payload["error"]
    assert connected == []  # refused BEFORE any connection

    # 2. env set to the WRONG value still refuses.
    monkeypatch.setenv(tool.CONFIRM_ENV, "yes")
    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert tool.CONFIRM_ENV in payload["error"]
    assert connected == []

    # 3. --confirm-count missing (env + backup-ref present).
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    exit_code = tool.main(["--apply", "--json", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "--confirm-count" in payload["error"]
    assert connected == []

    # 4. --confirm-count WRONG value (live count is 2, confirmed 5): refuses
    #    inside the transaction after the scan, with no UPDATE executed.
    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    connection = _Connection(cursor)
    monkeypatch.setitem(
        sys.modules,
        "psycopg2",
        SimpleNamespace(connect=lambda *a, **k: connection),
    )
    exit_code = tool.main(["--apply", "--json", "--confirm-count", "5", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "--confirm-count does not match" in payload["error"]
    assert not any(sql.strip().startswith("UPDATE") for sql, _ in cursor.executed)

    # 5. --backup-ref missing (env + count present).
    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "--backup-ref" in payload["error"]

    # 6. --backup-ref blank string also refuses.
    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "   "])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "--backup-ref" in payload["error"]

    # 7. --apply and --scan together is a usage error.
    exit_code = tool.main(["--apply", "--scan", "--json"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2


def test_tool_apply_zeroes_unsafe_and_reports_unsafe_after_zero(monkeypatch, capsys, tmp_path):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))
    report_path = tmp_path / "apply-report.json"

    exit_code = tool.main(
        [
            "--apply",
            "--json",
            "--confirm-count",
            "2",
            "--backup-ref",
            "s3://controller-backup/mentions-2026-08-15",
            "--report",
            str(report_path),
        ]
    )
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["scanned_row_count"] == 2
    assert payload["affected_row_count"] == 1
    assert payload["unsafe_value_count"] == 2
    assert payload["updated_row_count"] == 1
    assert payload["unsafe_after"] == 0  # post-apply verification target
    assert (
        payload["backup_ref_sha256"]
        == hashlib.sha256(b"s3://controller-backup/mentions-2026-08-15").hexdigest()
    )
    # Rollback evidence: per-row checksums, never values.
    assert len(payload["updated_row_checksums"]) == 1
    serialized = json.dumps(payload, ensure_ascii=False)
    assert "example.invalid" not in serialized
    assert _FAKE_URL_A not in serialized

    # The persisted write carries the S1 digests, keeping the consumer join
    # (review_attribute_batch pgcrypto digest) functional.
    updates = [params for sql, params in cursor.executed if sql.strip().startswith("UPDATE")]
    assert len(updates) == 1
    written = json.loads(updates[0][0])
    assert written["preprocess"]["retained_external_keys"] == [
        review_mention_ingest.external_key_sha256("naver_blog", _FAKE_URL_A),
        review_mention_ingest.external_key_sha256("naver_blog", _FAKE_URL_B),
    ]

    artifact = json.loads(report_path.read_text(encoding="utf-8"))
    assert artifact["unsafe_after"] == 0
    assert "example.invalid" not in json.dumps(artifact)


def test_tool_apply_is_idempotent_on_rerun(monkeypatch, capsys):
    """Second run against repaired rows reports 0 updates (no re-digest loop)."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)

    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    first = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert first["updated_row_count"] == 1

    # Re-run with the post-repair count (0) against the now-repaired rows.
    exit_code = tool.main(["--apply", "--json", "--confirm-count", "0", "--backup-ref", "s3://b/x"])
    second = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert second["affected_row_count"] == 0
    assert second["unsafe_value_count"] == 0
    assert second["updated_row_count"] == 0
    assert second["unsafe_after"] == 0
    updates = [params for sql, params in cursor.executed if sql.strip().startswith("UPDATE")]
    assert len(updates) == 1  # only the FIRST run's update survived


def test_tool_apply_rescans_to_unsafe_after_zero_for_over_bound_rows(monkeypatch, capsys):
    """Over-bound drops also verify to 0 and never leave a residue."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    over = "https://example.invalid/overbound?" + "z" * repair._HASH_INPUT_MAX
    row = (
        "33333333-3333-3333-3333-333333333333",
        "place-3",
        "2026-06-22",
        "naver_blog",
        {"preprocess": {"retained_external_keys": [over, _FAKE_URL_A]}},
    )
    cursor = _Cursor([row], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["unsafe_value_count"] == 2
    assert payload["updated_row_count"] == 1
    assert payload["unsafe_after"] == 0
    # Only the in-bound value survives as a digest; the over-bound slot is gone.
    updates = [params for sql, params in cursor.executed if sql.strip().startswith("UPDATE")]
    written = json.loads(updates[0][0])
    assert written["preprocess"]["retained_external_keys"] == [
        repair.safe_digest("naver_blog", _FAKE_URL_A)
    ]


def test_tool_error_output_is_redacted(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)

    def boom(dsn, connect_timeout):
        raise RuntimeError(f"connection refused for {dsn}")

    monkeypatch.setitem(
        sys.modules,
        "psycopg2",
        SimpleNamespace(connect=boom),
    )

    exit_code = tool.main(["--scan", "--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 2
    assert dsn not in json.dumps(payload)
    assert password not in json.dumps(payload)


def test_tool_apply_error_path_is_redacted_and_exits_2(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://user:seekret@example.invalid/db")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)

    class _BoomCursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            raise RuntimeError("scan exploded with postgresql://user:seekret@host/db")

        def fetchall(self):
            return []

    class _BoomConnection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return _BoomCursor()

        def close(self):
            pass

    monkeypatch.setitem(
        sys.modules,
        "psycopg2",
        SimpleNamespace(connect=lambda *a, **k: _BoomConnection()),
    )

    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 2
    assert payload["ok"] is False
    assert "seekret" not in json.dumps(payload)
    assert "user:seekret@example.invalid" not in json.dumps(payload)


# --- concurrency contract: the re-read must lock the row ---


def test_apply_reselect_locks_rows_for_update():
    """The apply re-read must take a row lock so a concurrent writer cannot
    commit between re-read and UPDATE (lost update). A plain SELECT is a
    defect: two overlapping repairs could both re-read the same pre-state and
    one would silently overwrite the other's write."""
    sql = tool._RESELECT_SQL.upper()
    assert "FOR UPDATE" in sql
    assert sql.startswith("SELECT ATTRIBUTES FROM COMMUNITY.PLACE_MENTIONS_WEEKLY")
    assert "WHERE ID = %S" in sql


def test_apply_executes_the_locked_reselect_per_affected_row(monkeypatch, capsys):
    """Every repaired row is re-read via the locked statement, and the UPDATE
    carries the same row id — proving repair works from the live re-read, not
    the stale scan plan."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    capsys.readouterr()

    reselects = [params for sql, params in cursor.executed if sql is tool._RESELECT_SQL]
    updates = [params for sql, params in cursor.executed if sql.strip().startswith("UPDATE")]
    assert len(reselects) == 1  # one affected row
    assert len(updates) == 1
    assert reselects[0] == updates[0][1:]  # same row id re-read then updated


def test_apply_repairs_from_live_reread_not_stale_plan(monkeypatch, capsys):
    """If the row CHANGED between scan and apply's locked re-read (a writer
    committed before the lock), the repair must operate on the re-read state.
    The scan planned 2 unsafe values, but the live row now has 1 — the written
    attributes must reflect the live row's other keys."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)

    stale_row = (
        "11111111-1111-1111-1111-111111111111",
        "place-1",
        "2026-06-22",
        "naver_blog",
        {"preprocess": {"retained_external_keys": [_FAKE_URL_A, _FAKE_URL_B]}},
    )
    # Live state at re-read time: writer added a key and removed one URL.
    live_row = (
        "11111111-1111-1111-1111-111111111111",
        "place-1",
        "2026-06-22",
        "naver_blog",
        {
            "preprocess": {"retained_external_keys": [_FAKE_URL_A, "writer-added"]},
            "writer_section": {"note": "keep"},
        },
    )
    cursor = _LiveRereadCursor(stale_row, live_row)
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["updated_row_count"] == 1
    updates = [params for sql, params in cursor.executed if sql.strip().startswith("UPDATE")]
    written = json.loads(updates[0][0])
    # Live re-read state repaired: URL→digest, writer's non-URL key preserved,
    # writer's sibling section preserved (NOT overwritten from the stale plan).
    assert written["preprocess"]["retained_external_keys"] == [
        repair.safe_digest("naver_blog", _FAKE_URL_A),
        "writer-added",
    ]
    assert written["writer_section"] == {"note": "keep"}


class _LiveRereadCursor(_Cursor):
    """Scan sees the STALE row; the locked re-read (and post-verify scan) sees
    the LIVE row, simulating a concurrent writer that committed after the
    scan's snapshot but before the apply's FOR UPDATE."""

    def __init__(self, stale_row, live_row):
        super().__init__([stale_row], apply_mode=True)
        self._live_row = list(live_row)
        self._reselect_seen = False

    def execute(self, sql, params=None):
        if sql is tool._RESELECT_SQL:
            self.executed.append((sql, params))
            self._next = (self._live_row[4],)
            self._rows = [self._live_row]  # subsequent scans see live state
            return
        super().execute(sql, params)


# --- job-run recording: correct service, correct job name, both paths ---


class _JobRunRecorder:
    """Capture job_runs.record_job_run calls without touching a DB."""

    def __init__(self):
        self.calls: list[dict] = []

    def install(self, monkeypatch):
        recorder = self

        def record_job_run(**kwargs):
            recorder.calls.append(kwargs)

        import apps.api.app.services.job_runs as job_runs_module

        monkeypatch.setattr(job_runs_module, "record_job_run", record_job_run)


def test_apply_success_records_repair_job_name(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))
    recorder = _JobRunRecorder()
    recorder.install(monkeypatch)

    tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    capsys.readouterr()

    assert len(recorder.calls) == 1
    call = recorder.calls[0]
    assert call["job_name"] == tool.JOB_NAME == "place-mention-attribute-repair"
    assert call["status"] == "succeeded"
    assert call["error_message"] is None


def test_apply_failure_records_repair_job_name_and_redacted_error(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://user:seekret@example.invalid/db")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    recorder = _JobRunRecorder()
    recorder.install(monkeypatch)

    class _BoomCursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            raise RuntimeError("scan exploded with postgresql://user:seekret@host/db")

        def fetchall(self):
            return []

    class _BoomConnection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return _BoomCursor()

        def close(self):
            pass

    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda *a, **k: _BoomConnection())
    )

    exit_code = tool.main(["--apply", "--json", "--confirm-count", "2", "--backup-ref", "s3://b/x"])
    capsys.readouterr()

    assert exit_code == 2
    assert len(recorder.calls) == 1
    call = recorder.calls[0]
    assert call["job_name"] == tool.JOB_NAME  # the ingest job name never appears
    assert call["job_name"] != review_mention_ingest.JOB_NAME
    assert call["status"] == "failed"
    # The recorded error is redacted: no DSN credential survives.
    assert "seekret" not in str(call["error_message"])


def test_scan_mode_records_no_job_run(monkeypatch, capsys):
    """Read-only scan is not a job run (no mutation, nothing to audit in ops)."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    cursor = _Cursor([_clean_row()])
    _patch_psycopg2(monkeypatch, _Connection(cursor))
    recorder = _JobRunRecorder()
    recorder.install(monkeypatch)

    tool.main(["--scan", "--json"])
    capsys.readouterr()

    assert recorder.calls == []


# --- sanitized evidence: no raw refs, paths, URLs, or internal ids ---


def test_apply_output_never_exposes_raw_backup_ref_or_row_ids(monkeypatch, capsys, tmp_path):
    """The apply payload/report must carry ONLY digest evidence: the raw
    --backup-ref (a storage path) and internal mention row ids must not appear
    in stdout or the report artifact."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.CONFIRM_ENV, tool.CONFIRM_ENV_VALUE)
    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))
    report_path = tmp_path / "apply-report.json"
    backup_ref = "s3://internal-bucket-name/lala/mentions-backup-2026-08-15.dump"
    row_id = "11111111-1111-1111-1111-111111111111"

    tool.main(
        [
            "--apply",
            "--json",
            "--confirm-count",
            "2",
            "--backup-ref",
            backup_ref,
            "--report",
            str(report_path),
        ]
    )
    stdout = capsys.readouterr().out

    assert "backup_ref" not in stdout.replace("backup_ref_sha256", "")
    assert backup_ref not in stdout
    assert "s3://internal-bucket-name" not in stdout
    assert row_id not in stdout

    artifact_text = report_path.read_text(encoding="utf-8")
    artifact = json.loads(artifact_text)
    assert backup_ref not in artifact_text
    assert "s3://internal-bucket-name" not in artifact_text
    assert row_id not in artifact_text
    assert "mention_id" not in artifact_text
    # Positive evidence: the digests ARE present so the controller can correlate.
    assert artifact["backup_ref_sha256"] == hashlib.sha256(backup_ref.encode("utf-8")).hexdigest()
    assert artifact["updated_row_checksums"] == [
        {
            "row_sha256": hashlib.sha256(row_id.encode("utf-8")).hexdigest(),
            "before_sha256": artifact["updated_row_checksums"][0]["before_sha256"],
            "after_sha256": artifact["updated_row_checksums"][0]["after_sha256"],
        }
    ]
    assert (
        artifact["updated_row_checksums"][0]["before_sha256"]
        != artifact["updated_row_checksums"][0]["after_sha256"]
    )
