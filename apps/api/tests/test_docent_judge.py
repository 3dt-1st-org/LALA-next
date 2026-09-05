"""Tests for the P6B offline-testable docent model-judge contract.

Covers: strict judge-result parsing; every fail-closed class (missing,
malformed, duplicate, unknown, non-finite, out-of-range, contradictory
fields); the double live gate (live-AI gate + separate judge opt-in, OFF by
default); injected fake-provider batch behavior; canary sequencing; the
80-record hard cap; stop-loss (malformed / provider failures / token ceiling);
per-record timeout and no-retry accounting; honest-empty skips; sanitizer
safety of persisted outcomes; stable aggregate output; and the separate
optional judge gate on the offline QA report (``NOT_RUN`` when no judge ran).
"""

from __future__ import annotations

import json
import sys
import time
import types
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

from apps.api.app.core.errors import ServiceError
from apps.api.app.services import docent_judge as judge

_KO_SCRIPT = (
    "호암미술관은 전시와 정원이 어우러진 문화 공간입니다. "
    "관람 전후에는 주변 로컬 카페와 골목을 함께 둘러보세요. "
    "오늘은 미세먼지 PM10 30, 초미세먼지 PM2.5 12 수준이라 야외 정원 산책도 무리가 없습니다."
)
_EN_SCRIPT = (
    "This museum pairs galleries with a quiet garden. "
    "Stop by the nearby neighborhood cafes before or after your visit. "
    "With PM10 30 and PM2.5 12 today, the outdoor garden walk is comfortable."
)


def _payload(
    decision: str = "PASS",
    flagged: tuple[str, ...] = (),
    confidence: Any = 1.0,
    reason: str = "ok",
) -> dict[str, Any]:
    return {
        "decision": decision,
        "dimensions": [
            {
                "dimension": dimension,
                "status": "flagged" if dimension in flagged else "pass",
                "reason": reason,
                "confidence": confidence,
            }
            for dimension in judge.JUDGE_DIMENSIONS
        ],
    }


def _record(
    place_id: str = "eval_attraction_01",
    language: str = "ko",
    script: str | None = None,
) -> dict[str, Any]:
    if script is None:
        script = _KO_SCRIPT if language == "ko" else _EN_SCRIPT
    return {
        "place_id": place_id,
        "language": language,
        "category": "attraction",
        "script": script,
    }


def _roster(count: int = 80, *, empty_at: tuple[int, ...] = ()) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    index = 0
    while len(records) < count:
        place_index = index // 2
        language = "ko" if index % 2 == 0 else "en"
        script = "" if index in empty_at else (_KO_SCRIPT if language == "ko" else _EN_SCRIPT)
        records.append(_record(f"eval_place_{place_index:02d}", language, script))
        index += 1
    return records


class _ScriptedProvider:
    """Test provider: canned replies in call order, exceptions raised, sleeps.

    A reply item may be a ``JudgeProviderReply``, a raw ``str`` (payload JSON),
    a ``dict`` (payload), or an ``Exception`` instance (raised). When
    ``fast_after`` is set, only the first N calls sleep for ``sleep_seconds``;
    later calls return immediately.
    """

    def __init__(
        self,
        replies: list[Any],
        *,
        sleep_seconds: float = 0.0,
        total_tokens: int = 700,
        fast_after: int | None = None,
    ) -> None:
        self.replies = list(replies)
        self.sleep_seconds = sleep_seconds
        self.total_tokens = total_tokens
        self.fast_after = fast_after
        self.seen: list[tuple[str, str]] = []

    def judge(self, record: dict[str, Any]) -> judge.JudgeProviderReply:
        key = (str(record.get("place_id")), str(record.get("language")))
        self.seen.append(key)
        if self.sleep_seconds and (self.fast_after is None or len(self.seen) <= self.fast_after):
            time.sleep(self.sleep_seconds)
        reply = self.replies[min(len(self.seen) - 1, len(self.replies) - 1)]
        if isinstance(reply, Exception):
            raise reply
        if isinstance(reply, judge.JudgeProviderReply):
            return reply
        text = json.dumps(reply) if isinstance(reply, dict) else reply
        return judge.JudgeProviderReply(
            text=text,
            prompt_tokens=100,
            completion_tokens=50,
            total_tokens=self.total_tokens,
        )


# --- Strict parsing: valid payloads -------------------------------------------


def test_valid_pass_payload_parses_with_every_dimension() -> None:
    result = judge.parse_judge_payload(_payload())
    assert result.failure_reason is None
    assert result.decision == judge.DECISION_PASS
    assert result.is_fail_closed is False
    assert tuple(d.dimension for d in result.dimensions) == judge.JUDGE_DIMENSIONS
    for dimension in result.dimensions:
        assert dimension.status == judge.DIMENSION_STATUS_PASS
        assert dimension.reason == "ok"


