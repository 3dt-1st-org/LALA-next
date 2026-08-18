from __future__ import annotations

import json

from apps.api.app.tools import enrich_place_local_columns

# Credential-free sentinel DSN: asserting its absence from output still proves
# redact_secret_text received the configured DSN, without password-shaped literals.
_FAKE_DSN = "postgresql://example.invalid/lala"


_PRODUCTION_ROWS = [
    {
        "place_id": "tour-api-1017547",
        "name_ko": "중명전",
        "name_en": "Myeongjeongjeon Hall",
        "address_ko": "서울시 중구 덕수궁길 11",
        "address_en": "11 Deoksugung-gil, Jung-gu, Seoul",
        "region_name_ko": "중구",
        "region_name_en": "Jung-gu",
    },
    {
        "place_id": "tour-api-130420",
        "name_ko": "한밭교육박물관",
        "name_en": "Daejeon Hanhat Education Museum",
        "address_ko": "대전광역시 서구 둔산로 111",
        "address_en": "111 Dunsan-ro, Seo-gu, Daejeon",
        "region_name_ko": "서구",
        "region_name_en": "Seo-gu",
    },
]


def _run_main(monkeypatch, argv: list[str], *, rows: list | None = None) -> tuple[int, dict]:
    monkeypatch.setenv("DB_DSN", _FAKE_DSN)
    calls: dict[str, object] = {
        "fetch_targeted": [],
        "apply_targeted": None,
        "fetch_candidates": None,
    }

    def fake_fetch_targeted(*, dsn, place_ids, connect_timeout):
        calls["fetch_targeted"].append(list(place_ids))
        return rows if rows is not None else []

    def fake_apply_targeted(*, dsn, enrichments, expected_name_ko, connect_timeout):
        calls["apply_targeted"] = {
            "enrichments": list(enrichments),
            "expected_name_ko": dict(expected_name_ko),
        }
        return len(enrichments)

    monkeypatch.setattr(enrich_place_local_columns, "fetch_targeted_places", fake_fetch_targeted)
    monkeypatch.setattr(
        enrich_place_local_columns, "apply_targeted_local_enrichments", fake_apply_targeted
    )
    monkeypatch.setattr(
        enrich_place_local_columns,
        "fetch_candidates",
        lambda **kwargs: calls.__setitem__("fetch_candidates", kwargs) or [],
    )
    monkeypatch.setattr(
        enrich_place_local_columns,
        "apply_local_enrichments",
        lambda **kwargs: (_ for _ in ()).throw(AssertionError("broad apply must not run")),
    )

    exit_code = enrich_place_local_columns.main(argv)
    return exit_code, calls


def _capture_json(capsys) -> tuple[str, dict]:
    """Capture stdout once; the secret-safety assertion runs on the same raw text
    that gets parsed, so a consumed buffer can never hide a leaked DSN."""
    raw = capsys.readouterr().out
    assert _FAKE_DSN not in raw
    return raw, json.loads(raw)


def test_legacy_plan_payload_is_unchanged(capsys) -> None:
    exit_code = enrich_place_local_columns.main(["--json"])

    _raw, payload = _capture_json(capsys)
    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert "targeted" not in payload


def test_legacy_non_positive_limit_is_rejected(capsys) -> None:
    exit_code = enrich_place_local_columns.main(["--json", "--preview", "--limit", "0"])

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "--limit must be positive" in payload["error"]


def test_legacy_preview_defaults_to_limit_500(monkeypatch, capsys) -> None:
    monkeypatch.setenv("DB_DSN", _FAKE_DSN)
    captured: dict = {}

    def fake_fetch_candidates(**kwargs):
        captured.update(kwargs)
        return []

    monkeypatch.setattr(enrich_place_local_columns, "fetch_candidates", fake_fetch_candidates)
    monkeypatch.setattr(
        enrich_place_local_columns,
        "apply_local_enrichments",
        lambda **kwargs: (_ for _ in ()).throw(AssertionError("preview must not apply")),
    )

    exit_code = enrich_place_local_columns.main(["--json", "--preview"])

    _raw, payload = _capture_json(capsys)
    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["candidate_count"] == 0
    assert captured["limit"] == 500


