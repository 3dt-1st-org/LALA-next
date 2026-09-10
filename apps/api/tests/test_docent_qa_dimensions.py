"""Tests for the deterministic docent QA dimension audits (P6A).

Covers: evidence gating (records without a script are not-applicable for every
dimension — never a silent pass), per-dimension pass/flag evidence, the
pass/flagged/not-applicable accounting preserved by the sanitizer schema, and
adversarial repetition cases (duplicates flagged, short/common particles never
a false positive, deterministic bounded scanning).
"""

from __future__ import annotations

import json

from apps.api.app.services import docent_qa_dimensions as dims
from apps.api.app.tools import sanitize_docent_qa_report as sanitizer

_ALLOWED_STATUSES = {dims.STATUS_PASS, dims.STATUS_FLAGGED, dims.STATUS_NOT_APPLICABLE}


def _record(**overrides) -> dict:
    record = {
        "place_id": "eval-dim-01",
        "category": "attraction",
        "language": "ko",
        "source": "rule_based_curation",
        "grounding_count": 2,
        "script": (
            "호암미술관은 전시와 정원이 어우러진 문화 공간입니다. "
            "관람 전후에는 주변 로컬 카페와 골목을 함께 둘러보세요. "
            "오늘은 미세먼지 PM10 30, 초미세먼지 PM2.5 12 수준이라 야외 정원 산책도 무리가 없습니다."
        ),
        "auto_precheck": {"issue_tags": []},
    }
    record.update(overrides)
    return record


# --- Evidence gating: no script -> not applicable, never pass -----------------


def test_record_without_script_is_not_applicable_everywhere() -> None:
    audits = dims.audit_record_dimensions(
        {"place_id": "x", "language": "ko", "auto_precheck": {"issue_tags": []}}
    )
    assert set(audits) == set(dims.DIMENSION_ORDER)
    for audit in audits.values():
        assert audit.status == dims.STATUS_NOT_APPLICABLE
        assert audit.reason == "no_script_evidence"


def test_summary_counts_all_three_verdicts_for_every_dimension() -> None:
    records = [_record(), _record(script=None), _record(script="")]
    summary = dims.summarize_dimension_audits(records)
    assert set(summary) == set(dims.DIMENSION_ORDER)
    for counts in summary.values():
        assert set(counts) == {"pass", "flagged", "not_applicable"}
        assert counts["pass"] == 1
        assert counts["flagged"] == 0
        assert counts["not_applicable"] == 2


# --- Source attribution --------------------------------------------------------


def test_source_attribution_passes_on_clean_label() -> None:
    assert dims.audit_source_attribution(_record()).status == dims.STATUS_PASS