def test_valid_rewrite_payload_parses() -> None:
    result = judge.parse_judge_payload(_payload(decision="REWRITE", flagged=("repetition",)))
    assert result.failure_reason is None
    assert result.decision == judge.DECISION_REWRITE
    flagged = {d.dimension: d for d in result.dimensions}["repetition"]
    assert flagged.status == judge.DIMENSION_STATUS_FLAGGED


def test_dimension_order_is_not_required() -> None:
    payload = _payload()
    payload["dimensions"] = list(reversed(payload["dimensions"]))
    assert judge.parse_judge_payload(payload).failure_reason is None


def test_parse_judge_response_decodes_json_text() -> None:
    result = judge.parse_judge_response(json.dumps(_payload()))
    assert result.decision == judge.DECISION_PASS
    assert len(result.dimensions) == 11


def test_parse_judge_response_rejects_non_json_text() -> None:
    result = judge.parse_judge_response("the script looks fine to me")
    assert result.is_fail_closed
    assert result.decision == judge.DECISION_REWRITE
    assert result.failure_reason == "invalid_json"


# --- Fail-closed classes -------------------------------------------------------


@pytest.mark.parametrize(
    "payload",
    [
        [],
        "PASS",
        None,
        42,
        True,
    ],
)
def test_non_object_payload_fails_closed(payload: Any) -> None:
    result = judge.parse_judge_payload(payload)
    assert result.decision == judge.DECISION_REWRITE
    assert result.failure_reason == "payload_not_object"
    assert result.dimensions == ()


def test_missing_decision_or_dimensions_fails_closed() -> None:
    missing_decision = _payload()
    del missing_decision["decision"]
    assert judge.parse_judge_payload(missing_decision).failure_reason == "missing_field"
    missing_dimensions = _payload()
    del missing_dimensions["dimensions"]
    assert judge.parse_judge_payload(missing_dimensions).failure_reason == "missing_field"


def test_missing_dimension_entry_field_fails_closed() -> None:
    payload = _payload()
    del payload["dimensions"][3]["reason"]
    assert judge.parse_judge_payload(payload).failure_reason == "missing_field"


@pytest.mark.parametrize(
    "decision",
    ["pass", "Pass", " PASS", "PASS ", "REWRITE".lower(), "APPROVE", 1, None],
)
def test_invalid_decision_fails_closed(decision: Any) -> None:
    payload = _payload(decision=decision)
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_decision"


def test_dimensions_not_a_list_fails_closed() -> None:
    payload = _payload()
    payload["dimensions"] = {"dimension": "repetition"}
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_dimensions_field"
    payload["dimensions"] = "all fine"
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_dimensions_field"


def test_wrong_dimension_count_fails_closed() -> None:
    payload = _payload()
    payload["dimensions"] = payload["dimensions"][:10]
    assert judge.parse_judge_payload(payload).failure_reason == "dimension_count_mismatch"
    overflowing = _payload()
    overflowing["dimensions"] = overflowing["dimensions"] + [dict(overflowing["dimensions"][0])]
    assert judge.parse_judge_payload(overflowing).failure_reason == "dimension_count_mismatch"


def test_duplicate_dimension_fails_closed() -> None:
    payload = _payload()
    payload["dimensions"][4] = dict(payload["dimensions"][0])
    result = judge.parse_judge_payload(payload)
    assert result.decision == judge.DECISION_REWRITE
    assert result.failure_reason == "duplicate_dimension"


def test_unknown_dimension_fails_closed() -> None:
    payload = _payload()
    payload["dimensions"][2]["dimension"] = "vibes"
    assert judge.parse_judge_payload(payload).failure_reason == "unknown_dimension"


def test_unknown_top_level_field_fails_closed() -> None:
    payload = {**_payload(), "overall_score": 91}
    assert judge.parse_judge_payload(payload).failure_reason == "unknown_field"


def test_unknown_dimension_field_fails_closed() -> None:
    payload = _payload()
    payload["dimensions"][1]["excerpt"] = "..."
    assert judge.parse_judge_payload(payload).failure_reason == "unknown_field"


def test_non_object_dimension_entry_fails_closed() -> None:
    payload = _payload()
    payload["dimensions"][7] = ["repetition", "pass"]
    assert judge.parse_judge_payload(payload).failure_reason == "dimension_entry_not_object"


@pytest.mark.parametrize("status", ["ok", "PASS", "FLAGGED", 1, None, ""])
def test_invalid_dimension_status_fails_closed(status: Any) -> None:
    payload = _payload()
    payload["dimensions"][9]["status"] = status
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_dimension_status"


@pytest.mark.parametrize(
    "reason",
    ["", "   ", "x" * 201, "line1\nline2", 7, None],
)
def test_invalid_reason_fails_closed(reason: Any) -> None:
    payload = _payload(reason="ok")
    payload["dimensions"][0]["reason"] = reason
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_reason"


