"""Offline-testable, fail-closed model-judge boundary for docent QA (P6B).

Defines the strict structured judge contract for the established ``docent_qa``
model role, the live-judge gate, and the bounded batch policy for the existing
80-language-record roster.

Honesty rules (binding):

- The judge result carries exactly one overall decision — ``PASS`` or
  ``REWRITE`` — plus one bounded result per dimension. Every dimension result
  carries a machine-readable status (``pass`` / ``flagged``) and a concise
  reason code.
- Parsing is strict and fail-closed: missing, malformed, duplicate, unknown,
  non-finite, out-of-range, or contradictory fields always collapse the record
  verdict to ``REWRITE`` with a machine-readable failure reason code. A
  ``PASS`` with any flagged dimension is contradictory and fails closed.
- Live model judging is OFF by default. A production code path requires the
  existing explicit live-AI gate (``LALA_ENABLE_LIVE_AI`` + standard OpenAI
  key, Azure base URLs rejected) AND the separate ``docent_qa_judge``
  opt-in flag, and resolves the ``docent_qa`` model role separately from
  docent generation. No new provider, Azure path, raw-key path, or
  direct-token path is introduced.
- The batch is bounded: hard maximum 80 language records, a small canary
  before the remainder, finite concurrency, a per-record timeout, exactly one
  provider call per record (no automatic retries that could multiply spend),
  and a stop-loss halting the batch on malformed responses, repeated provider
  failures, or a configured token-usage ceiling. The policy is pure data and
  is independently unit-testable without any provider.
- Nothing raw is logged or persisted: no raw provider payloads, raw review
  text, secrets, personal data, precise coordinates, or cloud identifiers.
  Persisted outcomes carry only the sanitized record identity, the decision,
  dimension statuses/reason codes (sanitized), bounded redacted script
  excerpts via the P6A sanitizer, and aggregate counters.
- The judge gate is a separate optional gate on the offline QA report; when no
  judge ran it reports ``NOT_RUN``, never ``PASS``. It never upgrades the
  deterministic P6A results into claims of broad factual truth or production
  readiness.
"""

from __future__ import annotations

import json
import math
from collections.abc import Sequence
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import asdict, dataclass, field
from typing import Any, Protocol

from apps.api.app.core.config import get_settings, resolve_openai_base_url_host
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.model_client import resolve
from apps.api.app.tools.sanitize_docent_qa_report import sanitize_text, script_excerpt

DECISION_PASS = "PASS"
DECISION_REWRITE = "REWRITE"
DIMENSION_STATUS_PASS = "pass"
DIMENSION_STATUS_FLAGGED = "flagged"
_ALLOWED_DECISIONS = (DECISION_PASS, DECISION_REWRITE)
_ALLOWED_DIMENSION_STATUSES = (DIMENSION_STATUS_PASS, DIMENSION_STATUS_FLAGGED)

# Exactly the bounded judge dimension set. One structured result per dimension
# is required; anything else fails closed.
JUDGE_DIMENSIONS: tuple[str, ...] = (
    "language_purity",
    "factual_grounding",
    "local_context",
    "persona_fit",
    "useful_visitor_guidance",
    "unsafe_or_unsupported_claims",
    "source_rights_caution",
    "markdown_tts_suitability",
    "weather_contradiction",
    "repetition",
    "internal_score_leakage",
)
_DIMENSION_SET = frozenset(JUDGE_DIMENSIONS)

MAX_REASON_CHARS = 200
# The script handed to the judge prompt is bounded so a single record can never
# blow up per-record spend.
MAX_PROMPT_SCRIPT_CHARS = 4_000

DOCENT_JUDGE_TIMEOUT_SECONDS = 8.0
DOCENT_JUDGE_MAX_COMPLETION_TOKENS = 500

# Hard roster ceiling for one judge batch: the existing 40-place x KO+EN
# offline roster is exactly 80 language records; no policy may exceed it.
HARD_MAX_RECORDS = 80