def test_source_attribution_flags_missing_label() -> None:
    record = _record(source=None)
    audit = dims.audit_source_attribution(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "missing_source_label"


def test_source_attribution_flags_blocked_label() -> None:
    record = _record(source="demo_fallback_sample")
    audit = dims.audit_source_attribution(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "blocked_source_label"


def test_source_attribution_falls_back_to_script_source_method() -> None:
    record = _record(source=None, script_source_method="rule_based_curation")
    assert dims.audit_source_attribution(record).status == dims.STATUS_PASS


# --- Local context -------------------------------------------------------------


def test_local_context_passes_on_local_tokens() -> None:
    assert dims.audit_local_context(_record()).status == dims.STATUS_PASS


def test_local_context_flags_generic_script() -> None:
    record = _record(script="여기는 전시 관람만 가능한 공간입니다. 티켓은 현장에서 구매하세요.")
    audit = dims.audit_local_context(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "no_local_context"


# --- Language purity -----------------------------------------------------------


def test_language_purity_flags_hangul_in_english() -> None:
    record = _record(
        language="en",
        script="Welcome to this museum 전시 관람 안내입니다. Enjoy the garden walk nearby.",
    )
    audit = dims.audit_language_purity(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "hangul_in_english"


def test_language_purity_flags_latin_words_in_korean() -> None:
    record = _record(
        script="이 장소는 beautiful mountain village 처럼 아름다운 곳입니다. 산책로가 좋습니다."
    )
    audit = dims.audit_language_purity(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "latin_words_in_korean"


def test_language_purity_allows_pm_tokens_and_short_brands_in_korean() -> None:
    record = _record(
        script="LALA가 고른 장소입니다. 미세먼지 PM10 30, 초미세먼지 PM2.5 12 안내입니다."
    )
    assert dims.audit_language_purity(record).status == dims.STATUS_PASS


def test_language_purity_is_not_applicable_for_unsupported_language() -> None:
    record = _record(language="ja", script="ここは美術館です。周辺を散策してください。")
    audit = dims.audit_language_purity(record)
    assert audit.status == dims.STATUS_NOT_APPLICABLE
    assert audit.reason == "unsupported_language"


# --- Usefulness ----------------------------------------------------------------


def test_usefulness_passes_with_route_action() -> None:
    assert dims.audit_usefulness(_record()).status == dims.STATUS_PASS


def test_usefulness_flags_missing_route_action() -> None:
    record = _record(
        script="이곳은 전시 공간입니다. 티켓 구매 후 관람하실 수 있습니다. 안내데스크에 문의하세요."
    )
    audit = dims.audit_usefulness(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "route_action_missing"


def test_usefulness_flags_on_precheck_tag_even_with_route_tokens() -> None:
    record = _record(auto_precheck={"issue_tags": ["route_action_missing"]})
    audit = dims.audit_usefulness(record)
    assert audit.status == dims.STATUS_FLAGGED


# --- Safety / advertising / hallucination / grounding --------------------------


def test_safety_flags_secret_like_text() -> None:
    record = _record(
        script="안내입니다. sk-AbCdEf123456 키처럼 보이는 표현이 섞였습니다. 골목 근처 안내."
    )
    audit = dims.audit_safety(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "secret_like_text"


def test_advertising_leakage_flags_mock_wording() -> None:
    record = _record(
        script="이 장소는 데모 안내입니다. 골목 상권 근처를 함께 둘러보세요. 동선을 확인하세요."
    )
    audit = dims.audit_advertising_leakage(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "mock_or_fallback_wording"


def test_hallucination_flags_raw_score_leakage() -> None:
    record = _record(script="final_score 0.91 기준으로 추천합니다. 골목 산책 동선도 안내합니다.")
    audit = dims.audit_hallucination(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "raw_score_leakage"


def test_grounding_flags_zero_grounding_count() -> None:
    record = _record(grounding_count=0)
    audit = dims.audit_grounding(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "no_grounding_metadata"


def test_grounding_flags_invalid_grounding_count() -> None:
    record = _record(grounding_count="many")
    audit = dims.audit_grounding(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "invalid_grounding_metadata"


def test_grounding_flags_precheck_tags() -> None:
    record = _record(grounding_count=None, auto_precheck={"issue_tags": ["no_rag_chunks"]})
    assert dims.audit_grounding(record).status == dims.STATUS_FLAGGED


def test_grounding_is_not_applicable_when_evidence_absent() -> None:
    """Absent grounding evidence is N/A, never a silent pass (verifier defect #1)."""
    record = _record(grounding_count=None)
    audit = dims.audit_grounding(record)
    assert audit.status == dims.STATUS_NOT_APPLICABLE
    assert audit.reason == "no_grounding_metadata"


def test_grounding_passes_only_on_positive_explicit_count() -> None:
    assert dims.audit_grounding(_record(grounding_count=1)).status == dims.STATUS_PASS
    assert dims.audit_grounding(_record(grounding_count=2)).status == dims.STATUS_PASS


# --- Repetition: adversarial cases ---------------------------------------------


def test_repetition_flags_exact_duplicate_sentence() -> None:
    sentence = "바다를 끼고 도는 해안 산책로에서 노을을 만날 수 있습니다."
    record = _record(script=f"{sentence} {sentence}")
    audit = dims.audit_repetition(record)
    assert audit.status == dims.STATUS_FLAGGED
    # A verbatim sentence duplicate also re-triggers the phrase check; both codes are honest.
    assert "repeated_sentence" in audit.reason.split(",")


def test_repetition_never_flags_short_common_particles() -> None:
    record = _record(script="네. 네. 네. 예. 예. 네. 예.")
    audit = dims.audit_repetition(record)
    assert audit.status == dims.STATUS_NOT_APPLICABLE
    assert audit.reason == "insufficient_sentence_evidence"


def test_repetition_flags_common_particle_sentences_below_floor() -> None:
    # "좋습니다." repeated is compact length 4 < MIN_SENTENCE_CHARS -> never a repeat flag.
    record = _record(script="좋습니다. 좋습니다. 좋습니다.")
    assert dims.audit_repetition(record).status == dims.STATUS_NOT_APPLICABLE


def test_repetition_flags_repeated_phrase_across_distinct_sentences() -> None:
    record = _record(
        language="en",
        source="rule_based_curation",
        script=(
            "Try the slow roasted barley tea here before you walk the course. "
            "They brew slow roasted barley tea too, so grab a cup for the route."
        ),
    )
    audit = dims.audit_repetition(record)
    assert audit.status == dims.STATUS_FLAGGED
    assert audit.reason == "repeated_phrase"


def test_repetition_passes_distinct_sentences() -> None:
    record = _record(
        script="오늘은 바람이 선선하게 불었습니다. 산책로를 따라 천천히 걸었습니다. 골목 카페에서 잠시 쉬었습니다."
    )
    audit = dims.audit_repetition(record)
    assert audit.status == dims.STATUS_PASS


def test_repetition_is_deterministic() -> None:
    script = "같은 문장이 반복됩니다. 같은 문장이 반복됩니다. 다른 문장도 있습니다."
    assert dims.repetition_reasons(script) == dims.repetition_reasons(script)
    assert dims.repetition_reasons(script) == ["repeated_sentence"]


def test_repetition_scan_is_bounded_and_stable() -> None:
    filler = " ".join(f"이 문장은 서로 다른 내용을 담고 있습니다 {index}." for index in range(900))
    duplicated = "아주 긴 서두 뒤에 붙은 중복 문장입니다. 아주 긴 서두 뒤에 붙은 중복 문장입니다."
    script = filler + " " + duplicated
    assert len(script) > dims.MAX_REPETITION_SCAN_CHARS
    # The duplicate sits beyond the bounded scan window: deterministic, never flagged.
    assert dims.repetition_reasons(script) == []


# --- Sanitizer schema: pass/flagged/not-applicable preserved -------------------


def _lane_c_report() -> dict:
    return {
        "generated_at": "20260905T000000Z",
        "base_url": "https://unit.invalid",
        "run_caps": {"max_places": 50},
        "counters": {"calls": 4, "ok": 3, "service_errors": 1, "transport_errors": 0},
        "token_counters": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        "estimated_cost_usd": 0,
        "place_count": 4,
        "records": [
            _record(place_id="eval-dim-good"),
            {
                "place_id": "eval-dim-error",
                "place_name": "에러 장소",
                "category": "event",
                "region": "서울",
                "language": "ko",
                "expectation": "nonempty",
                "http_status": 503,
                "error_code": "HTTP503",
                "auto_precheck": {"issue_tags": []},
            },
            _record(
                place_id="eval-dim-mock",
                source="demo_fallback",
                script=(
                    "이 장소는 데모 안내입니다. 실제 방문 전에 운영 시간을 확인하세요. "
                    "근처 골목 상권도 함께 둘러보세요."
                ),
            ),
            _record(
                place_id="eval-dim-secret",
                script=(
                    "이 안내에는 키처럼 보이는 표현이 섞여 있습니다. "
                    "sk-AbCdEf123456 골목 근처를 안내합니다. 방문 전후 동선을 확인하세요."
                ),
            ),
        ],
    }


def test_sanitized_report_preserves_all_three_dimension_counts() -> None:
    sanitized = sanitizer.build_sanitized_report(_lane_c_report(), {})
    flags = sanitized["summary"]["dimension_flags"]
    assert set(flags) == set(dims.DIMENSION_ORDER)
    for dimension, counts in flags.items():
        assert set(counts) == {"pass", "flagged", "not_applicable"}
        assert sum(counts.values()) == 4, dimension
    assert flags["grounding"] == {"pass": 3, "flagged": 0, "not_applicable": 1}
    assert flags["source_attribution"] == {"pass": 2, "flagged": 1, "not_applicable": 1}
    assert flags["repetition"] == {"pass": 3, "flagged": 0, "not_applicable": 1}
    assert flags["safety"] == {"pass": 2, "flagged": 1, "not_applicable": 1}
    assert flags["advertising_leakage"] == {"pass": 2, "flagged": 1, "not_applicable": 1}


def test_sanitized_records_carry_verdict_codes_not_raw_evidence() -> None:
    sanitized = sanitizer.build_sanitized_report(_lane_c_report(), {})
    raw_scripts = {
        record["place_id"]: str(record.get("script") or "")
        for record in _lane_c_report()["records"]
    }
    for record in sanitized["records"]:
        verdicts = record["dimension_verdicts"]
        assert set(verdicts) == set(dims.DIMENSION_ORDER)
        for verdict in verdicts.values():
            assert verdict["status"] in _ALLOWED_STATUSES
            assert verdict["reason"].isascii()
        assert "script" not in record
        assert len(record["script_excerpt"]) <= 240
        raw = raw_scripts[record["place_id"]]
        if raw.strip():
            # Verifier defect #5: an excerpt must never equal the whole script.
            assert record["script_excerpt"] != raw
            assert record["script_excerpt"] != " ".join(raw.split())
            assert record["script_excerpt"].endswith(sanitizer._EXCERPT_SUFFIX)


def test_sanitized_excerpt_redacts_secret_like_text() -> None:
    sanitized = sanitizer.build_sanitized_report(_lane_c_report(), {})
    secret_record = next(r for r in sanitized["records"] if r["place_id"] == "eval-dim-secret")
    assert "sk-AbCdEf123456" not in secret_record["script_excerpt"]
    assert "[redacted]" in secret_record["script_excerpt"]


def test_excerpt_never_equals_short_full_script() -> None:
    short = "이 장소는 짧은 안내입니다."
    excerpt = sanitizer.script_excerpt(short)
    assert excerpt != short
    assert excerpt != " ".join(short.split())
    assert excerpt.endswith(sanitizer._EXCERPT_SUFFIX)
    # Deterministic: same input, same elided output.
    assert excerpt == sanitizer.script_excerpt(short)


def test_excerpt_elides_at_least_one_source_character() -> None:
    for script in ("네.", "안내.", "x" * 239, "x" * 240, "x" * 1000):
        excerpt = sanitizer.script_excerpt(script)
        assert excerpt != script
        assert len(excerpt.replace(sanitizer._EXCERPT_SUFFIX, "")) < len(script)


def test_excerpt_redacts_coordinate_pairs() -> None:
    script = "만남 위치는 37.5665, 126.9780 부근이고 골목 산책 동선으로 이어집니다."
    excerpt = sanitizer.script_excerpt(script)
    assert "37.5665" not in excerpt
    assert "126.9780" not in excerpt
    assert "[redacted]" in excerpt


def test_excerpt_redacts_email_and_phone() -> None:
    script = (
        "문의는 guide@example.com 으로 하시고 사전 예약은 010-1234-5678 로 연락하세요. "
        "대표 번호는 +82 2 1234 5678 입니다. 근처 동산 코스도 안내합니다."
    )
    excerpt = sanitizer.script_excerpt(script)
    assert "guide@example.com" not in excerpt
    assert "010-1234-5678" not in excerpt
    assert "1234 5678" not in excerpt
    assert excerpt.count("[redacted]") >= 3


def test_excerpt_does_not_redact_pm_template_text() -> None:
    script = (
        "오늘은 미세먼지 PM10 30, 초미세먼지 PM2.5 12 수준이라 야외 정원 산책도 무리가 없습니다."
    )
    excerpt = sanitizer.script_excerpt(script)
    assert "PM10 30" in excerpt
    assert "PM2.5 12" in excerpt
    assert "[redacted]" not in excerpt


def test_manual_notes_redact_coordinates_email_phone_and_secrets() -> None:
    report = _lane_c_report()
    notes = {
        "places": {
            "eval-dim-good": {
                "verdict": "flagged",
                "notes": (
                    "리뷰어가 좌표 37.5665, 126.9780 와 이메일 reviewer@example.com,"
                    " 전화 010-1234-5678, 키 sk-AbCdEf1234567890 을 메모로 남겼습니다."
                ),
            }
        }
    }
    sanitized = sanitizer.build_sanitized_report(report, notes)
    record = next(r for r in sanitized["records"] if r["place_id"] == "eval-dim-good")
    notes_text = record["manual_notes"]
    assert "37.5665" not in notes_text
    assert "reviewer@example.com" not in notes_text
    assert "010-1234-5678" not in notes_text
    assert "sk-AbCdEf1234567890" not in notes_text
    assert notes_text.count("[redacted]") >= 4


def test_sanitizer_cli_writes_dimension_table_with_not_applicable(tmp_path) -> None:
    report_path = tmp_path / "live-docent-qa-test.json"
    report_path.write_text(json.dumps(_lane_c_report()), encoding="utf-8")
    output_path = tmp_path / "sanitized-report.md"
    exit_code = sanitizer.main(
        [
            str(report_path),
            "--manual-notes",
            str(tmp_path / "missing-notes.json"),
            "--output",
            str(output_path),
        ]
    )
    assert exit_code == 0
    markdown = output_path.read_text(encoding="utf-8")
    assert "| Dimension | Pass | Flagged | Not applicable |" in markdown
    payload = json.loads(output_path.with_suffix(".json").read_text(encoding="utf-8"))
    for counts in payload["summary"]["dimension_flags"].values():
        assert set(counts) == {"pass", "flagged", "not_applicable"}