def test_reason_at_bound_is_accepted() -> None:
    payload = _payload(reason="x" * judge.MAX_REASON_CHARS)
    assert judge.parse_judge_payload(payload).failure_reason is None


@pytest.mark.parametrize("confidence", [float("nan"), float("inf"), float("-inf")])
def test_non_finite_confidence_fails_closed(confidence: float) -> None:
    payload = _payload(confidence=confidence)
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_confidence"


@pytest.mark.parametrize("confidence", [-0.1, 1.0001, 2.0, -1])
def test_out_of_range_confidence_fails_closed(confidence: float) -> None:
    payload = _payload(confidence=confidence)
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_confidence"


@pytest.mark.parametrize("confidence", [True, False, "0.9", None])
def test_wrong_type_confidence_fails_closed(confidence: Any) -> None:
    payload = _payload(confidence=confidence)
    assert judge.parse_judge_payload(payload).failure_reason == "invalid_confidence"


def test_confidence_boundary_values_are_accepted() -> None:
    assert judge.parse_judge_payload(_payload(confidence=0.0)).failure_reason is None
    assert judge.parse_judge_payload(_payload(confidence=1)).failure_reason is None


def test_nan_json_literal_fails_closed() -> None:
    text = json.dumps(_payload()).replace('"confidence": 1.0', '"confidence": NaN')
    assert judge.parse_judge_response(text).failure_reason == "invalid_json"


def test_infinite_json_number_fails_closed() -> None:
    text = json.dumps(_payload()).replace('"confidence": 1.0', '"confidence": 1e999')
    assert judge.parse_judge_response(text).failure_reason == "invalid_confidence"


def test_contradictory_pass_with_flagged_dimension_fails_closed() -> None:
    payload = _payload(decision="PASS", flagged=("weather_contradiction",))
    result = judge.parse_judge_payload(payload)
    assert result.decision == judge.DECISION_REWRITE
    assert result.failure_reason == "contradictory_decision"
    assert result.dimensions == ()


def test_contradictory_rewrite_with_all_pass_dimensions_fails_closed() -> None:
    """Reverse contradiction: REWRITE with zero flagged dimensions has no
    supporting evidence and must fail closed exactly like PASS+flagged."""
    payload = _payload(decision="REWRITE")  # every dimension status is pass
    result = judge.parse_judge_payload(payload)
    assert result.decision == judge.DECISION_REWRITE
    assert result.failure_reason == "contradictory_decision"
    assert result.dimensions == ()
    assert result.is_fail_closed is True


def test_fail_closed_result_shape_is_machine_readable() -> None:
    result = judge.parse_judge_payload("not-a-payload")
    public = result.to_public_dict()
    assert public["decision"] == judge.DECISION_REWRITE
    assert public["failure_reason"] == "payload_not_object"
    assert public["dimensions"] == []


# --- Live gate (OFF by default) ------------------------------------------------


def _gate_settings(
    *,
    enable_live_ai: bool = False,
    api_key: str | None = "test-openai-key",  # pragma: allowlist secret
    base_url: str = "",
) -> SimpleNamespace:
    return SimpleNamespace(
        enable_live_ai=enable_live_ai,
        openai_api_key=api_key,
        openai_base_url=base_url,
        model_role_overrides={},
    )


def test_judge_live_enabled_defaults_off(monkeypatch) -> None:
    monkeypatch.delenv("LALA_ENABLE_LIVE_AI", raising=False)
    monkeypatch.delenv("LALA_DOCENT_QA_JUDGE", raising=False)
    assert judge.judge_live_enabled(_gate_settings()) is False


def test_judge_live_enabled_requires_both_gates(monkeypatch) -> None:
    live_on = _gate_settings(enable_live_ai=True)
    live_off = _gate_settings(enable_live_ai=False)
    monkeypatch.setenv("LALA_DOCENT_QA_JUDGE", "true")
    # Judge opt-in alone (live-AI gate off) is not enough.
    assert judge.judge_live_enabled(live_off) is False
    monkeypatch.delenv("LALA_DOCENT_QA_JUDGE", raising=False)
    # Live-AI gate alone (judge opt-in off) is not enough.
    assert judge.judge_live_enabled(live_on) is False
    monkeypatch.setenv("LALA_DOCENT_QA_JUDGE", "true")
    assert judge.judge_live_enabled(live_on) is True


def test_judge_live_enabled_requires_api_key(monkeypatch) -> None:
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("LALA_DOCENT_QA_JUDGE", "true")
    assert judge.judge_live_enabled(_gate_settings(enable_live_ai=True, api_key=None)) is False


def test_judge_live_enabled_rejects_azure_base_url(monkeypatch) -> None:
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("LALA_DOCENT_QA_JUDGE", "true")
    azure = _gate_settings(
        enable_live_ai=True,
        base_url="https://example.openai.azure.com/openai",
    )
    assert judge.judge_live_enabled(azure) is False