@dataclass(frozen=True)
class JudgeDimensionResult:
    """One bounded dimension verdict inside a judge result."""

    dimension: str
    status: str
    reason: str

    def to_public_dict(self) -> dict[str, str]:
        return asdict(self)


@dataclass(frozen=True)
class JudgeResult:
    """One strict judge verdict for one record.

    ``failure_reason`` is ``None`` only for a fully valid payload. Any parse
    or contract violation collapses the decision to ``REWRITE`` with a
    machine-readable failure reason code and no trusted dimension results.
    """

    decision: str
    dimensions: tuple[JudgeDimensionResult, ...] = ()
    failure_reason: str | None = None

    @property
    def is_fail_closed(self) -> bool:
        return self.failure_reason is not None

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "decision": self.decision,
            "failure_reason": self.failure_reason,
            "dimensions": [dimension.to_public_dict() for dimension in self.dimensions],
        }


def _fail_closed(reason_code: str) -> JudgeResult:
    return JudgeResult(decision=DECISION_REWRITE, dimensions=(), failure_reason=reason_code)


def _valid_confidence(value: Any) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    number = float(value)
    return math.isfinite(number) and 0.0 <= number <= 1.0


def parse_judge_payload(payload: Any) -> JudgeResult:
    """Strictly validate a structured judge payload; fail closed to ``REWRITE``.

    The payload must be exactly ``{"decision": "PASS"|"REWRITE", "dimensions":
    [{"dimension", "status", "reason", "confidence"}, ...]}`` with exactly one
    entry per known dimension (no duplicates, no unknown dimensions, no
    unknown fields, no missing fields). ``reason`` is 1..200 characters;
    ``confidence`` is a finite number in [0, 1] (bools rejected). A ``PASS``
    decision with any flagged dimension is contradictory and fails closed.
    """
    if not isinstance(payload, dict):
        return _fail_closed("payload_not_object")
    expected_keys = {"decision", "dimensions"}
    actual_keys = set(payload)
    if actual_keys != expected_keys:
        if not expected_keys.issubset(actual_keys):
            return _fail_closed("missing_field")
        return _fail_closed("unknown_field")

    decision = payload["decision"]
    if not isinstance(decision, str) or decision not in _ALLOWED_DECISIONS:
        return _fail_closed("invalid_decision")

    raw_dimensions = payload["dimensions"]
    if not isinstance(raw_dimensions, list):
        return _fail_closed("invalid_dimensions_field")
    if len(raw_dimensions) != len(JUDGE_DIMENSIONS):
        return _fail_closed("dimension_count_mismatch")

    expected_entry_keys = {"dimension", "status", "reason", "confidence"}
    results: list[JudgeDimensionResult] = []
    seen_dimensions: set[str] = set()
    for entry in raw_dimensions:
        if not isinstance(entry, dict):
            return _fail_closed("dimension_entry_not_object")
        if set(entry) != expected_entry_keys:
            if not expected_entry_keys.issubset(entry):
                return _fail_closed("missing_field")
            return _fail_closed("unknown_field")
        dimension = entry["dimension"]
        if not isinstance(dimension, str) or dimension not in _DIMENSION_SET:
            return _fail_closed("unknown_dimension")
        if dimension in seen_dimensions:
            return _fail_closed("duplicate_dimension")
        seen_dimensions.add(dimension)
        status = entry["status"]
        if not isinstance(status, str) or status not in _ALLOWED_DIMENSION_STATUSES:
            return _fail_closed("invalid_dimension_status")
        reason = entry["reason"]
        if (
            not isinstance(reason, str)
            or not reason.strip()
            or "\n" in reason
            or len(reason) > MAX_REASON_CHARS
        ):
            return _fail_closed("invalid_reason")
        if not _valid_confidence(entry["confidence"]):
            return _fail_closed("invalid_confidence")
        results.append(JudgeDimensionResult(dimension=dimension, status=status, reason=reason))

    if decision == DECISION_PASS and any(
        result.status == DIMENSION_STATUS_FLAGGED for result in results
    ):
        return _fail_closed("contradictory_decision")
    return JudgeResult(decision=decision, dimensions=tuple(results))


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant rejected: {value}")


