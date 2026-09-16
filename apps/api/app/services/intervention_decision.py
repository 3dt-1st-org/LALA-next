from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

_BAD_DUST_GRADES = {"bad", "very_bad", "나쁨", "매우나쁨"}


@dataclass(frozen=True)
class InterventionDecision:
    weather_status: str
    air_quality_status: str
    is_closure: bool
    is_closing_soon: bool
    air_quality_grade: str | None = None
    closure_factors: tuple[dict[str, Any], ...] = ()
    closing_soon_factors: tuple[dict[str, Any], ...] = ()

    @property
    def is_bad_weather(self) -> bool:
        return self.weather_status == "bad"

    @property
    def is_bad_air_quality(self) -> bool:
        return self.air_quality_status == "bad"

    @property
    def is_adverse_outdoor(self) -> bool:
        return self.is_bad_weather or self.is_bad_air_quality

    @property
    def closing_cause(self) -> str | None:
        if self.is_closure:
            return "closed"
        if self.is_closing_soon:
            return "closing_soon"
        return None

    @property
    def should_intervene(self) -> bool:
        return self.is_adverse_outdoor or self.is_closure or self.is_closing_soon

    @property
    def trigger_type(self) -> str | None:
        if self.is_closure:
            if self.is_bad_weather and self.is_bad_air_quality:
                return "bad_weather_and_air_quality_and_closure"
            if self.is_bad_air_quality:
                return "bad_air_quality_and_closure"
            if self.is_bad_weather:
                return "bad_weather_and_closure"
            return "closure_detected"
        if self.is_closing_soon:
            if self.is_bad_weather and self.is_bad_air_quality:
                return "bad_weather_and_air_quality_and_closing_soon"
            if self.is_bad_air_quality:
                return "bad_air_quality_and_closing_soon"
            if self.is_bad_weather:
                return "bad_weather_and_closing_soon"
            return "closing_soon"
        if self.is_bad_weather and self.is_bad_air_quality:
            return "bad_weather_and_air_quality"
        if self.is_bad_weather:
            return "bad_weather"
        if self.is_bad_air_quality:
            return "bad_air_quality"
        return None

    @property
    def trigger_factors(self) -> list[dict[str, Any]]:
        factors: list[dict[str, Any]] = []
        if self.is_bad_weather:
            factors.append({"factor": "weather_outdoor_status", "value": "bad"})
        if self.air_quality_grade in _BAD_DUST_GRADES:
            factors.append({"factor": "air_quality_dust_grade", "value": self.air_quality_grade})
        factors.extend(self.closure_factors)
        factors.extend(self.closing_soon_factors)
        return factors


def build_decision(
    *,
    weather_status: str,
    air_quality_status: str,
    air_quality_grade: str | None,
    is_closure: bool,
    is_closing_soon: bool,
    closure_factors: list[dict[str, Any]] | None = None,
    closing_soon_factors: list[dict[str, Any]] | None = None,
) -> InterventionDecision:
    closure = bool(is_closure)
    return InterventionDecision(
        weather_status=weather_status,
        air_quality_status=air_quality_status,
        air_quality_grade=air_quality_grade,
        is_closure=closure,
        is_closing_soon=bool(is_closing_soon and not closure),
        closure_factors=tuple(closure_factors or ()),
        closing_soon_factors=tuple(closing_soon_factors or ()),
    )


def select_first_candidate(
    *,
    place_candidates: list[dict],
    exclude_place_id: str | None,
    predicates: list[Callable[[dict], bool]],
    build_slot: Callable[[dict], dict],
) -> dict | None:
    for place in place_candidates:
        if place.get("place_id") == exclude_place_id:
            continue
        if all(predicate(place) for predicate in predicates):
            return build_slot(place)
    return None


def is_indoor(place: dict) -> bool:
    return place.get("is_indoor") is True


def intervention_reason_spec(
    *,
    weather_status: str,
    candidate_name: str,
    air_quality_status: str = "unknown",
    closing_cause: str | None = None,
    estimated_hours: str | None = None,
) -> tuple[str, dict[str, object]]:
    values: dict[str, object] = {
        "candidate_name": candidate_name,
        "estimated_hours": estimated_hours or "",
    }
    if closing_cause is not None:
        if air_quality_status == "bad" and weather_status == "bad":
            cause = "both"
        elif air_quality_status == "bad":
            cause = "air"
        elif weather_status == "bad":
            cause = "weather"
        else:
            cause = "only"
        return f"reason.estimated.{cause}.{closing_cause}", values
    if air_quality_status == "bad" and weather_status == "bad":
        return "reason.adverse.both", values
    if air_quality_status == "bad":
        return "reason.adverse.air", values
    if weather_status == "good":
        return "reason.weather.good", values
    if weather_status == "unknown":
        return "reason.weather.unknown", values
    return "reason.weather.bad", values


def intervention_action_spec(
    *,
    weather_status: str,
    candidate_name: str,
    air_quality_status: str = "unknown",
    closing_cause: str | None = None,
) -> tuple[str, dict[str, object]]:
    values: dict[str, object] = {"candidate_name": candidate_name}
    if closing_cause is not None:
        if air_quality_status == "bad" and weather_status == "bad":
            return "action.estimated.both", values
        if air_quality_status == "bad":
            return "action.estimated.air", values
        if weather_status == "bad":
            return "action.estimated.weather", values
        return f"action.estimated.{closing_cause}", values
    if air_quality_status == "bad" or weather_status == "bad":
        return "action.adverse", values
    if weather_status == "good":
        return "action.weather.good", values
    if weather_status == "unknown":
        return "action.weather.unknown", values
    return "action.adverse", values