def _install_openai_stub(monkeypatch, client_factory) -> types.ModuleType:
    module = types.ModuleType("openai")

    class _OpenAI:
        def __init__(self, **kwargs: Any) -> None:
            client = client_factory(kwargs)
            self.chat = client.chat

    module.OpenAI = _OpenAI  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "openai", module)
    return module


def test_build_live_provider_refuses_when_gates_off(monkeypatch) -> None:
    def _explode(_kwargs: Any) -> None:
        raise AssertionError("live client constructed despite gates off")

    _install_openai_stub(monkeypatch, _explode)
    monkeypatch.delenv("LALA_ENABLE_LIVE_AI", raising=False)
    monkeypatch.delenv("LALA_DOCENT_QA_JUDGE", raising=False)
    with pytest.raises(ServiceError) as excinfo:
        judge.build_live_provider(_gate_settings())
    assert excinfo.value.code == "DOCENT_JUDGE_NOT_ENABLED"


def test_build_live_provider_constructs_no_retry_client_and_resolves_docent_qa_role(
    monkeypatch,
) -> None:
    captured: dict[str, Any] = {}

    def _make_client(kwargs: Any) -> Any:
        captured.update(kwargs)

        def _create(**call_kwargs: Any) -> Any:
            captured["create_kwargs"] = call_kwargs
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps(_payload())))],
                usage=SimpleNamespace(prompt_tokens=11, completion_tokens=7, total_tokens=18),
            )

        return SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=_create)))

    _install_openai_stub(monkeypatch, _make_client)
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("LALA_DOCENT_QA_JUDGE", "true")
    provider = judge.build_live_provider(_gate_settings(enable_live_ai=True))
    assert captured["max_retries"] == 0, "provider must never auto-retry (spend multiplier)"
    assert captured["timeout"] == judge.DOCENT_JUDGE_TIMEOUT_SECONDS
    reply = provider.judge(_record())
    assert judge.parse_judge_response(reply.text).decision == judge.DECISION_PASS
    assert reply.total_tokens == 18
    # The docent_qa role is resolved separately from docent generation.
    assert captured["create_kwargs"]["model"] == "gpt-5.4-mini"


# --- Bounded batch policy (provider-free) --------------------------------------


def test_policy_defaults_enforce_the_hard_roster_cap() -> None:
    policy = judge.JudgeBatchPolicy()
    policy.validate()
    assert policy.max_records == judge.HARD_MAX_RECORDS == 80


@pytest.mark.parametrize(
    "overrides",
    [
        {"max_records": 81},
        {"canary_size": 0},
        {"canary_size": 80},
        {"max_concurrency": 0},
        {"max_concurrency": 17},
        {"per_record_timeout_seconds": 0.0},
        {"per_record_timeout_seconds": -1.0},
        {"per_record_timeout_seconds": float("inf")},
        {"per_record_timeout_seconds": "5"},
        {"max_malformed_responses": 0},
        {"max_provider_failures": 0},
        {"max_total_tokens": 0},
        {"max_records": True},
    ],
)
def test_policy_validation_rejects_nonsensical_bounds(overrides: dict[str, Any]) -> None:
    policy = judge.JudgeBatchPolicy(**overrides)
    with pytest.raises(ValueError):
        policy.validate()


def test_policy_plan_caps_roster_and_splits_canary() -> None:
    policy = judge.JudgeBatchPolicy(max_records=10, canary_size=3)
    records = _roster(13)
    plan = policy.plan(records)
    assert plan.dropped_by_cap == 3
    assert len(plan.canary) == 3
    assert len(plan.remainder) == 7
    assert [r["place_id"] for r in plan.canary] == [records[i]["place_id"] for i in range(3)]


# --- Batch runner with injected fake providers ---------------------------------


def test_full_roster_batch_passes_with_fake_provider() -> None:
    provider = judge.FakeJudgeProvider()
    run = judge.run_judge_batch(_roster(80), provider=provider)
    assert run.halted is False
    assert run.counters["judged"] == 80
    assert run.counters["pass_decisions"] == 80
    assert run.counters["rewrite_decisions"] == 0
    assert run.gate_status() == judge.DECISION_PASS
    assert len(provider.seen) == 80
    assert len(run.outcomes) == 80


def test_batch_summary_is_stable_across_runs() -> None:
    records = _roster(20)
    first = judge.run_judge_batch(records, provider=judge.FakeJudgeProvider())
    second = judge.run_judge_batch(records, provider=judge.FakeJudgeProvider())
    assert first.summarize() == second.summarize()
    assert first.summarize() == first.summarize()