def parse_judge_response(text: str) -> JudgeResult:
    """Parse a raw provider reply string; any decode failure fails closed."""
    try:
        payload = json.loads(text, parse_constant=_reject_json_constant)
    except (TypeError, ValueError):
        return _fail_closed("invalid_json")
    return parse_judge_payload(payload)


# --- Live gate (OFF by default) ------------------------------------------------


def judge_live_enabled(settings: Any | None = None) -> bool:
    """The live judge gate: existing live-AI gate AND a separate judge opt-in.

    Requires the standard-OpenAI firewall (Azure base URLs rejected), the
    ``docent_qa`` role to resolve (separately from docent generation), the
    explicit ``LALA_ENABLE_LIVE_AI`` gate with an API key, and the separate
    ``docent_qa_judge`` feature flag. Defaults to False on every axis.
    """
    from apps.api.app.core.feature_flags import resolve_feature_flags

    settings = settings or get_settings()
    try:
        resolve_openai_base_url_host(settings.openai_base_url)
        resolve("docent_qa", settings)
    except ValueError:
        return False
    if not (settings.enable_live_ai and settings.openai_api_key):
        return False
    return resolve_feature_flags().get("docent_qa_judge") is True


def build_judge_prompt(record: dict[str, Any]) -> tuple[str, str]:
    """Build the (system, user) judge prompt for one record.

    The prompt carries only the sanitized record identity and a bounded script
    excerpt as input; it never carries secrets by construction.
    """
    dimension_names = ", ".join(JUDGE_DIMENSIONS)
    system = (
        "You are a strict docent script QA judge. Reply with exactly ONE JSON object and "
        'nothing else. Schema: {"decision": "PASS" or "REWRITE", "dimensions": [{"dimension": D,'
        ' "status": "pass" or "flagged", "reason": "<concise code>", "confidence": C}, ...]}. '
        f"Provide exactly one entry for each of these dimensions (any order): {dimension_names}. "
        "reason is a concise machine-readable code of at most 200 characters with no newline. "
        "confidence is a finite number between 0 and 1 inclusive. "
        "decision must be PASS only when every dimension status is pass; otherwise REWRITE. "
        "Add no other field."
    )
    script = str(record.get("script") or "")[:MAX_PROMPT_SCRIPT_CHARS]
    user = (
        f"Place id: {record.get('place_id')}\n"
        f"Language: {record.get('language')}\n"
        f"Category: {record.get('category')}\n"
        f"Script:\n{script}"
    )
    return system, user


@dataclass(frozen=True)
class JudgeProviderReply:
    """Provider reply boundary object: raw text plus optional usage counters.

    ``text`` is consumed only by the strict fail-closed parser and is never
    persisted. Usage counters feed the stop-loss accounting only.
    """

    text: str
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0


class JudgeProvider(Protocol):
    """The judge provider boundary. Tests/offline runners inject a fake."""

    def judge(self, record: dict[str, Any]) -> JudgeProviderReply: ...