def test_target_mode_requires_refresh_local(capsys) -> None:
    exit_code = enrich_place_local_columns.main(
        ["--json", "--preview", "--target-place-id", "tour-api-1017547"]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "--target-place-id requires --refresh-local" in payload["error"]


def test_target_mode_rejects_blank_value(capsys) -> None:
    exit_code = enrich_place_local_columns.main(
        ["--json", "--preview", "--refresh-local", "--target-place-id", "  "]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "must not be blank" in payload["error"]


def test_target_mode_rejects_duplicate_ids(capsys) -> None:
    exit_code = enrich_place_local_columns.main(
        [
            "--json",
            "--preview",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
            "--target-place-id",
            "tour-api-1017547",
        ]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "was passed more than once" in payload["error"]


def test_target_mode_rejects_explicit_limit(capsys) -> None:
    exit_code = enrich_place_local_columns.main(
        [
            "--json",
            "--preview",
            "--refresh-local",
            "--limit",
            "5",
            "--target-place-id",
            "tour-api-1017547",
        ]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "cannot combine with --target-place-id" in payload["error"]


def test_target_mode_rejects_non_positive_limit(capsys) -> None:
    exit_code = enrich_place_local_columns.main(
        [
            "--json",
            "--preview",
            "--refresh-local",
            "--limit",
            "-1",
            "--target-place-id",
            "tour-api-1017547",
        ]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "--limit must be positive" in payload["error"]


def test_target_mode_requires_preview_or_apply(capsys) -> None:
    exit_code = enrich_place_local_columns.main(
        [
            "--json",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
        ]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "--preview or --apply" in payload["error"]


def test_target_apply_keeps_confirmation_and_allow_env_guards(monkeypatch, capsys) -> None:
    monkeypatch.setenv("DB_DSN", _FAKE_DSN)
    monkeypatch.delenv(enrich_place_local_columns.ALLOW_ENV, raising=False)
    monkeypatch.setattr(
        enrich_place_local_columns,
        "fetch_targeted_places",
        lambda **kwargs: (_ for _ in ()).throw(
            AssertionError("guards must reject before any DB read")
        ),
    )

    exit_code = enrich_place_local_columns.main(
        [
            "--json",
            "--apply",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
            "--confirm",
            enrich_place_local_columns.CONFIRM_TEXT,
        ]
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert enrich_place_local_columns.ALLOW_ENV in payload["error"]


def test_target_missing_place_refuses_before_mutation(monkeypatch, capsys) -> None:
    monkeypatch.setenv(enrich_place_local_columns.ALLOW_ENV, "1")

    exit_code, calls = _run_main(
        monkeypatch,
        [
            "--json",
            "--apply",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
            "--target-place-id",
            "tour-api-999999",
            "--confirm",
            enrich_place_local_columns.CONFIRM_TEXT,
        ],
        rows=[_PRODUCTION_ROWS[0]],
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "tour-api-999999" in payload["error"]
    assert "was not found" in payload["error"]
    assert calls["apply_targeted"] is None


def test_target_uncurated_korean_name_refuses_before_mutation(monkeypatch, capsys) -> None:
    monkeypatch.setenv(enrich_place_local_columns.ALLOW_ENV, "1")
    uncurated_row = {**_PRODUCTION_ROWS[0], "name_ko": "수정된 이름"}

    exit_code, calls = _run_main(
        monkeypatch,
        [
            "--json",
            "--apply",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
            "--confirm",
            enrich_place_local_columns.CONFIRM_TEXT,
        ],
        rows=[uncurated_row],
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert "curated" in payload["error"]
    assert calls["apply_targeted"] is None


def test_target_db_exception_is_redacted_in_error_output(monkeypatch, capsys) -> None:
    monkeypatch.setenv("DB_DSN", _FAKE_DSN)

    def exploding_fetch(*, dsn, place_ids, connect_timeout):
        raise RuntimeError(f"connection failed for {dsn}")

    monkeypatch.setattr(enrich_place_local_columns, "fetch_targeted_places", exploding_fetch)

    exit_code = enrich_place_local_columns.main(
        [
            "--json",
            "--preview",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
        ]
    )

    raw, payload = _capture_json(capsys)
    assert exit_code == 2
    assert payload["ok"] is False
    assert "connection failed" in payload["error"]
    # Why: the error branch must hand the configured DSN to redact_secret_text,
    # which replaces the whole sentinel with the [redacted] marker.
    assert "connection failed for [redacted]" in payload["error"]
    assert _FAKE_DSN not in raw


def test_target_preview_reports_name_only_repair_without_mutation(monkeypatch, capsys) -> None:
    exit_code, calls = _run_main(
        monkeypatch,
        [
            "--json",
            "--preview",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
            "--target-place-id",
            "tour-api-130420",
        ],
        rows=_PRODUCTION_ROWS,
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["db_mutation"] is False
    assert payload["updated_rows"] == 0
    assert calls["apply_targeted"] is None
    assert calls["fetch_targeted"] == [["tour-api-1017547", "tour-api-130420"]]
    assert [result["name_en"] for result in payload["target_results"]] == [
        "Jungmyeongjeon",
        "Hanbat Education Museum",
    ]


def test_target_apply_renames_exactly_two_places_name_en_only(monkeypatch, capsys) -> None:
    monkeypatch.setenv(enrich_place_local_columns.ALLOW_ENV, "1")

    exit_code, calls = _run_main(
        monkeypatch,
        [
            "--json",
            "--apply",
            "--refresh-local",
            "--target-place-id",
            "tour-api-1017547",
            "--target-place-id",
            "tour-api-130420",
            "--confirm",
            enrich_place_local_columns.CONFIRM_TEXT,
        ],
        rows=_PRODUCTION_ROWS,
    )

    _raw, payload = _capture_json(capsys)
    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["db_mutation"] is True
    assert payload["targeted"] is True
    assert payload["name_en_only"] is True
    assert payload["updated_rows"] == 2
    assert calls["fetch_targeted"] == [["tour-api-1017547", "tour-api-130420"]]
    applied = calls["apply_targeted"]
    assert applied["expected_name_ko"] == {
        "tour-api-1017547": "중명전",
        "tour-api-130420": "한밭교육박물관",
    }
    by_id = {item.place_id: item for item in applied["enrichments"]}
    assert by_id["tour-api-1017547"].name_en == "Jungmyeongjeon"
    assert by_id["tour-api-130420"].name_en == "Hanbat Education Museum"
    # Why: bounded repair must not recompute address/region English fields.
    for item in applied["enrichments"]:
        assert item.address_en is None
        assert item.region_name_en is None
    assert [result["name_en"] for result in payload["target_results"]] == [
        "Jungmyeongjeon",
        "Hanbat Education Museum",
    ]
