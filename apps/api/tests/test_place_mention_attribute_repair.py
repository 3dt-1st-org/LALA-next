from __future__ import annotations

import json
import sys
from types import SimpleNamespace

from apps.api.app.services import place_mention_attribute_repair as repair
from apps.api.app.tools import run_place_mention_attribute_repair as tool

_FAKE_URL_A = "https://example.test/post/123?x=1"
_FAKE_URL_B = "https://example.test/post/456?q=ad#section"


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
    assert repair.is_url_shaped("www.example.test/path")
    assert not repair.is_url_shaped("not-a-url-key-1")
    assert not repair.is_url_shaped(123)
    assert not repair.is_url_shaped(None)


def test_detects_bare_authority_and_scheme_forms():
    assert repair.is_url_shaped("http://example.test/a")
    assert repair.is_url_shaped("ftp://files.example.test/x.txt")
    assert repair.is_url_shaped("example.test/path")
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
    assert "example.test" not in serialized
    assert _FAKE_URL_A not in serialized
    # Safe sibling data untouched.
    assert repaired["top_terms"] == ["커피"]


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
    over = "https://example.test/overbound?" + "z" * bound
    at_limit = "https://example.test/at-limit/" + "k" * (
        bound - len(provider) - len("https://example.test/at-limit/") - 1
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
    prefix_len = bound - len(provider) - 1 - len("https://example.test/p/")
    prefix = "https://example.test/p/" + "z" * prefix_len
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
    assert "example.test" not in serialized


def test_drop_prunes_emptied_container_but_preserves_preexisting_empty():
    provider = "naver_blog"
    bound = repair._HASH_INPUT_MAX
    over = "https://example.test/only-overbound?" + "z" * bound

    attributes = {
        "preprocess": {"retained_external_keys": [over]},  # emptied by the drop
        "already_empty": [],
        "prune_me": [over],  # array emptied by the drop
    }

    repaired, changed = repair.redact_unsafe_values(attributes, provider=provider)

    assert changed is True
    # Keys whose containers were EMPTIED BY THE DROP are pruned entirely —
    # including parents left empty ("preprocess" -> {} -> pruned too).
    assert "retained_external_keys" not in repaired.get("preprocess", {})
    assert "preprocess" not in repaired or repaired["preprocess"] == {}
    assert "prune_me" not in repaired
    # A container that was empty BEFORE repair stays as-is (no rewrite).
    assert repaired["already_empty"] == []
    # Over-bound material never survives anywhere in the repaired output.
    assert over not in json.dumps(repaired, default=str)


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
    assert "example.test" not in serialized  # paths + digests only, never values

    summary = repair.summarize_row_plans([plan])
    assert summary["affected_row_count"] == 1
    assert summary["unsafe_value_count"] == 2
    assert summary["field_breakdown"] == {"preprocess": 2}
    assert "example.test" not in json.dumps(summary)


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


# --- CLI: plan/dry-run/apply contract via fake cursor ---


class _Cursor:
    def __init__(self, rows, apply_mode=False):
        self._rows = rows
        self._apply_mode = apply_mode
        self.executed: list[tuple[str, tuple]] = []
        self.rowcount = 0

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def execute(self, sql, params=None):
        self.executed.append((sql, params))
        if "WHERE id = %s" in sql and self._apply_mode:
            key = params[0]
            for row in self._rows:
                if row[0] == key:
                    self._next = (row[4],)
                    return
            self._next = None
        self.rowcount = 1

    def fetchall(self):
        return self._rows

    def fetchone(self):
        try:
            return self._next
        except AttributeError:
            return None


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
    assert tool.ALLOW_ENV in payload["apply_required_env"]


def test_tool_dry_run_reports_counts_and_no_values(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    cursor = _Cursor([_unsafe_row(), _clean_row()])
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--dry-run", "--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "dry-run"
    assert payload["scanned_row_count"] == 2
    assert payload["affected_row_count"] == 1
    assert payload["unsafe_value_count"] == 2
    assert payload["replace_action_count"] == 2
    assert payload["drop_action_count"] == 0
    assert payload["field_breakdown"] == {"preprocess": 2}
    # Diff summary carries identity/location/checksums — never the value.
    serialized = json.dumps(payload, ensure_ascii=False)
    assert "example.test" not in serialized
    assert _FAKE_URL_A not in serialized
    assert payload["diff_preview"][0]["before_sha256"] != payload["diff_preview"][0]["after_sha256"]
    # Read-only: no UPDATE executed.
    assert not any("UPDATE" in sql for sql, _ in cursor.executed)


def test_tool_apply_requires_two_man_rule(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.delenv(tool.ALLOW_ENV, raising=False)

    exit_code = tool.main(["--apply", "--json"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "--confirm" in payload["error"]

    exit_code = tool.main(["--apply", "--confirm", tool.CONFIRM_TEXT, "--json"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert tool.ALLOW_ENV in payload["error"]


def test_tool_apply_updates_only_unsafe_rows_with_digests(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    cursor = _Cursor([_unsafe_row(), _clean_row()], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--apply", "--confirm", tool.CONFIRM_TEXT, "--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["scanned_row_count"] == 2
    assert payload["affected_row_count"] == 1
    assert payload["updated_row_count"] == 1
    # Rollback evidence: per-row checksums, never values.
    assert len(payload["updated_row_checksums"]) == 1
    serialized = json.dumps(payload, ensure_ascii=False)
    assert "example.test" not in serialized
    assert _FAKE_URL_A not in serialized

    updates = [params for sql, params in cursor.executed if "UPDATE" in sql]
    assert len(updates) == 1
    written = json.loads(updates[0][0])
    assert written["preprocess"]["retained_external_keys"] == [
        repair.safe_digest("naver_blog", _FAKE_URL_A),
        repair.safe_digest("naver_blog", _FAKE_URL_B),
    ]


def test_tool_apply_is_idempotent_on_rerun(monkeypatch, capsys):
    """Second run against repaired rows reports 0 updates (no re-digest loop)."""
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    repaired_attributes = {
        "preprocess": {
            "retained_external_keys": [
                repair.safe_digest("naver_blog", _FAKE_URL_A),
                repair.safe_digest("naver_blog", _FAKE_URL_B),
            ]
        }
    }
    repaired_row = (
        "11111111-1111-1111-1111-111111111111",
        "place-1",
        "2026-06-22",
        "naver_blog",
        repaired_attributes,
    )
    cursor = _Cursor([repaired_row], apply_mode=True)
    _patch_psycopg2(monkeypatch, _Connection(cursor))

    exit_code = tool.main(["--apply", "--confirm", tool.CONFIRM_TEXT, "--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["affected_row_count"] == 0
    assert payload["updated_row_count"] == 0
    assert not any("UPDATE" in sql for sql, _ in cursor.executed)


def test_tool_error_output_is_redacted(monkeypatch, capsys):
    password = "example" + "-password"  # pragma: allowlist secret -- fake fixture
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)

    def boom(dsn, connect_timeout):
        raise RuntimeError(f"connection refused for {dsn}")

    monkeypatch.setitem(
        sys.modules,
        "psycopg2",
        SimpleNamespace(connect=boom),
    )

    exit_code = tool.main(["--dry-run", "--json"])
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 2
    assert dsn not in json.dumps(payload)
    assert password not in json.dumps(payload)