@dataclass
class FakeJudgeProvider:
    """Deterministic offline boundary fake. Never used by a production path.

    Returns a canonical all-``PASS`` judge payload for every record so the
    offline evaluator can exercise the full judge pipeline with zero network
    or paid calls. Records the (place_id, language) pairs it actually saw so
    tests can prove sequencing and skip behavior.
    """

    prompt_tokens: int = 600
    completion_tokens: int = 240
    seen: list[tuple[str, str]] = field(default_factory=list)

    def judge(self, record: dict[str, Any]) -> JudgeProviderReply:
        self.seen.append((str(record.get("place_id")), str(record.get("language"))))
        payload = {
            "decision": DECISION_PASS,
            "dimensions": [
                {
                    "dimension": dimension,
                    "status": DIMENSION_STATUS_PASS,
                    "reason": "fake_ok",
                    "confidence": 1.0,
                }
                for dimension in JUDGE_DIMENSIONS
            ],
        }
        return JudgeProviderReply(
            text=json.dumps(payload),
            prompt_tokens=self.prompt_tokens,
            completion_tokens=self.completion_tokens,
            total_tokens=self.prompt_tokens + self.completion_tokens,
        )


@dataclass
class LiveJudgeProvider:
    """The production provider. Constructed only via :func:`build_live_provider`."""

    client: Any
    model_id: str

    def judge(self, record: dict[str, Any]) -> JudgeProviderReply:
        system, user = build_judge_prompt(record)
        completion = self.client.chat.completions.create(
            model=self.model_id,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=0.0,
            max_completion_tokens=DOCENT_JUDGE_MAX_COMPLETION_TOKENS,
        )
        text = completion.choices[0].message.content or ""
        usage = getattr(completion, "usage", None)
        prompt_tokens = int(getattr(usage, "prompt_tokens", 0) or 0)
        completion_tokens = int(getattr(usage, "completion_tokens", 0) or 0)
        total_tokens = int(getattr(usage, "total_tokens", 0) or 0)
        if not total_tokens:
            total_tokens = prompt_tokens + completion_tokens
        return JudgeProviderReply(
            text=text,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
        )


def build_live_provider(settings: Any | None = None) -> LiveJudgeProvider:
    """Construct the live judge provider; refuses unless every gate is on.

    Mirrors the established live-AI boundary style: the ``openai`` import and
    client construction happen only here, behind the double gate, with
    ``max_retries=0`` so the provider itself never multiplies spend. No new
    provider, Azure path, raw-key path, or direct-token path.
    """
    settings = settings or get_settings()
    if not judge_live_enabled(settings):
        raise ServiceError(
            status_code=503,
            code="DOCENT_JUDGE_NOT_ENABLED",
            message="Live docent judge is not enabled.",
            retryable=False,
        )
    resolved_model = resolve("docent_qa", settings)
    try:
        from openai import OpenAI
    except Exception as exc:
        raise ServiceError(
            status_code=503,
            code="AI_CLIENT_UNAVAILABLE",
            message="OpenAI client dependency is unavailable.",
            retryable=False,
        ) from exc
    client = OpenAI(
        api_key=settings.openai_api_key,
        base_url=settings.openai_base_url or "https://api.openai.com/v1",
        timeout=DOCENT_JUDGE_TIMEOUT_SECONDS,
        max_retries=0,
    )
    return LiveJudgeProvider(client=client, model_id=resolved_model.model_id)


# --- Bounded batch policy ------------------------------------------------------


