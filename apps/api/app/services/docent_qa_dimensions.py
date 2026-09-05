"""Deterministic docent QA dimension audits (P6A).

Audits evidence already present in a QA record — script text, source label,
grounding metadata, and the deterministic precheck's ``issue_tags`` — and
reports one verdict per dimension: ``pass``, ``flagged``, or
``not_applicable``.

Honesty rules (binding):

- A dimension without enough evidence is reported ``not_applicable`` (with a
  stable reason code), never silently counted as a pass.
- Records without a script (honest-empty / generation-error / transport-error
  rows) are ``not_applicable`` for every dimension.
- Every check is deterministic, offline, and linear-bounded. No model judge is
  involved here; the ``docent_qa`` model judge stays a separate external gate.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import asdict, dataclass
from typing import Any

from apps.api.app.services.docent_quality_qa import (
    RAW_SCORE_RE,
    SCRIPT_SOURCE_BLOCKLIST,
    SECRET_LIKE_RE,
)

DIMENSION_ORDER = (
    "grounding",
    "source_attribution",
    "local_context",
    "language_purity_ko_en",
    "usefulness",
    "safety",
    "repetition",
    "advertising_leakage",
    "hallucination",
)
STATUS_PASS = "pass"
STATUS_FLAGGED = "flagged"
STATUS_NOT_APPLICABLE = "not_applicable"

# --- Language purity (mirrors docent_quality_qa thresholds, evidence-gated) ----
_HANGUL_RE = re.compile(r"[가-힣]")
_LONG_ASCII_WORD_RE = re.compile(r"\b(?!PM10\b|PM2\.5\b|AI\b)[A-Za-z]{6,}\b")
_KO_ASCII_ALLOWLIST = {"airkorea", "kakao", "tourapi", "kcisa", "kopis"}

# --- Local context / usefulness token evidence --------------------------------
_KO_LOCAL_CONTEXT_TOKENS = ("지역", "동네", "상권", "소상공", "로컬", "골목", "분산", "주변")
_EN_LOCAL_CONTEXT_TOKENS = (
    "local",
    "neighborhood",
    "nearby",
    "community",
    "small business",
)
_KO_ROUTE_TOKENS = (
    "동선",
    "코스",
    "이동",
    "산책",
    "들러",
    "가기 전",
    "나온 뒤",
    "근처",
    "방문 전후",
)
_EN_ROUTE_RE = re.compile(r"\b(?:route|walk|course|before|after|nearby|stop by)\b", re.IGNORECASE)

# --- Repetition (deterministic, bounded, particle-safe) -----------------------
# Sentence-level: exact normalized duplicates. Sentences shorter than
# MIN_SENTENCE_CHARS (compact, spaces stripped) are common interjections /
# particles (네. / 예. / 좋아요. / Yes. / OK.) and never count as repetition.
_SENTENCE_SPLIT_RE = re.compile(r"[.!?。]+")
MIN_SENTENCE_CHARS = 10
# Phrase-level: a whitespace-token window (어절 for KO) repeated verbatim.
# The compact-length floor keeps short/common particle sequences out.
PHRASE_TOKEN_COUNT = 4
MIN_PHRASE_CHARS = 12
# Deterministic bounded scan: scripts longer than this are truncated for the
# repetition audit only, so cost stays linear with a stable result.
MAX_REPETITION_SCAN_CHARS = 20_000


@dataclass(frozen=True)
class DimensionAudit:
    """One dimension verdict for one QA record."""

    dimension: str
    status: str
    reason: str

    def to_public_dict(self) -> dict[str, str]:
        return asdict(self)


def _record_script(record: dict[str, Any]) -> str:
    return str(record.get("script") or "").strip()


def _issue_tags(record: dict[str, Any]) -> set[str]:
    tags = (record.get("auto_precheck") or {}).get("issue_tags") or []
    return {str(tag) for tag in tags}


def _na(dimension: str, reason: str = "no_script_evidence") -> DimensionAudit:
    return DimensionAudit(dimension, STATUS_NOT_APPLICABLE, reason)


def _scorable_sentences(script: str) -> list[str]:
    sentences = [part.strip() for part in _SENTENCE_SPLIT_RE.split(script) if part.strip()]
    return [s for s in sentences if len("".join(s.split())) >= MIN_SENTENCE_CHARS]


def repetition_reasons(script: str) -> list[str]:
    """Deterministic, bounded repeated sentence/phrase findings (reason codes only).

    Returns ``["repeated_sentence", ...]`` / ``["repeated_phrase", ...]``; an
    empty list means no repetition found. Short/common particles are excluded
    by the compact-length floors so they can never trigger a false positive.
    """
    text = script.strip()[:MAX_REPETITION_SCAN_CHARS]
    reasons: list[str] = []
    scorable = _scorable_sentences(text)
    sentence_counts = Counter(" ".join(s.split()).casefold() for s in scorable)
    if any(count >= 2 for count in sentence_counts.values()):
        reasons.append("repeated_sentence")
    tokens = text.split()
    phrase_counts: Counter[str] = Counter()
    for index in range(len(tokens) - PHRASE_TOKEN_COUNT + 1):
        phrase = " ".join(tokens[index : index + PHRASE_TOKEN_COUNT])
        if len("".join(phrase.split())) >= MIN_PHRASE_CHARS:
            phrase_counts[phrase.casefold()] += 1
    if any(count >= 2 for count in phrase_counts.values()):
        reasons.append("repeated_phrase")
    return reasons


def audit_source_attribution(record: dict[str, Any]) -> DimensionAudit:
    dimension = "source_attribution"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    source = str(record.get("source") or record.get("script_source_method") or "").strip()
    if not source:
        return DimensionAudit(dimension, STATUS_FLAGGED, "missing_source_label")
    if SCRIPT_SOURCE_BLOCKLIST.search(source):
        return DimensionAudit(dimension, STATUS_FLAGGED, "blocked_source_label")
    return DimensionAudit(dimension, STATUS_PASS, "source_label_present")


def audit_local_context(record: dict[str, Any]) -> DimensionAudit:
    dimension = "local_context"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    lowered = script.lower()
    mentioned = any(token in script for token in _KO_LOCAL_CONTEXT_TOKENS) or any(
        token in lowered for token in _EN_LOCAL_CONTEXT_TOKENS
    )
    if not mentioned:
        return DimensionAudit(dimension, STATUS_FLAGGED, "no_local_context")
    return DimensionAudit(dimension, STATUS_PASS, "local_context_present")


def audit_language_purity(record: dict[str, Any]) -> DimensionAudit:
    dimension = "language_purity_ko_en"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    language = str(record.get("language") or "").strip().lower()
    if language not in {"ko", "en"}:
        return _na(dimension, "unsupported_language")
    if language == "en":
        if _HANGUL_RE.search(script):
            return DimensionAudit(dimension, STATUS_FLAGGED, "hangul_in_english")
    else:
        latin_words = [
            word.lower()
            for word in _LONG_ASCII_WORD_RE.findall(script)
            if word.lower() not in _KO_ASCII_ALLOWLIST
        ]
        if len(latin_words) >= 3:
            return DimensionAudit(dimension, STATUS_FLAGGED, "latin_words_in_korean")
    return DimensionAudit(dimension, STATUS_PASS, "single_language_script")


def audit_usefulness(record: dict[str, Any]) -> DimensionAudit:
    dimension = "usefulness"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    tags = _issue_tags(record)
    flagged_tags = sorted(tags & {"route_action_missing", "category_persona_weak"})
    if flagged_tags:
        return DimensionAudit(dimension, STATUS_FLAGGED, flagged_tags[0])
    language = str(record.get("language") or "").strip().lower()
    has_route = (
        bool(_EN_ROUTE_RE.search(script))
        if language == "en"
        else any(token in script for token in _KO_ROUTE_TOKENS)
    )
    if not has_route:
        return DimensionAudit(dimension, STATUS_FLAGGED, "route_action_missing")
    return DimensionAudit(dimension, STATUS_PASS, "route_action_present")


def audit_safety(record: dict[str, Any]) -> DimensionAudit:
    dimension = "safety"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    if SECRET_LIKE_RE.search(script) or "secret_like_text" in _issue_tags(record):
        return DimensionAudit(dimension, STATUS_FLAGGED, "secret_like_text")
    return DimensionAudit(dimension, STATUS_PASS, "no_secret_like_text")


def audit_repetition(record: dict[str, Any]) -> DimensionAudit:
    dimension = "repetition"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    text = script[:MAX_REPETITION_SCAN_CHARS]
    reasons = repetition_reasons(text)
    if reasons:
        return DimensionAudit(dimension, STATUS_FLAGGED, ",".join(reasons))
    if len(_scorable_sentences(text)) < 2:
        return _na(dimension, "insufficient_sentence_evidence")
    return DimensionAudit(dimension, STATUS_PASS, "no_repeated_sentences")


def audit_advertising_leakage(record: dict[str, Any]) -> DimensionAudit:
    dimension = "advertising_leakage"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    if SCRIPT_SOURCE_BLOCKLIST.search(script) or "fallback_or_mock_wording" in _issue_tags(record):
        return DimensionAudit(dimension, STATUS_FLAGGED, "mock_or_fallback_wording")
    return DimensionAudit(dimension, STATUS_PASS, "no_mock_wording")


def audit_hallucination(record: dict[str, Any]) -> DimensionAudit:
    dimension = "hallucination"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    if RAW_SCORE_RE.search(script) or "raw_score_leakage" in _issue_tags(record):
        return DimensionAudit(dimension, STATUS_FLAGGED, "raw_score_leakage")
    return DimensionAudit(dimension, STATUS_PASS, "no_raw_score_leakage")


def audit_grounding(record: dict[str, Any]) -> DimensionAudit:
    dimension = "grounding"
    script = _record_script(record)
    if not script:
        return _na(dimension)
    tags = _issue_tags(record)
    flagged_tags = sorted(tags & {"no_rag_chunks", "missing_place_name"})
    if flagged_tags:
        return DimensionAudit(dimension, STATUS_FLAGGED, flagged_tags[0])
    grounding_count = record.get("grounding_count")
    if grounding_count is not None:
        try:
            if int(grounding_count) <= 0:
                return DimensionAudit(dimension, STATUS_FLAGGED, "no_grounding_metadata")
        except (TypeError, ValueError):
            return DimensionAudit(dimension, STATUS_FLAGGED, "invalid_grounding_metadata")
    return DimensionAudit(dimension, STATUS_PASS, "grounding_metadata_present")


_AUDITORS = {
    "grounding": audit_grounding,
    "source_attribution": audit_source_attribution,
    "local_context": audit_local_context,
    "language_purity_ko_en": audit_language_purity,
    "usefulness": audit_usefulness,
    "safety": audit_safety,
    "repetition": audit_repetition,
    "advertising_leakage": audit_advertising_leakage,
    "hallucination": audit_hallucination,
}


def audit_record_dimensions(record: dict[str, Any]) -> dict[str, DimensionAudit]:
    """Audit every dimension for one QA record using its in-record evidence."""
    return {dimension: auditor(record) for dimension, auditor in _AUDITORS.items()}


def summarize_dimension_audits(records: list[dict[str, Any]]) -> dict[str, dict[str, int]]:
    """Aggregate per-dimension pass/flagged/not_applicable counts.

    All three counters are always present for every dimension so a missing
    evidence pool is visible as ``not_applicable`` — never as a silent pass.
    """
    summary: dict[str, dict[str, int]] = {
        dimension: {STATUS_PASS: 0, STATUS_FLAGGED: 0, STATUS_NOT_APPLICABLE: 0}
        for dimension in DIMENSION_ORDER
    }
    for record in records:
        for dimension, audit in audit_record_dimensions(record).items():
            summary[dimension][audit.status] += 1
    return summary
