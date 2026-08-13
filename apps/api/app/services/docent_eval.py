"""Offline docent QA evaluation harness (V4-C).

Loads a committed synthetic eval fixture of representative places, exercises the existing
``docent_service.generate_script`` rule-based path with the OpenAI client mocked at the
boundary (no network, no DB, ``LALA_ENABLE_LIVE_AI`` stays off), and returns structured
per-place/per-language results that the CLI harness turns into a pass/fail report.

This module never edits ``docent_service``; it imports it read-only. Fixture places are
synthetic (``eval_`` prefix) — never real product data.
"""

from __future__ import annotations

import json
import os
import re
import sys
import types
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentScriptRequest
from apps.api.app.services import docent_service

CATEGORIES = ("attraction", "restaurant", "event", "culture_venue")
FIXTURE_DEFAULT = (
    Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "docent_eval_places.json"
)

_HANGUL_RE = re.compile(r"[가-힣]")
_LATIN_RE = re.compile(r"[A-Za-z]")
# Internal synthetic IDs (eval_<category>_<nn>) must never leak into a public script.
_INTERNAL_ID_RE = re.compile(r"\beval_[a-z_]+_\d+\b", re.IGNORECASE)
# Placeholder/mock leakage guard (mirrors docent_quality_qa.SCRIPT_SOURCE_BLOCKLIST intent).
_PLACEHOLDER_RE = re.compile(
    r"(?:mock|demo|dummy|placeholder|fallback|sample|목데이터|데모|샘플|임시)", re.IGNORECASE
)

# Defensive boundary-mock state. The live-AI branch is structurally unreachable while
# ``LALA_ENABLE_LIVE_AI`` is off; this counter proves the OpenAI client was never constructed.
_LIVE_CLIENT_STATE = {"constructed": 0}


@dataclass
class LanguageResult:
    """Result of generating one script for one (place, language) pair."""

    language: str
    script: str
    source: str | None
    nonempty: bool
    single_language_ok: bool
    no_internal_id_leak: bool
    no_placeholder: bool
    unavailable: bool = False
    reason: str | None = None


@dataclass
class PlaceResult:
    place_id: str
    category: str
    expect_nonempty: bool
    expect_met: bool
    languages: list[LanguageResult] = field(default_factory=list)


@dataclass
class EvalReport:
    total_places: int
    category_counts: dict[str, int]
    place_results: list[PlaceResult]
    passed: bool
    live_client_constructions: int
    failures: list[str] = field(default_factory=list)
    honest_empty_place_ids: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def load_fixture(path: Path | str | None = None) -> list[dict[str, Any]]:
    """Load the synthetic eval fixture (a JSON array of place objects)."""
    fixture_path = Path(path) if path is not None else FIXTURE_DEFAULT
    with fixture_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError("docent eval fixture must be a JSON array of place objects")
    return data


def build_request(place: dict[str, Any], language: str) -> DocentScriptRequest:
    """Build a ``DocentScriptRequest`` from a fixture place for the given language.

    Honest-empty fixtures omit place_name/region/scores so the docent service surfaces its
    ``DOCENT_CONTEXT_REQUIRED`` unavailable state instead of fabricating a script.
    """
    name = (
        place.get(f"place_name_{language}")
        or place.get("place_name_ko")
        or place.get("place_name_en")
    )
    kwargs: dict[str, Any] = {
        "place_id": place["place_id"],
        "category": place["category"],
        "language": language,
        "mode": "brief",
    }
    if name:
        kwargs["place_name"] = name
    region_ko = place.get("region_ko")
    region_en = place.get("region_en")
    if region_ko:
        kwargs["region_ko"] = region_ko
    if region_en:
        kwargs["region_en"] = region_en
    scores = place.get("scores") or {}
    for key in (
        "final_score",
        "local_spending_score",
        "small_merchant_fit_score",
        "demand_dispersion_score",
        "weather_fit_score",
        "culture_relevance_score",
    ):
        value = scores.get(key)
        if value is not None:
            kwargs[key] = value
    weather = place.get("weather") or {}
    for key in ("weather_temp", "weather_icon", "weather_outdoor_status"):
        value = weather.get(key)
        if value:
            kwargs[key] = value
    return DocentScriptRequest(**kwargs)


def _single_language_ok(script: str, language: str) -> bool:
    """A docent script renders exactly one language: KO must carry Hangul, EN must carry Latin
    and no Hangul (rule-based templates are single-language by construction)."""
    if not script.strip():
        return False
    has_hangul = bool(_HANGUL_RE.search(script))
    has_latin = bool(_LATIN_RE.search(script))
    if language == "ko":
        return has_hangul
    if language == "en":
        return has_latin and not has_hangul
    return True


