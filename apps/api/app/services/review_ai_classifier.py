"""Provider-neutral, offline-testable AI classifier contract for P3-M3.

This module implements the second-stage AI ad/relevance classifier described in
the P3 review plan. It provides a strict contract with bounded types, fail-closed
JSON parsing, and comprehensive offline test coverage.

Key contract requirements:
- Deterministic first-pass filters (existing classify_post()) are a prerequisite
- Strict bounded JSON parsing with fail-closed behavior for malformed results
- Standard OpenAI bulk resolver (gpt-5.4-nano) via existing model-role/config helpers
- Immutable classification results with bounded fields
- Safe generic exceptions that don't expose input data, secrets, or provider errors
- Pure function for applying AI classification without overriding deterministic rejections
- Low confidence → recheck_required with retained=False
- Category policy preservation (restaurants retain food terms, attractions reject food-only)
- Versioned prompt builder that's secret-free and doesn't return raw text
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from apps.api.app.services.model_client import resolve
from apps.api.app.services.review_mention_ingest import ReviewMentionDecision

PROMPT_VERSION = "review-ai-classifier-v1"
SCHEMA_VERSION = "review-ai-classifier-v1"
DECISION_FIELDS = frozenset(
    {
        "schema_version",
        "decision",
        "is_ad",
        "is_relevant",
        "ad_confidence",
        "relevance_confidence",
        "reason_code",
    }
)
ALLOWED_DECISIONS = frozenset({"organic", "ad_filtered", "irrelevant", "uncertain"})
ALLOWED_REASON_CODES = frozenset(
    {
        "organic_mention",
        "advertising_detected",
        "sponsored_content",
        "insufficient_place_evidence",
        "off_topic_content",
        "low_confidence",
        "ambiguous_signal",
    }
)
CONFIDENCE_THRESHOLD = 0.7
RECHECK_THRESHOLD = 0.5


class AIClassifierError(Exception):
    """Base exception for AI classifier errors.

    This exception type and its messages are designed to be safe for logging
    and operator display without exposing input content, secrets, or provider
    error details.
    """

    pass


class AIClassifierValidationError(AIClassifierError):
    """Raised when AI response validation fails."""

    pass


class AIClassifierConfigurationError(AIClassifierError):
    """Raised when required configuration is missing."""

    pass


@dataclass(frozen=True)
class AIClassificationResult:
    """Immutable AI classification result with bounded fields.

    All fields are strictly typed and bounded. No raw text or free-form
    content from the AI response is included in the persisted result.
    """

    schema_version: str
    decision: str
    is_ad: bool
    is_relevant: bool
    ad_confidence: float
    relevance_confidence: float
    reason_code: str

    def to_public_dict(self) -> dict[str, Any]:
        """Return a safe public representation without sensitive data."""
        return {
            "schema_version": self.schema_version,
            "decision": self.decision,
            "is_ad": self.is_ad,
            "is_relevant": self.is_relevant,
            "ad_confidence": self.ad_confidence,
            "relevance_confidence": self.relevance_confidence,
            "reason_code": self.reason_code,
        }

    def to_attributes_payload(self) -> dict[str, Any]:
        """Return the payload for persistence in DB attributes."""
        return self.to_public_dict()


@dataclass(frozen=True)
class AIClassifierPrompt:
    """Versioned prompt builder for AI classification.

    This builder is secret-free and never returns raw prompt text for logging
    or display. It only builds structured input for the AI model.
    """

    version: str = PROMPT_VERSION

    def build_classification_input(
        self,
        decisions: Sequence[ReviewMentionDecision],
    ) -> dict[str, Any]:
        """Build structured input for AI classification.

        The returned dict contains only the structured fields needed for
        classification, not the full prompt text.
        """
        return {
            "schema_version": self.version,
            "decisions": [
                {
                    "external_key": decision.post.external_key,
                    "provider": decision.post.provider,
                    "normalized_text": decision.normalized_text[:280],  # Truncated for safety
                    "place_id": decision.place.place_id if decision.place else None,
                    "place_name_ko": decision.place.name_ko if decision.place else None,
                    "category": decision.place.category if decision.place else None,
                    "deterministic_is_ad": decision.is_ad,
                    "deterministic_is_relevant": decision.is_relevant,
                    "deterministic_reason": decision.reason,
                    "match_confidence": decision.match_confidence,
                    "category_policy": decision.category_policy,
                }
                for decision in decisions
            ],
        }


def resolve_bulk_model() -> str:
    """Resolve the standard OpenAI bulk model for AI classification.

    Uses the existing model-role resolution infrastructure to get the
    appropriate model ID for the review_bulk lane (gpt-5.4-nano).

    Returns:
        The model ID string for the bulk classifier.

    Raises:
        AIClassifierConfigurationError: If model resolution fails.
    """
    try:
        return resolve("review_bulk").model_id
    except Exception as exc:
        raise AIClassifierConfigurationError(
            "Failed to resolve review_bulk model for AI classification"
        ) from exc


def build_system_prompt() -> str:
    """Build the system prompt for AI classification.

    The prompt is designed to be secret-free and focused on the classification
    task without exposing implementation details or sensitive data.
    """
    return """\