def test_batch_judges_ko_and_en_and_skips_honest_empty() -> None:
    provider = judge.FakeJudgeProvider()
    records = [
        _record("eval_ko_01", "ko"),
        _record("eval_en_01", "en"),
        _record("eval_minimal", "ko", ""),
    ]
    run = judge.run_judge_batch(records, provider=provider)
    assert run.counters["judged"] == 2
    assert run.counters["skipped_no_script"] == 1
    assert provider.seen == [("eval_ko_01", "ko"), ("eval_en_01", "en")]
    by_key = {(o.place_id, o.language): o for o in run.outcomes}
    assert by_key[("eval_ko_01", "ko")].decision == judge.DECISION_PASS
    assert by_key[("eval_en_01", "en")].decision == judge.DECISION_PASS
    empty = by_key[("eval_minimal", "ko")]
    assert empty.decision is None
    assert empty.error_code == judge.ERROR_SKIPPED_NO_SCRIPT
    assert empty.script_excerpt == ""
    assert run.gate_status() == judge.DECISION_PASS


# --- Honest-empty records are skipped BEFORE provider submission ----------------


def test_empty_in_nonfinal_canary_position_is_never_submitted() -> None:
    """Empty at canary index 1 (not last): classified before submission, so
    provider invocations equal the judgeable records exactly."""
    provider = _ScriptedProvider([json.dumps(_payload())])
    policy = judge.JudgeBatchPolicy(canary_size=4, max_concurrency=1)
    records = _roster(6, empty_at=(1,))
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    judgeable = [r for r in records if r["script"].strip()]
    assert len(judgeable) == 5
    assert len(provider.seen) == len(judgeable)
    assert ("eval_place_00", "en") not in provider.seen  # the empty record
    empty_outcome = next(o for o in run.outcomes if o.error_code == judge.ERROR_SKIPPED_NO_SCRIPT)
    assert empty_outcome.place_id == "eval_place_00"
    assert empty_outcome.language == "en"
    assert run.counters["skipped_no_script"] == 1
    assert run.counters["judged"] == 5


def test_multiple_empties_in_remainder_waves_are_never_submitted() -> None:
    """Empties at roster indices 5 and 9 (inside remainder waves): invocation
    count equals the non-empty submitted records, never the full roster."""
    provider = _ScriptedProvider([json.dumps(_payload())])
    policy = judge.JudgeBatchPolicy(canary_size=4, max_concurrency=4)
    records = _roster(12, empty_at=(5, 9))
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    judgeable = [r for r in records if r["script"].strip()]
    assert len(judgeable) == 10
    assert len(provider.seen) == 10, "empties must never reach the provider"
    assert run.counters["skipped_no_script"] == 2
    assert run.counters["judged"] == 10
    assert run.counters["dropped_by_cap"] == 0
    assert run.gate_status() == judge.DECISION_PASS


def test_provider_invocations_equal_judgeable_records_on_fixture_shaped_roster() -> None:
    """A fixture-shaped roster with the honest-empty pair at positions 18/19
    (inside the remainder) must consume exactly 78 provider calls for 78
    judgeable records."""
    provider = judge.FakeJudgeProvider()
    records = _roster(80, empty_at=(18, 19))
    run = judge.run_judge_batch(records, provider=provider)
    assert len(provider.seen) == 78
    assert run.counters["judged"] == 78
    assert run.counters["skipped_no_script"] == 2


# --- Aggregate gate: sub-stop-loss errors never yield PASS ----------------------


def test_mixed_pass_and_provider_error_is_incomplete_not_pass() -> None:
    provider = _ScriptedProvider([RuntimeError("boom")] + [json.dumps(_payload())] * 7)
    policy = judge.JudgeBatchPolicy(canary_size=4, max_concurrency=4, max_provider_failures=3)
    run = judge.run_judge_batch(_roster(8), provider=provider, policy=policy)
    assert run.halted is False
    assert run.counters["provider_failures"] == 1
    assert run.counters["judged"] == 7
    assert run.gate_status() == judge.GATE_INCOMPLETE
    assert run.gate_status() != judge.DECISION_PASS


def test_mixed_pass_and_timeout_is_incomplete_not_pass() -> None:
    provider = _ScriptedProvider([json.dumps(_payload())], sleep_seconds=0.15, fast_after=1)
    policy = judge.JudgeBatchPolicy(
        canary_size=4,
        max_concurrency=4,
        per_record_timeout_seconds=0.03,
        max_provider_failures=3,
    )
    run = judge.run_judge_batch(_roster(8), provider=provider, policy=policy)
    assert run.counters["provider_timeouts"] >= 1
    assert run.halted is False
    assert run.gate_status() == judge.GATE_INCOMPLETE


def test_halted_run_reports_halted_not_pass() -> None:
    provider = _ScriptedProvider([json.dumps(_payload())], total_tokens=400_000)
    policy = judge.JudgeBatchPolicy(canary_size=1, max_total_tokens=300_000)
    run = judge.run_judge_batch(_roster(4), provider=provider, policy=policy)
    assert run.halted is True
    assert run.gate_status() == judge.GATE_HALTED