@dataclass(frozen=True)
class JudgeBatchPolicy:
    """Pure, provider-free batch bounds for the judge roster.

    ``max_records`` is capped by :data:`HARD_MAX_RECORDS` (80): no configured
    policy may exceed the existing 40-place x KO+EN roster. The stop-loss
    counters trip a halt on ``max_malformed_responses`` malformed replies,
    ``max_provider_failures`` provider failures (timeouts included), or a
    cumulative ``max_total_tokens`` usage ceiling.
    """

    max_records: int = HARD_MAX_RECORDS
    canary_size: int = 4
    max_concurrency: int = 4
    per_record_timeout_seconds: float = DOCENT_JUDGE_TIMEOUT_SECONDS
    max_malformed_responses: int = 2
    max_provider_failures: int = 3
    max_total_tokens: int = 300_000

    def validate(self) -> None:
        """Validate every bound; raise ValueError before any provider call."""
        int_fields: tuple[tuple[str, int], ...] = (
            ("max_records", self.max_records),
            ("canary_size", self.canary_size),
            ("max_concurrency", self.max_concurrency),
            ("max_malformed_responses", self.max_malformed_responses),
            ("max_provider_failures", self.max_provider_failures),
            ("max_total_tokens", self.max_total_tokens),
        )
        for name, value in int_fields:
            if isinstance(value, bool) or not isinstance(value, int) or value < 1:
                raise ValueError(f"JudgeBatchPolicy.{name} must be a positive integer")
        if self.max_records > HARD_MAX_RECORDS:
            raise ValueError(
                f"JudgeBatchPolicy.max_records may not exceed the hard roster cap {HARD_MAX_RECORDS}"
            )
        if self.canary_size >= self.max_records:
            raise ValueError("JudgeBatchPolicy.canary_size must be smaller than max_records")
        if self.max_concurrency > 16:
            raise ValueError("JudgeBatchPolicy.max_concurrency may not exceed 16")
        timeout = self.per_record_timeout_seconds
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
            raise ValueError("JudgeBatchPolicy.per_record_timeout_seconds must be a number")
        if not math.isfinite(float(timeout)) or not 0.0 < float(timeout) <= 60.0:
            raise ValueError("JudgeBatchPolicy.per_record_timeout_seconds must be in (0, 60]")

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "max_records": self.max_records,
            "canary_size": self.canary_size,
            "max_concurrency": self.max_concurrency,
            "per_record_timeout_seconds": self.per_record_timeout_seconds,
            "max_malformed_responses": self.max_malformed_responses,
            "max_provider_failures": self.max_provider_failures,
            "max_total_tokens": self.max_total_tokens,
        }

    def plan(self, records: Sequence[dict[str, Any]]) -> JudgeBatchPlan:
        """Cap the roster to ``max_records`` and split canary / remainder."""
        self.validate()
        capped = list(records[: self.max_records])
        dropped_by_cap = len(records) - len(capped)
        canary = capped[: self.canary_size]
        remainder = capped[self.canary_size :]
        return JudgeBatchPlan(
            canary=tuple(canary),
            remainder=tuple(remainder),
            dropped_by_cap=dropped_by_cap,
        )


@dataclass(frozen=True)
class JudgeBatchPlan:
    canary: tuple[dict[str, Any], ...]
    remainder: tuple[dict[str, Any], ...]
    dropped_by_cap: int


@dataclass(frozen=True)
class JudgeRecordOutcome:
    """The only per-record judge data that may be persisted (sanitized)."""

    place_id: str
    language: str
    decision: str | None
    failure_reason: str | None
    error_code: str | None
    dimensions: tuple[JudgeDimensionResult, ...]
    script_excerpt: str

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "place_id": self.place_id,
            "language": self.language,
            "decision": self.decision,
            "failure_reason": self.failure_reason,
            "error_code": self.error_code,
            "dimensions": [
                {
                    "dimension": dimension.dimension,
                    "status": dimension.status,
                    # Reason codes are persisted redacted + bounded: a model
                    # echoing secrets into a reason can never leak them.
                    "reason": sanitize_text(dimension.reason, limit=MAX_REASON_CHARS),
                }
                for dimension in self.dimensions
            ],
            "script_excerpt": self.script_excerpt,
        }


ERROR_SKIPPED_NO_SCRIPT = "skipped_no_script"
ERROR_SKIPPED_BATCH_HALTED = "skipped_batch_halted"
ERROR_PROVIDER_FAILURE = "provider_failure"
ERROR_PROVIDER_TIMEOUT = "provider_timeout"

HALT_MALFORMED = "malformed_response_stop_loss"
HALT_PROVIDER_FAILURES = "provider_failure_stop_loss"
HALT_USAGE = "usage_stop_loss"