You are a strict review classifier for LALA, a Korean travel app.

Classify each review decision as JSON with EXACTLY these fields:
{
  "decision": "organic|ad_filtered|irrelevant|uncertain",
  "is_ad": boolean,
  "is_relevant": boolean,
  "ad_confidence": 0.0-1.0,
  "relevance_confidence": 0.0-1.0,
  "reason_code": "organic_mention|advertising_detected|sponsored_content|insufficient_place_evidence|off_topic_content|low_confidence|ambiguous_signal"
}

Rules:
1. Return ONLY the JSON object, no markdown fences or extra text.
2. Use the provided deterministic classification as a baseline signal.
3. Mark as ad_filtered only with strong advertising evidence (sponsor markers, excessive price/coupon language).
4. Mark as irrelevant only when content clearly doesn't describe place experience.
5. Preserve category policy: restaurant food terms are valid, attraction food-only reviews are not.
6. When uncertain, set confidence < 0.6 and decision=uncertain.
7. Never return raw text, excerpts, or free-form reasons in the result.
"""


def parse_ai_response(
    raw_response: str,
    expected_count: int,
) -> list[AIClassificationResult]:
    """Parse AI response with strict bounded validation.

    This function implements fail-closed behavior: any deviation from the
    expected schema results in an AIClassifierValidationError, not silent
    acceptance or partial parsing.

    Args:
        raw_response: The raw text response from the AI model.
        expected_count: The exact number of results expected.

    Returns:
        A list of validated AIClassificationResult objects.

    Raises:
        AIClassifierValidationError: If response structure is invalid.
    """
    # Strip potential markdown fences
    cleaned = raw_response.strip()
    if cleaned.startswith("```"):
        lines = cleaned.splitlines()
        if len(lines) >= 2 and lines[-1].strip() == "```":
            cleaned = "\n".join(lines[1:-1]).strip()
        cleaned = cleaned.lstrip("json").strip()

    # Parse JSON with strict validation
    try:
        payload = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise AIClassifierValidationError("AI response was not valid JSON") from exc

    if not isinstance(payload, dict):
        raise AIClassifierValidationError("AI response root must be a JSON object")

    results = payload.get("results")
    if not isinstance(results, list):
        raise AIClassifierValidationError("AI response must contain a 'results' list")

    if len(results) != expected_count:
        raise AIClassifierValidationError(
            f"AI response contained {len(results)} results, expected {expected_count}"
        )

    parsed_results: list[AIClassificationResult] = []
    seen_indices = set()

    for idx, item in enumerate(results):
        if not isinstance(item, dict):
            raise AIClassifierValidationError(f"Result {idx} is not a JSON object")

        # Check for required fields and no extra fields
        fields = set(item.keys())
        if fields != DECISION_FIELDS:
            raise AIClassifierValidationError(
                f"Result {idx} has invalid fields: {fields - DECISION_FIELDS}"
            )

        # Validate and extract each field with strict bounds
        decision = _validate_decision(item.get("decision"), idx)
        is_ad = _validate_bool(item.get("is_ad"), "is_ad", idx)
        is_relevant = _validate_bool(item.get("is_relevant"), "is_relevant", idx)
        ad_confidence = _validate_confidence(item.get("ad_confidence"), "ad_confidence", idx)
        relevance_confidence = _validate_confidence(
            item.get("relevance_confidence"), "relevance_confidence", idx
        )
        reason_code = _validate_reason_code(item.get("reason_code"), idx)

        parsed_results.append(
            AIClassificationResult(
                schema_version=SCHEMA_VERSION,
                decision=decision,
                is_ad=is_ad,
                is_relevant=is_relevant,
                ad_confidence=ad_confidence,
                relevance_confidence=relevance_confidence,
                reason_code=reason_code,
            )
        )
        seen_indices.add(idx)

    if len(seen_indices) != expected_count:
        raise AIClassifierValidationError("Duplicate or missing result indices detected")

    return parsed_results


def apply_ai_classification(
    decision: ReviewMentionDecision,
    ai_result: AIClassificationResult,
) -> ReviewMentionDecision:
    """Apply AI classification to a deterministic decision.

    This is a pure function that creates a new decision with AI classification
    applied. It NEVER overrides deterministic rejections:
    - If the deterministic filter already rejected (retained=False), it stays rejected
    - If the deterministic filter marked as ad, it stays ad (AI can only confirm)
    - Category policy is always preserved

    Low confidence results get recheck_required status with retained=False.

    Args:
        decision: The original deterministic classification result.
        ai_result: The AI classification result to apply.

    Returns:
        A new ReviewMentionDecision with AI classification applied.
    """
    # Never override deterministic rejections
    if not decision.retained:
        return decision

    # Never override deterministic ad detection
    if decision.is_ad and not ai_result.is_ad:
        return decision

    # High confidence ad detection: filter it
    if ai_result.is_ad and ai_result.ad_confidence >= CONFIDENCE_THRESHOLD:
        return _create_modified_decision(
            decision,
            retained=False,
            is_ad=True,
            reason="advertising_filtered",
        )

    # High confidence irrelevant content: filter it
    if not ai_result.is_relevant and ai_result.relevance_confidence >= CONFIDENCE_THRESHOLD:
        return _create_modified_decision(
            decision,
            retained=False,
            is_relevant=False,
            reason="ai_classified_irrelevant",
        )

    # Check confidence thresholds for recheck
    if (
        ai_result.ad_confidence < RECHECK_THRESHOLD
        or ai_result.relevance_confidence < RECHECK_THRESHOLD
    ):
        # Low confidence: mark for recheck but don't retain
        return _create_modified_decision(
            decision,
            retained=False,
            reason="recheck_required",
        )

    # Organic, relevant content: keep it
    return _create_modified_decision(
        decision,
        retained=True,
        reason="ai_confirmed_organic",
    )


def _validate_decision(value: Any, idx: int) -> str:
    """Validate decision field."""
    if not isinstance(value, str):
        raise AIClassifierValidationError(f"Result {idx}: decision must be a string")
    decision = value.strip()
    if decision not in ALLOWED_DECISIONS:
        raise AIClassifierValidationError(
            f"Result {idx}: invalid decision '{decision}'. Must be one of {ALLOWED_DECISIONS}"
        )
    return decision


def _validate_bool(value: Any, field_name: str, idx: int) -> bool:
    """Validate boolean field."""
    if not isinstance(value, bool):
        raise AIClassifierValidationError(
            f"Result {idx}: {field_name} must be a boolean, got {type(value).__name__}"
        )
    return value


def _validate_confidence(value: Any, field_name: str, idx: int) -> float:
    """Validate confidence field is a float between 0 and 1."""
    if isinstance(value, bool):
        raise AIClassifierValidationError(
            f"Result {idx}: {field_name} must be a number, not boolean"
        )
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise AIClassifierValidationError(f"Result {idx}: {field_name} must be a number") from exc

    if not 0.0 <= parsed <= 1.0:
        raise AIClassifierValidationError(
            f"Result {idx}: {field_name} must be between 0.0 and 1.0, got {parsed}"
        )
    return round(parsed, 4)


def _validate_reason_code(value: Any, idx: int) -> str:
    """Validate reason_code field."""
    if not isinstance(value, str):
        raise AIClassifierValidationError(f"Result {idx}: reason_code must be a string")
    code = value.strip()
    if code not in ALLOWED_REASON_CODES:
        raise AIClassifierValidationError(
            f"Result {idx}: invalid reason_code '{code}'. Must be one of {ALLOWED_REASON_CODES}"
        )
    return code


def _create_modified_decision(
    original: ReviewMentionDecision,
    **changes: Any,
) -> ReviewMentionDecision:
    """Create a modified decision while preserving immutability."""
    # Extract all values from the original frozen dataclass
    values = {
        "post": original.post,
        "place": original.place,
        "normalized_text": original.normalized_text,
        "content_sha256": original.content_sha256,
        "is_ad": original.is_ad,
        "is_relevant": original.is_relevant,
        "retained": original.retained,
        "reason": original.reason,
        "match_confidence": original.match_confidence,
        "match_method": original.match_method,
        "category_policy": original.category_policy,
        "week_start": original.week_start,
        "top_terms": original.top_terms,
    }
    # Apply the changes
    values.update(changes)
    return ReviewMentionDecision(**values)


# Offline test helpers (used only in tests, never in production)


@dataclass(frozen=True)
class MockAIResponse:
    """Mock AI response for offline testing."""

    raw: str

    @classmethod
    def organic(cls, confidence: float = 0.9) -> MockAIResponse:
        return cls(
            json.dumps(
                {
                    "results": [
                        {
                            "schema_version": SCHEMA_VERSION,
                            "decision": "organic",
                            "is_ad": False,
                            "is_relevant": True,
                            "ad_confidence": confidence,
                            "relevance_confidence": confidence,
                            "reason_code": "organic_mention",
                        }
                    ]
                }
            )
        )

    @classmethod
    def ad_filtered(cls, confidence: float = 0.9) -> MockAIResponse:
        return cls(
            json.dumps(
                {
                    "results": [
                        {
                            "schema_version": SCHEMA_VERSION,
                            "decision": "ad_filtered",
                            "is_ad": True,
                            "is_relevant": False,
                            "ad_confidence": confidence,
                            "relevance_confidence": 0.3,
                            "reason_code": "advertising_detected",
                        }
                    ]
                }
            )
        )

    @classmethod
    def uncertain(cls, confidence: float = 0.4) -> MockAIResponse:
        return cls(
            json.dumps(
                {
                    "results": [
                        {
                            "schema_version": SCHEMA_VERSION,
                            "decision": "uncertain",
                            "is_ad": False,
                            "is_relevant": True,
                            "ad_confidence": confidence,
                            "relevance_confidence": confidence,
                            "reason_code": "low_confidence",
                        }
                    ]
                }
            )
        )

    @classmethod
    def malformed(cls) -> MockAIResponse:
        return cls("not valid json")

    @classmethod
    def missing_fields(cls) -> MockAIResponse:
        return cls(
            json.dumps(
                {
                    "results": [
                        {
                            "schema_version": SCHEMA_VERSION,
                            "decision": "organic",
                            # Missing other required fields
                        }
                    ]
                }
            )
        )

    @classmethod
    def extra_fields(cls) -> MockAIResponse:
        return cls(
            json.dumps(
                {
                    "results": [
                        {
                            "schema_version": SCHEMA_VERSION,
                            "decision": "organic",
                            "is_ad": False,
                            "is_relevant": True,
                            "ad_confidence": 0.9,
                            "relevance_confidence": 0.9,
                            "reason_code": "organic_mention",
                            "extra_forbidden_field": "should not be here",
                        }
                    ]
                }
            )
        )