def _evaluate_language(place: dict[str, Any], language: str) -> LanguageResult:
    request = build_request(place, language)
    try:
        response = docent_service.generate_script(request)
    except ServiceError as exc:
        # Honest-empty / unavailable: the service declines rather than fabricating content.
        return LanguageResult(
            language=language,
            script="",
            source=None,
            nonempty=False,
            single_language_ok=False,
            no_internal_id_leak=True,
            no_placeholder=True,
            unavailable=True,
            reason=exc.code,
        )
    script = str(response.get("script") or "")
    return LanguageResult(
        language=language,
        script=script,
        source=response.get("source"),
        nonempty=bool(script.strip()),
        single_language_ok=_single_language_ok(script, language),
        no_internal_id_leak=not _INTERNAL_ID_RE.search(script),
        no_placeholder=not _PLACEHOLDER_RE.search(script),
        unavailable=False,
        reason=None,
    )


def evaluate_place(place: dict[str, Any]) -> PlaceResult:
    languages = place.get("language_samples") or ["ko", "en"]
    results = [_evaluate_language(place, lang) for lang in languages]
    expect_nonempty = bool(place.get("expect_nonempty", True))
    if expect_nonempty:
        expect_met = bool(results) and all(r.nonempty for r in results)
    else:
        # Honest-empty: every language surfaced empty/unavailable, with no fabricated content.
        expect_met = all((r.unavailable or not r.nonempty) and r.no_placeholder for r in results)
    return PlaceResult(
        place_id=place["place_id"],
        category=place["category"],
        expect_nonempty=expect_nonempty,
        expect_met=expect_met,
        languages=results,
    )


def evaluate_docent(places: list[dict[str, Any]]) -> EvalReport:
    """Run the offline docent eval across the fixture and return a structured report."""
    category_counts: dict[str, int] = {category: 0 for category in CATEGORIES}
    place_results: list[PlaceResult] = []
    honest_empty_ids: list[str] = []
    failures: list[str] = []

    for place in places:
        result = evaluate_place(place)
        place_results.append(result)
        if result.category in category_counts:
            category_counts[result.category] += 1
        if not result.expect_nonempty:
            honest_empty_ids.append(result.place_id)
        if not result.expect_met:
            failures.append(
                f"{result.place_id}: expectation not met (expect_nonempty={result.expect_nonempty})"
            )
        for lang in result.languages:
            lang_id = f"{result.place_id}/{lang.language}"
            if not lang.no_internal_id_leak:
                failures.append(f"{lang_id}: internal eval id leaked into script")
            if not lang.no_placeholder:
                failures.append(f"{lang_id}: placeholder/mock term in script")
            if result.expect_nonempty and not lang.single_language_ok:
                failures.append(f"{lang_id}: single-language check failed")
            # Rule-based path is the intended offline source; an "openai" source here means the
            # live branch executed despite the guard.
            if result.expect_nonempty and lang.source == "openai":
                failures.append(f"{lang_id}: live-AI source used (expected rule_based_curation)")

    missing_categories = [category for category in CATEGORIES if category_counts[category] == 0]
    if missing_categories:
        failures.append(f"category coverage missing: {missing_categories}")
    if not honest_empty_ids:
        failures.append("no honest-empty fixture (expect_nonempty=false) present")

    live_constructions = _LIVE_CLIENT_STATE["constructed"]
    if live_constructions:
        failures.append(
            f"live OpenAI client constructed {live_constructions} time(s) (expected zero)"
        )

    return EvalReport(
        total_places=len(places),
        category_counts=category_counts,
        place_results=place_results,
        passed=not failures,
        live_client_constructions=live_constructions,
        failures=failures,
        honest_empty_place_ids=honest_empty_ids,
    )


class _FakeCompletions:
    """Boundary mock for the live-AI branch. Returns a sentinel so the eval can detect that
    the branch executed, without any network call."""

    SENTINEL = "DOCENT_EVAL_FAKE_LIVE_PATH_SENTINEL"

    def create(self, **_kwargs: Any) -> Any:
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=self.SENTINEL))]
        )


class _FakeOpenAI:
    def __init__(self, **_kwargs: Any) -> None:
        # Records that a live client was constructed so the eval can fail loudly. No network.
        _LIVE_CLIENT_STATE["constructed"] += 1
        self.chat = SimpleNamespace(completions=_FakeCompletions())


@contextmanager
def offline_openai_guard() -> Iterator[None]:
    """Install a no-network fake ``openai`` module and ensure ``LALA_ENABLE_LIVE_AI`` is off.

    Primary guarantee: with the flag cleared, ``generate_script`` takes the rule-based path
    and the live client is never constructed. The fake module is defense-in-depth so the live
    branch — if ever reached — makes zero network calls.
    """
    saved_module = sys.modules.get("openai")
    fake_module = types.ModuleType("openai")
    fake_module.OpenAI = _FakeOpenAI  # type: ignore[attr-defined]
    sys.modules["openai"] = fake_module
    saved_flag = os.environ.pop("LALA_ENABLE_LIVE_AI", None)
    saved_constructions = _LIVE_CLIENT_STATE["constructed"]
    _LIVE_CLIENT_STATE["constructed"] = 0
    try:
        yield
    finally:
        if saved_module is not None:
            sys.modules["openai"] = saved_module
        else:
            sys.modules.pop("openai", None)
        if saved_flag is not None:
            os.environ["LALA_ENABLE_LIVE_AI"] = saved_flag
        _LIVE_CLIENT_STATE["constructed"] = saved_constructions