@dataclass
class JudgeBatchRun:
    """One bounded judge batch execution and its aggregate accounting."""

    policy: JudgeBatchPolicy
    outcomes: list[JudgeRecordOutcome] = field(default_factory=list)
    counters: dict[str, int] = field(default_factory=dict)
    halted: bool = False
    halt_reason: str | None = None
    total_tokens: int = 0

    def gate_status(self) -> str:
        """Overall judge-gate status; ``NOT_RUN`` is reported by the caller
        when no judge ran at all, and can never be produced here as a pass."""
        if any(outcome.decision == DECISION_REWRITE for outcome in self.outcomes):
            return DECISION_REWRITE
        if self.halted:
            return "HALTED"
        if any(outcome.decision == DECISION_PASS for outcome in self.outcomes):
            return DECISION_PASS
        return "NO_VERDICTS"

    def summarize(self) -> dict[str, Any]:
        """Stable, secret-free aggregate for the offline QA report."""
        per_dimension: dict[str, dict[str, int]] = {
            dimension: {DIMENSION_STATUS_PASS: 0, DIMENSION_STATUS_FLAGGED: 0}
            for dimension in JUDGE_DIMENSIONS
        }
        for outcome in self.outcomes:
            for dimension in outcome.dimensions:
                per_dimension[dimension.dimension][dimension.status] += 1
        return {
            "status": self.gate_status(),
            "counters": dict(sorted(self.counters.items())),
            "per_dimension": {
                dimension: dict(sorted(counts.items()))
                for dimension, counts in per_dimension.items()
            },
            "total_tokens": self.total_tokens,
            "halted": self.halted,
            "halt_reason": self.halt_reason,
            "policy": self.policy.to_public_dict(),
            "outcomes": [outcome.to_public_dict() for outcome in self.outcomes],
        }