def test_rewrite_keeps_precedence_over_incomplete_and_halted() -> None:
    provider = _ScriptedProvider(["<not-json>", RuntimeError("boom")])
    policy = judge.JudgeBatchPolicy(canary_size=2, max_concurrency=1, max_provider_failures=3)
    run = judge.run_judge_batch(_roster(6), provider=provider, policy=policy)
    assert run.counters["malformed_responses"] == 1
    assert run.counters["provider_failures"] >= 1
    # The malformed record's fail-closed REWRITE outranks every other status.
    assert run.gate_status() == judge.DECISION_REWRITE


def test_all_honest_empty_roster_reports_no_verdicts() -> None:
    provider = judge.FakeJudgeProvider()
    records = [_record("eval_minimal", "ko", ""), _record("eval_minimal", "en", "")]
    run = judge.run_judge_batch(records, provider=provider)
    assert provider.seen == []
    assert run.counters["skipped_no_script"] == 2
    assert run.gate_status() == judge.GATE_NO_VERDICTS


# --- Reported usage is clamped before stop-loss accounting ----------------------


def test_negative_token_usage_cannot_reduce_stop_loss_accounting() -> None:
    negative = judge.JudgeProviderReply(text=json.dumps(_payload()), total_tokens=-500_000)
    provider = _ScriptedProvider([negative])
    run = judge.run_judge_batch([_record()], provider=provider)
    assert run.total_tokens == 0
    assert run.halted is False  # negative usage neither halted nor reduced anything
    # A subsequent real ceiling still trips on its own merits.
    ceiling = judge.JudgeProviderReply(text=json.dumps(_payload()), total_tokens=300_000)
    provider = _ScriptedProvider([ceiling])
    policy = judge.JudgeBatchPolicy(canary_size=1, max_total_tokens=300_000)
    run = judge.run_judge_batch(_roster(4), provider=provider, policy=policy)
    assert run.halted is True
    assert run.halt_reason == judge.HALT_USAGE


def test_invalid_token_usage_type_is_counted_as_zero() -> None:
    bogus = judge.JudgeProviderReply(text=json.dumps(_payload()), total_tokens="not-a-number")
    provider = _ScriptedProvider([bogus])
    run = judge.run_judge_batch([_record()], provider=provider)
    assert run.total_tokens == 0
    assert run.counters["judged"] == 1


def test_canary_runs_before_remainder_in_roster_order() -> None:
    provider = _ScriptedProvider([json.dumps(_payload())])
    policy = judge.JudgeBatchPolicy(canary_size=4, max_concurrency=1)
    records = _roster(10)
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    assert run.halted is False
    expected = [(r["place_id"], r["language"]) for r in records]
    assert provider.seen == expected
    assert run.counters["canary_records"] == 4
    assert run.counters["remainder_records"] == 6


def test_canary_malformed_responses_halt_before_remainder() -> None:
    provider = _ScriptedProvider(["<not-json>"])
    policy = judge.JudgeBatchPolicy(canary_size=2, max_malformed_responses=1)
    records = _roster(6)
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    assert run.halted is True
    assert run.halt_reason == judge.HALT_MALFORMED
    assert provider.seen == [(r["place_id"], r["language"]) for r in records[:1]]
    assert run.counters["malformed_responses"] == 1
    assert run.counters["skipped_batch_halted"] == 5
    malformed = run.outcomes[0]
    assert malformed.decision == judge.DECISION_REWRITE
    assert malformed.failure_reason == "invalid_json"
    assert run.gate_status() == judge.DECISION_REWRITE


def test_provider_failures_stop_loss_without_retries() -> None:
    provider = _ScriptedProvider([RuntimeError("boom")])
    policy = judge.JudgeBatchPolicy(canary_size=1, max_provider_failures=2, max_concurrency=1)
    records = _roster(5)
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    assert run.halted is True
    assert run.halt_reason == judge.HALT_PROVIDER_FAILURES
    assert run.counters["provider_failures"] == 2
    assert run.counters["provider_timeouts"] == 0
    # Exactly one call per record — no automatic retries that could multiply spend.
    assert provider.seen == [(r["place_id"], r["language"]) for r in records[:2]]
    assert len(set(provider.seen)) == len(provider.seen)
    assert run.counters["skipped_batch_halted"] == 3
    assert all(outcome.error_code == judge.ERROR_PROVIDER_FAILURE for outcome in run.outcomes[:2])
    assert run.gate_status() == "HALTED"


def test_token_ceiling_stop_loss_halts_batch() -> None:
    provider = _ScriptedProvider([_payload()], total_tokens=150_000)
    policy = judge.JudgeBatchPolicy(canary_size=2, max_total_tokens=300_000)
    records = _roster(8)
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    assert run.halted is True
    assert run.halt_reason == judge.HALT_USAGE
    assert run.total_tokens == 300_000
    assert run.counters["judged"] == 2
    assert run.counters["skipped_batch_halted"] == 6
    assert len(provider.seen) == 2


