"""Unit tests for the bounded live docent QA runner's targeted replay mode.

All networking is mocked: these tests prove selection/validation behavior and
must never reach a real endpoint (no weather GET, no script POST).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from apps.api.app.tools import run_docent_live_qa_sample as runner

_WEATHER = {
    "temp": 21,
    "icon": "sun",
    "outdoor_status": "good",
    "dust": {"pm10": 20, "pm25": 10, "pm10_grade_ko": "좋음", "pm25_grade_ko": "좋음"},
}


def _place(index: int, *, bilingual: bool = True) -> dict[str, Any]:
    return {
        "place_id": f"tour-api-{1000 + index}",
        "place_name_ko": f"테스트 장소 {index}",
        "place_name_en": f"Test Place {index}",
        "category": "attraction" if index % 2 else "culture_venue",
        "region_ko": "종로구",
        "primary_source": "tour_api",
        "expectation": "nonempty",
        "language_samples": ["ko", "en"] if bilingual else ["ko"],
    }


def _manifest(
    n: int = 30, overrides: dict[str, dict[str, Any]] | None = None
) -> list[dict[str, Any]]:
    rows = []
    for index in range(n):
        row = _place(index, bilingual=index % 2 == 0)
        if overrides and row["place_id"] in overrides:
            row = {**row, **overrides[row["place_id"]]}
        rows.append(row)
    if overrides:
        for place_id, patch in overrides.items():
            if not any(row["place_id"] == place_id for row in rows):
                rows.append({**_place(len(rows)), **patch, "place_id": place_id})
    return rows


@pytest.fixture()
def network(monkeypatch):
    """Mock both HTTP helpers; any real call attempt fails the test."""
    calls: list[dict[str, Any]] = []

    def fake_post(url, payload, timeout):
        calls.append(
            {"method": "POST", "place_id": payload["place_id"], "language": payload["language"]}
        )
        return {
            "data": {
                "script": "테스트 스크립트입니다. 날씨와 미세먼지를 함께 안내합니다.",
                "source": "openai",
                "generated_at": "2026-08-18T00:00:00Z",
                "grounding_count": 1,
                "grounding_sources": ["place_profile"],
                "retrieval": {"mode": "hybrid"},
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
            }
        }

    def fake_get(url, timeout):
        calls.append({"method": "GET", "url": url})
        return {"data": _WEATHER}

    monkeypatch.setattr(runner, "_http_post_json", fake_post)
    monkeypatch.setattr(runner, "_http_get_json", fake_get)
    return calls


def _write_manifest(tmp_path: Path, manifest: list[dict[str, Any]]) -> Path:
    path = tmp_path / "qa_manifest_40places.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    return path


def test_default_full_run_behavior_unchanged(network, tmp_path):
    manifest = _manifest(30)
    manifest_path = _write_manifest(tmp_path, manifest)

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--request-delay-sec",
            "0",
        ]
    )

    assert exit_code == 0
    # 15 bilingual x2 + 15 mono-ko = 45 calls, in manifest order then language order.
    assert len(network) == 46  # 1 weather GET + 45 POSTs
    posts = [c for c in network if c["method"] == "POST"]
    expected = [
        (place["place_id"], language)
        for place in manifest
        for language in place["language_samples"]
    ]
    assert [(c["place_id"], c["language"]) for c in posts] == expected
    report = json.loads(
        (tmp_path / "out" / next(iter((tmp_path / "out").iterdir()))).read_text(encoding="utf-8")
    )
    assert report["place_count"] == 30
    assert report["counters"] == {
        "calls": 45,
        "ok": 45,
        "service_errors": 0,
        "transport_errors": 0,
    }
    assert "selection" not in report


def test_targeted_run_selects_exact_three_pairs(network, tmp_path):
    targets_spec = {
        "tour-api-1316965": {"language_samples": ["ko", "en"]},
        "tour-api-1017547": {"language_samples": ["ko", "en"]},
        "tour-api-130420": {"language_samples": ["ko", "en"]},
    }
    manifest = _manifest(30, overrides=targets_spec)
    # Manifest declares 1316965 before 1017547 before 130420; pass targets in
    # reverse CLI order to prove output follows manifest order, not CLI order.
    manifest_path = _write_manifest(tmp_path, manifest)
    argv_targets = [
        "--target",
        "tour-api-130420:en",
        "--target",
        "tour-api-1017547:en",
        "--target",
        "tour-api-1316965:ko",
    ]

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--request-delay-sec",
            "0",
            *argv_targets,
        ]
    )

    assert exit_code == 0
    posts = [c for c in network if c["method"] == "POST"]
    assert [(c["place_id"], c["language"]) for c in posts] == [
        ("tour-api-1316965", "ko"),
        ("tour-api-1017547", "en"),
        ("tour-api-130420", "en"),
    ]
    report = json.loads(
        (tmp_path / "out" / next(iter((tmp_path / "out").iterdir()))).read_text(encoding="utf-8")
    )
    assert report["selection"] == {
        "mode": "targeted",
        "targets": [
            "tour-api-1017547:en",
            "tour-api-130420:en",
            "tour-api-1316965:ko",
        ],
    }
    assert report["place_count"] == 3
    assert report["counters"]["calls"] == 3


def test_targeted_run_single_language_of_bilingual_place(network, tmp_path):
    manifest = _manifest(30, overrides={"tour-api-1000": {"language_samples": ["ko", "en"]}})
    manifest_path = _write_manifest(tmp_path, manifest)

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--request-delay-sec",
            "0",
            "--target",
            "tour-api-1000:en",
        ]
    )

    assert exit_code == 0
    posts = [c for c in network if c["method"] == "POST"]
    assert [(c["place_id"], c["language"]) for c in posts] == [("tour-api-1000", "en")]
    report = json.loads(
        (tmp_path / "out" / next(iter((tmp_path / "out").iterdir()))).read_text(encoding="utf-8")
    )
    assert report["counters"]["calls"] == 1


def test_target_validation_fails_before_network_for_missing_place(network, tmp_path):
    manifest_path = _write_manifest(tmp_path, _manifest(30))

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--target",
            "tour-api-999999:ko",
        ]
    )

    assert exit_code == 2
    assert network == []


def test_target_validation_rejects_duplicate_target(network, tmp_path):
    manifest_path = _write_manifest(tmp_path, _manifest(30))

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--target",
            "tour-api-1000:ko",
            "--target",
            "tour-api-1000:ko",
        ]
    )

    assert exit_code == 2
    assert network == []


@pytest.mark.parametrize("bad_target", ["nocolon", "tour-api-1000:", ":ko", "a:b:c", "x:ko:en"])
def test_target_validation_rejects_malformed_target(network, tmp_path, bad_target):
    manifest_path = _write_manifest(tmp_path, _manifest(30))

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--target",
            bad_target,
        ]
    )

    assert exit_code == 2
    assert network == []


def test_target_validation_rejects_unsupported_language(network, tmp_path):
    manifest_path = _write_manifest(tmp_path, _manifest(30))

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--target",
            "tour-api-1000:zh",
        ]
    )

    assert exit_code == 2
    assert network == []


def test_target_validation_rejects_language_not_sampled_for_place(network, tmp_path):
    # tour-api-1001 is mono-ko in the fixture; asking for en must fail pre-network.
    manifest = _manifest(30, overrides={"tour-api-1001": {"language_samples": ["ko"]}})
    manifest_path = _write_manifest(tmp_path, manifest)

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--target",
            "tour-api-1001:en",
        ]
    )

    assert exit_code == 2
    assert network == []


def test_targeted_mode_validates_full_manifest_before_network(network, tmp_path):
    manifest_path = _write_manifest(tmp_path, _manifest(10))

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--target",
            "tour-api-1000:ko",
        ]
    )

    assert exit_code == 2
    assert network == []


def test_targeted_mode_enforces_call_cap(network, tmp_path, monkeypatch):
    monkeypatch.setitem(runner.RUN_CAPS, "max_calls", 2)
    manifest = _manifest(
        30,
        overrides={
            "tour-api-1000": {"language_samples": ["ko", "en"]},
            "tour-api-1002": {"language_samples": ["ko", "en"]},
        },
    )
    manifest_path = _write_manifest(tmp_path, manifest)

    exit_code = runner.main(
        [
            "--manifest",
            str(manifest_path),
            "--base-url",
            "https://qa.example",
            "--output-dir",
            str(tmp_path / "out"),
            "--request-delay-sec",
            "0",
            "--target",
            "tour-api-1000:ko",
            "--target",
            "tour-api-1000:en",
            "--target",
            "tour-api-1002:ko",
        ]
    )

    assert exit_code == 2
    assert network == []


def test_parse_target_accepts_only_supported_languages():
    assert runner.parse_target("tour-api-1:ko") == ("tour-api-1", "ko")
    assert runner.parse_target("tour-api-1:en") == ("tour-api-1", "en")
    with pytest.raises(ValueError):
        runner.parse_target("tour-api-1:ja")