def run_judge_batch(
    records: Sequence[dict[str, Any]],
    *,
    provider: JudgeProvider,
    policy: JudgeBatchPolicy | None = None,
) -> JudgeBatchRun:
    """Run one bounded judge batch with an injected provider.

    The canary phase runs sequentially first; the remainder runs in bounded-
    concurrency waves. Each record gets exactly one provider call (no retries).
    The batch halts on malformed responses, repeated provider failures
    (timeouts included), or the cumulative token ceiling; every unjudged
    remainder record is explicitly skipped, never silently passed.
    """
    policy = policy or JudgeBatchPolicy()
    policy.validate()
    plan = policy.plan(records)
    run = JudgeBatchRun(policy=policy)
    run.counters = {
        "submitted": len(records),
        "judged": 0,
        "pass_decisions": 0,
        "rewrite_decisions": 0,
        "malformed_responses": 0,
        "provider_failures": 0,
        "provider_timeouts": 0,
        "skipped_no_script": 0,
        "skipped_batch_halted": 0,
        "dropped_by_cap": plan.dropped_by_cap,
        "canary_records": len(plan.canary),
        "remainder_records": len(plan.remainder),
    }

    def stop_loss_reason() -> str | None:
        if run.counters["malformed_responses"] >= policy.max_malformed_responses:
            return HALT_MALFORMED
        if (
            run.counters["provider_failures"] + run.counters["provider_timeouts"]
            >= policy.max_provider_failures
        ):
            return HALT_PROVIDER_FAILURES
        if run.total_tokens >= policy.max_total_tokens:
            return HALT_USAGE
        return None

    def judge_one(record: dict[str, Any], future: Future[JudgeProviderReply]) -> None:
        script = str(record.get("script") or "").strip()
        if not script:
            # Honest-empty record: nothing to judge. Skipped, never a pass.
            run.counters["skipped_no_script"] += 1
            run.outcomes.append(
                JudgeRecordOutcome(
                    place_id=str(record.get("place_id")),
                    language=str(record.get("language")),
                    decision=None,
                    failure_reason=None,
                    error_code=ERROR_SKIPPED_NO_SCRIPT,
                    dimensions=(),
                    script_excerpt="",
                )
            )
            return
        try:
            reply = future.result(timeout=policy.per_record_timeout_seconds)
        except TimeoutError:
            run.counters["provider_timeouts"] += 1
            run.outcomes.append(_error_outcome(record, ERROR_PROVIDER_TIMEOUT))
            return
        except Exception:
            # Exactly one call per record; failures are counted, never retried.
            run.counters["provider_failures"] += 1
            run.outcomes.append(_error_outcome(record, ERROR_PROVIDER_FAILURE))
            return
        run.total_tokens += int(reply.total_tokens or 0)
        result = parse_judge_response(reply.text)
        if result.is_fail_closed:
            run.counters["malformed_responses"] += 1
        run.counters["judged"] += 1
        if result.decision == DECISION_PASS:
            run.counters["pass_decisions"] += 1
        else:
            run.counters["rewrite_decisions"] += 1
        run.outcomes.append(
            JudgeRecordOutcome(
                place_id=str(record.get("place_id")),
                language=str(record.get("language")),
                decision=result.decision,
                failure_reason=result.failure_reason,
                error_code=None,
                dimensions=result.dimensions,
                script_excerpt=script_excerpt(script),
            )
        )

    # Explicit shutdown: a per-record timeout abandons the wait (accounted as a
    # failure) without blocking the batch on a hung call; cancelling queued
    # futures on halt stops unstarted paid calls. At most max_concurrency
    # already-running calls linger, each bounded by the provider's own timeout.
    executor = ThreadPoolExecutor(max_workers=policy.max_concurrency)
    try:
        # Canary: sequential, smallest blast radius before the remainder.
        for index, record in enumerate(plan.canary):
            if (reason := stop_loss_reason()) is not None:
                pending = [*plan.canary[index:], *plan.remainder]
                _mark_halted(run, pending, reason)
                return run
            judge_one(record, executor.submit(provider.judge, record))
        if (reason := stop_loss_reason()) is not None:
            _mark_halted(run, plan.remainder, reason)
            return run
        # Remainder: bounded-concurrency waves; stop-loss checked between waves.
        waves = [
            plan.remainder[index : index + policy.max_concurrency]
            for index in range(0, len(plan.remainder), policy.max_concurrency)
        ]
        for wave in waves:
            futures = [(record, executor.submit(provider.judge, record)) for record in wave]
            for record, future in futures:
                judge_one(record, future)
            if (reason := stop_loss_reason()) is not None:
                pending = [record for record in plan.remainder if not _has_outcome(run, record)]
                _mark_halted(run, pending, reason)
                return run
    finally:
        executor.shutdown(wait=False, cancel_futures=True)
    return run


def _has_outcome(run: JudgeBatchRun, record: dict[str, Any]) -> bool:
    key = (str(record.get("place_id")), str(record.get("language")))
    return any((outcome.place_id, outcome.language) == key for outcome in run.outcomes)


def _error_outcome(record: dict[str, Any], error_code: str) -> JudgeRecordOutcome:
    return JudgeRecordOutcome(
        place_id=str(record.get("place_id")),
        language=str(record.get("language")),
        decision=None,
        failure_reason=None,
        error_code=error_code,
        dimensions=(),
        script_excerpt="",
    )


def _mark_halted(run: JudgeBatchRun, pending: Sequence[dict[str, Any]], reason: str) -> None:
    run.halted = True
    run.halt_reason = reason
    for record in pending:
        run.counters["skipped_batch_halted"] += 1
        run.outcomes.append(_error_outcome(record, ERROR_SKIPPED_BATCH_HALTED))


def judge_gate_section(run: JudgeBatchRun | None) -> dict[str, Any]:
    """Build the separate optional judge-gate section for the offline report.

    When no judge ran the section is exactly ``{"status": "NOT_RUN"}`` — never
    a PASS — and never modifies the deterministic P6A results.
    """
    if run is None:
        return {"status": "NOT_RUN"}
    return run.summarize()