def test_per_record_timeout_is_accounted_never_retried() -> None:
    provider = _ScriptedProvider([_payload()], sleep_seconds=0.25)
    policy = judge.JudgeBatchPolicy(
        canary_size=1,
        max_concurrency=2,
        per_record_timeout_seconds=0.05,
        max_provider_failures=3,
    )
    records = _roster(4)
    run = judge.run_judge_batch(records, provider=provider, policy=policy)
    assert run.halted is True
    assert run.halt_reason == judge.HALT_PROVIDER_FAILURES
    assert run.counters["provider_timeouts"] == 3
    assert run.counters["skipped_batch_halted"] == 1
    assert len(set(provider.seen)) == len(provider.seen)
    error_codes = [outcome.error_code for outcome in run.outcomes if outcome.error_code]
    assert error_codes == [judge.ERROR_PROVIDER_TIMEOUT] * 3 + [judge.ERROR_SKIPPED_BATCH_HALTED]


def test_eighty_record_hard_cap_drops_overflow() -> None:
    provider = judge.FakeJudgeProvider()
    run = judge.run_judge_batch(_roster(85), provider=provider)
    assert run.counters["dropped_by_cap"] == 5
    assert run.counters["judged"] == 80
    assert len(run.outcomes) == 80
    assert len(provider.seen) == 80
    # Cap overflow fails closed: records beyond the hard cap were never judged,
    # so the aggregate gate can never report PASS.
    assert run.gate_status() == judge.GATE_INCOMPLETE


def test_empty_roster_reports_no_verdicts_never_pass() -> None:
    run = judge.run_judge_batch([], provider=judge.FakeJudgeProvider())
    assert run.gate_status() == "NO_VERDICTS"
    assert run.counters["judged"] == 0


# --- Sanitizer safety of persisted outcomes ------------------------------------


def test_persisted_outcomes_never_carry_raw_script_or_secret_text() -> None:
    dirty_script = (
        "관리자 키 sk-AbCdEf1234567890 로 접속하세요. 만남 위치는 37.5665, 126.9780 "
        "부근이고 문의는 guide@example.com 으로하세요. 골목 산책 동선도 안내합니다."
    )
    # The reason code carries a secret-like string that must be redacted even
    # in the persisted reason; the raw payload/review text is never persisted.
    payload = _payload(reason="leak postgres://user:pw@host/db")
    provider = _ScriptedProvider([payload])
    run = judge.run_judge_batch([_record("eval_dirty_01", "ko", dirty_script)], provider=provider)
    outcome = run.outcomes[0].to_public_dict()
    blob = json.dumps(outcome, ensure_ascii=False)
    assert "sk-AbCdEf1234567890" not in blob
    assert "37.5665" not in blob
    assert "guide@example.com" not in blob
    assert "postgres://user:pw@host/db" not in blob  # pragma: allowlist secret
    assert "raw provider review text" not in blob
    assert dirty_script not in blob
    excerpt = outcome["script_excerpt"]
    assert excerpt != dirty_script
    assert excerpt.endswith(" ...")
    assert "[redacted]" in excerpt
    first_reason = outcome["dimensions"][0]["reason"]
    assert "[redacted]" in first_reason
    assert "postgres://" not in first_reason


def test_prompt_never_carries_secrets_or_full_overlong_scripts() -> None:
    long_script = "골목 산책 동선 안내. " * 600
    record = _record("eval_long_01", "ko", long_script)
    _system, user = judge.build_judge_prompt(record)
    assert len(user) < len(long_script)
    assert judge.MAX_PROMPT_SCRIPT_CHARS == 4_000


def test_prompt_redacts_secrets_coordinates_and_direct_pii() -> None:
    dirty_script = (
        "관리자 키 sk-AbCdEf1234567890 로 접속하세요. 만남 위치는 37.5665, 126.9780 "
        "부근이고 문의는 guide@example.com 으로하세요. 골목 산책 동선도 안내합니다."
    )
    _system, user = judge.build_judge_prompt(_record("eval_dirty_01", "ko", dirty_script))
    assert "sk-AbCdEf1234567890" not in user
    assert "37.5665" not in user
    assert "126.9780" not in user
    assert "guide@example.com" not in user
    assert "[redacted]" in user


def test_prompt_omits_raw_place_id_and_whitelists_metadata() -> None:
    huge_id = "eval_" + "x" * 100_000
    record = _record(huge_id, "ko", _KO_SCRIPT)
    record["language"] = "ko" * 10_000
    record["category"] = "category" * 10_000
    _system, user = judge.build_judge_prompt(record)
    # No raw internal place identifier is ever sent to the provider.
    assert "Place id:" not in user
    assert "eval_x" not in user
    assert huge_id not in user
    # Metadata is whitelist-bounded: unknown values become the literal unknown.
    assert "Language: unknown" in user
    assert "Category: unknown" in user
    assert "Language: koko" not in user
    assert len(user) < 1_000


def test_prompt_keeps_whitelisted_language_and_category_labels() -> None:
    record = _record("eval_attraction_01", "en", _EN_SCRIPT)
    record["category"] = "restaurant"
    _system, user = judge.build_judge_prompt(record)
    assert "Language: en" in user
    assert "Category: restaurant" in user


def test_judge_result_public_dict_sanitizes_model_authored_reasons() -> None:
    payload = _payload(reason="leak postgres://user:pw@host/db")  # pragma: allowlist secret
    result = judge.parse_judge_payload(payload)
    assert result.failure_reason is None
    public = result.to_public_dict()
    blob = json.dumps(public, ensure_ascii=False)
    assert "postgres://" not in blob
    assert "[redacted]" in public["dimensions"][0]["reason"]
    assert public["dimensions"][0]["dimension"] == judge.JUDGE_DIMENSIONS[0]


# --- Judge gate section (separate optional gate on the report) -----------------


def test_judge_gate_section_not_run_when_no_judge_ran() -> None:
    assert judge.judge_gate_section(None) == {"status": "NOT_RUN"}
    # The default invocation is provider-free and exactly NOT_RUN.
    assert judge.judge_gate_section(None, simulated=True) == {"status": "NOT_RUN"}


def test_judge_gate_section_carries_run_summary() -> None:
    run = judge.run_judge_batch(_roster(4), provider=judge.FakeJudgeProvider())
    section = judge.judge_gate_section(run)
    assert section["status"] == judge.DECISION_PASS
    assert section == run.summarize()
    assert set(section["per_dimension"]) == set(judge.JUDGE_DIMENSIONS)


def test_simulated_gate_section_is_labeled_and_never_equals_real_pass() -> None:
    run = judge.run_judge_batch(_roster(4), provider=judge.FakeJudgeProvider())
    section = judge.judge_gate_section(run, simulated=True)
    assert section["status"] == judge.GATE_SIMULATED
    assert section["status"] != judge.DECISION_PASS
    assert section["provider"] == judge.SIMULATED_PROVIDER_LABEL
    assert section["simulated"] is True
    # The real aggregate semantics live nested and clearly subordinate.
    assert section["simulated_result"] == run.summarize()
    assert section["simulated_result"]["status"] == judge.DECISION_PASS
    # A simulated section can never be confused with a real-run summary shape.
    assert set(section) == {"status", "provider", "simulated", "simulated_result"}


# --- Offline QA report integration (run_docent_eval CLI) -----------------------


def _run_eval_cli(tmp_path: Path, *extra_args: str) -> dict[str, Any]:
    from apps.api.app.services import docent_eval
    from apps.api.app.tools import run_docent_eval

    fixture_path = tmp_path / "fixture.json"
    fixture_path.write_text(
        json.dumps(docent_eval.load_fixture(), ensure_ascii=False), encoding="utf-8"
    )
    output_path = tmp_path / "report.json"
    exit_code = run_docent_eval.main(
        ["--fixture", str(fixture_path), "--output", str(output_path), *extra_args]
    )
    assert exit_code == 0
    return json.loads(output_path.read_text(encoding="utf-8"))


def test_offline_report_defaults_to_judge_not_run(tmp_path) -> None:
    report = _run_eval_cli(tmp_path)
    assert report["judge_gate"] == {"status": "NOT_RUN"}
    # Deterministic P6A results are unchanged by the separate judge gate.
    assert report["passed"] is True
    assert report["total_places"] == 40
    assert report["total_language_cases"] == 80
    assert report["live_client_constructions"] == 0


def test_offline_report_judge_fake_is_labeled_simulated(tmp_path, capsys) -> None:
    report = _run_eval_cli(tmp_path, "--judge-fake")
    gate = report["judge_gate"]
    # Simulation-only labeling: the top status can never equal the real gate PASS.
    assert gate["status"] == judge.GATE_SIMULATED
    assert gate["status"] != judge.DECISION_PASS
    assert gate["provider"] == judge.SIMULATED_PROVIDER_LABEL
    assert gate["simulated"] is True
    simulated = gate["simulated_result"]
    assert simulated["counters"]["judged"] == 78
    assert simulated["counters"]["skipped_no_script"] == 2
    assert simulated["counters"]["pass_decisions"] == 78
    assert simulated["halted"] is False
    assert simulated["policy"]["max_records"] == 80
    assert set(simulated["per_dimension"]) == set(judge.JUDGE_DIMENSIONS)
    # The CLI summary is visibly simulation-only too.
    assert "judge_gate=SIMULATED" in capsys.readouterr().out
    # The deterministic P6A fields stay identical with the judge gate present.
    assert report["passed"] is True
    assert report["total_places"] == 40
    assert report["total_language_cases"] == 80
    assert report["live_client_constructions"] == 0
