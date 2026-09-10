from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timedelta, timezone

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.planner import DailyPlanRequest, PlanPreferenceContext
from apps.api.app.services.normalization import normalize_language
from apps.api.app.services.opening_hours_service import (
    estimated_opening_hours,
    is_closing_soon,
    is_within_hours,
)
from apps.api.app.services.places_service import list_places
from apps.api.app.services.request_identity import generation_identity
from apps.api.app.services.travel_time_service import (
    estimate_walking_minutes,
    live_routing_enabled,
    period_start_time,
    resolve_travel_time_authority_minutes,
    walking_distance_m,
)
from apps.api.app.services.weather_service import current_weather

# CP1: walking_band → 상한 분 매핑. max_one_way_minutes 바운드({15,30,60,90})의
# 하위 집합으로 밴드를 표현한다(short=15, medium=30, long=60). 문서화된 값이며
# 실측 authority 가 아님을 effect 설명에서 그대로 밝힌다.
_WALKING_BAND_MAX_MINUTES: dict[str, int] = {"short": 15, "medium": 30, "long": 60}

_WEATHER_SENSITIVE = frozenset({"medium", "high"})


def daily_plan(request: DailyPlanRequest) -> dict:
    language = normalize_language(request.language)
    weather = current_weather(lat=request.lat, lng=request.lng)
    preference = request.preference_context
    # CP1: 반경 상한은 문서화된 도보 추정치(4 km/h)로만 산출하고 요청 반경을
    # 절대 초과하지 않는다(없으면 요청 반경 그대로 — 기존 호출 형태 보존).
    effective_radius_m = request.radius_m
    one_way_minutes: int = 0
    one_way_source_fields: list[str] = []
    if preference is not None:
        one_way_minutes, one_way_source_fields = _effective_one_way_minutes(preference)
        effective_radius_m = min(request.radius_m, walking_distance_m(one_way_minutes))
    places = list_places(
        lat=request.lat,
        lng=request.lng,
        radius_m=effective_radius_m,
        category="all",
        language=language,
    )
    source = _combined_source(places.get("source"), weather.get("source"))
    place_candidates = places.get("places") or []
    # CP1: 실내/야외 정렬은 안정적(stable) 파티션만 — 입력 순서를 깨뜨리지 않고,
    # 관측 가능한 변화가 없으면 applied 로 보고하지 않는다.
    ordering_ordered_by: str | None = None
    ordering_preferred: str | None = None
    ordering_changed = False
    ordering_has_known = False
    if preference is not None and preference.indoor_outdoor != "balanced":
        preferred_direction: str = preference.indoor_outdoor
        ordered_by: str
        weather_safety = (
            weather.get("outdoor_status") == "bad"
            and preference.weather_sensitivity in _WEATHER_SENSITIVE
        )
        if weather_safety and preferred_direction == "outdoor":
            # 나쁜 날씨 + medium/high 민감도가 outdoor soft 선호를 이긴다(안전 우선).
            # unknown 실내 상태는 실내로 취급하지 않는다(honest).
            preferred_direction = "indoor"
            ordered_by = "weather_safety"
        else:
            ordered_by = "preference"
        place_candidates, ordering_has_known, ordering_changed = _stable_partition_by_indoor(
            place_candidates, preferred_direction
        )
        ordering_ordered_by = ordered_by
        ordering_preferred = preferred_direction
    selected_place = _resolve_selected_place(
        place_candidates=place_candidates,
        selected_place_id=request.selected_place_id,
        language=language,
    )
    payload = {
        "language": language,
        "center": {"lat": request.lat, "lng": request.lng},
        "radius_m": request.radius_m,
        "weather": weather,
        "slots": _daily_plan_slots(
            place_candidates=place_candidates,
            weather=weather,
            language=language,
            selected_place=selected_place,
        ),
        "source": source,
        **daily_plan_identity(request, language=language),
    }
    if preference is not None:
        # CP1: preference_effects 는 컨텍스트가 있을 때만 추가(legacy 응답 보존).
        # 지원 근거가 없는 효과는 applied=false + 사유 코드로 정직하게 보고한다.
        payload["preference_effects"] = _preference_effects(
            language=language,
            requested_radius_m=request.radius_m,
            effective_radius_m=effective_radius_m,
            one_way_minutes=one_way_minutes,
            one_way_source_fields=one_way_source_fields,
            ordered_by=ordering_ordered_by,
            preferred_direction=ordering_preferred,
            ordering_changed=ordering_changed,
            ordering_has_known=ordering_has_known,
            weather_outdoor_status=weather.get("outdoor_status"),
        )
    return payload


def _resolve_selected_place(
    *, place_candidates: list[dict], selected_place_id: str | None, language: str
) -> dict | None:
    """D-1: 선택된 장소를 실제 candidate 안에서만 해석한다(대체 장소 발명 금지).

    해석에 실패하면 성공 envelope 으로 '포함하지 못한 플랜'을 돌려주지 않고
    SELECTED_PLACE_UNAVAILABLE 오류로 정직하게 실패한다.
    """
    if selected_place_id is None:
        return None
    for candidate in place_candidates:
        if candidate.get("place_id") == selected_place_id:
            return candidate
    message = (
        "선택한 장소를 이 일정에 포함할 수 없어요."
        if language == "ko"
        else "The selected place cannot be included in this plan."
    )
    raise ServiceError(
        status_code=422,
        code="SELECTED_PLACE_UNAVAILABLE",
        message=message,
        retryable=False,
    )


def _effective_one_way_minutes(preference: PlanPreferenceContext) -> tuple[int, list[str]]:
    """선호 컨텍스트에서 유효 이동시간 상한(분)과 그 근거 필드를 산출한다.

    max_one_way_minutes(명시 분)와 walking_band(문서화 밴드 분) 중 더 작은 쪽.
    동점이면 명시 필드(max_one_way_minutes)를 근거로 내보낸다(결정적 tie-break).
    """
    minutes = int(preference.max_one_way_minutes)
    source_fields = ["max_one_way_minutes"]
    band_minutes = _WALKING_BAND_MAX_MINUTES[preference.walking_band]
    if band_minutes < minutes:
        minutes = band_minutes
        source_fields = ["walking_band"]
    return minutes, source_fields


def _stable_partition_by_indoor(
    place_candidates: list[dict], preferred: str
) -> tuple[list[dict], bool, bool]:
    """선호 방향에 맞춰 후보를 안정적(stable) 파티션 정렬한다.

    - preferred="indoor": is_indoor 가 True 로 *확인된* 후보가 먼저.
    - preferred="outdoor": is_indoor 가 False 로 확인된 후보가 먼저.
    - is_indoor 미확인(None/키 없음)은 실내로 취급하지 않고 뒤쪽에 원래 순서로.
    반환: (ordered, has_known_status, order_changed).
    """
    want_indoor = preferred == "indoor"

    def _matches(candidate: dict) -> bool:
        is_indoor = candidate.get("is_indoor")
        return (want_indoor and is_indoor is True) or (not want_indoor and is_indoor is False)

    has_known_status = any(candidate.get("is_indoor") is not None for candidate in place_candidates)
    ordered = sorted(place_candidates, key=lambda candidate: 0 if _matches(candidate) else 1)
    order_changed = [id(candidate) for candidate in ordered] != [
        id(candidate) for candidate in place_candidates
    ]
    return ordered, has_known_status, order_changed


def _effect_explanation_ko(
    *,
    reason_code: str,
    requested_radius_m: int,
    effective_radius_m: int,
    one_way_minutes: int,
) -> str:
    if reason_code == "RADIUS_CAPPED_TO_WALKING_TIME":
        return (
            f"이동 시간 선호({one_way_minutes}분)에 맞춰 탐색 반경을 "
            f"{requested_radius_m}m에서 {effective_radius_m}m로 줄였어요. "
            "도보 4km/h 기준 추정이에요."
        )
    if reason_code == "RADIUS_CAP_NOT_BINDING":
        return (
            f"요청한 반경이 이미 이동 시간 선호({one_way_minutes}분 이내)에 "
            "들어와 그대로 유지했어요."
        )
    if reason_code == "INDOOR_ORDERING_APPLIED":
        return "실내/야외 선호에 따라 후보 순서를 조정했어요."
    if reason_code == "WEATHER_SAFETY_INDOOR_PRIORITY":
        return "날씨가 좋지 않아 야외 선호보다 실내 후보를 우선 배치했어요."
    if reason_code == "INDOOR_ORDERING_NOT_DIRECTIONAL":
        return "실내/야외 중립 선호라 순서를 바꾸지 않았어요."
    if reason_code == "INDOOR_ORDERING_NO_CHANGE":
        return "후보가 이미 선호에 맞는 순서라 바뀐 항목이 없어요."
    if reason_code == "INDOOR_STATUS_UNAVAILABLE":
        return "실내/야외 정보가 있는 장소가 없어 순서를 바꾸지 못했어요."
    if reason_code == "CUISINE_FACET_UNAVAILABLE":
        return "장소 데이터에 요리 정보가 없어 요리 선호를 반영하지 못했어요."
    if reason_code == "PRICE_FACET_UNAVAILABLE":
        return "장소 데이터에 가격 정보가 없어 예산 선호를 반영하지 못했어요."
    if reason_code == "CLOSING_SOON_FACET_UNAVAILABLE":
        return "장소 데이터에 마감 임박 정보가 없어 제외 선호를 반영하지 못했어요."
    return ""


def _effect_explanation_en(
    *,
    reason_code: str,
    requested_radius_m: int,
    effective_radius_m: int,
    one_way_minutes: int,
) -> str:
    if reason_code == "RADIUS_CAPPED_TO_WALKING_TIME":
        return (
            f"Capped the search radius from {requested_radius_m}m to "
            f"{effective_radius_m}m to match the {one_way_minutes}-minute one-way "
            "preference (estimated at a 4 km/h walk)."
        )
    if reason_code == "RADIUS_CAP_NOT_BINDING":
        return (
            f"The requested radius already fits the {one_way_minutes}-minute "
            "one-way preference, so it was kept as-is."
        )
    if reason_code == "INDOOR_ORDERING_APPLIED":
        return "Candidate order was adjusted to match the indoor/outdoor preference."
    if reason_code == "WEATHER_SAFETY_INDOOR_PRIORITY":
        return (
            "Weather is bad, so known indoor candidates were prioritized over the "
            "outdoor preference."
        )
    if reason_code == "INDOOR_ORDERING_NOT_DIRECTIONAL":
        return "The indoor/outdoor preference is neutral, so no ordering was applied."
    if reason_code == "INDOOR_ORDERING_NO_CHANGE":
        return "Candidates were already ordered per the preference, so nothing changed."
    if reason_code == "INDOOR_STATUS_UNAVAILABLE":
        return "No place carries indoor/outdoor provenance, so no ordering was possible."
    if reason_code == "CUISINE_FACET_UNAVAILABLE":
        return "Place data has no cuisine facet, so the cuisine preference was not applied."
    if reason_code == "PRICE_FACET_UNAVAILABLE":
        return "Place data has no price facet, so the budget preference was not applied."
    if reason_code == "CLOSING_SOON_FACET_UNAVAILABLE":
        return "Place data has no closing-soon facet, so the exclusion preference was not applied."
    return ""


def _effect_entry(
    *,
    field: str,
    applied: bool,
    reason_code: str,
    language: str,
    details: dict[str, object] | None = None,
    requested_radius_m: int = 0,
    effective_radius_m: int = 0,
    one_way_minutes: int = 0,
) -> dict:
    ko = language == "ko"
    explanation = (
        _effect_explanation_ko(
            reason_code=reason_code,
            requested_radius_m=requested_radius_m,
            effective_radius_m=effective_radius_m,
            one_way_minutes=one_way_minutes,
        )
        if ko
        else _effect_explanation_en(
            reason_code=reason_code,
            requested_radius_m=requested_radius_m,
            effective_radius_m=effective_radius_m,
            one_way_minutes=one_way_minutes,
        )
    )
    entry: dict[str, object] = {
        "field": field,
        "applied": applied,
        "reason_code": reason_code,
        "explanation": explanation,
    }
    if details is not None:
        entry["details"] = details
    return entry


def _preference_effects(
    *,
    language: str,
    requested_radius_m: int,
    effective_radius_m: int,
    one_way_minutes: int,
    one_way_source_fields: list[str],
    ordered_by: str | None,
    preferred_direction: str | None,
    ordering_changed: bool,
    ordering_has_known: bool,
    weather_outdoor_status: object,
) -> list[dict]:
    """CP1 preference_effects: 관측 가능한 효과만, 정직한 사유 코드와 함께.

    항상 5개의 안정적 순서 항목을 낸다: 반경 상한(max_one_way_minutes 또는
    walking_band 근거), 실내/야외 정렬(indoor_outdoor), 그리고 데이터 근거가
    없어 반영하지 못한 food_cuisines/budget_band/exclude_closing_soon.
    원시 선호 문서나 민감 값은 절대 포함하지 않는다.
    """
    effects: list[dict] = []
    radius_applied = effective_radius_m < requested_radius_m
    effects.append(
        _effect_entry(
            field=one_way_source_fields[0],
            applied=radius_applied,
            reason_code=(
                "RADIUS_CAPPED_TO_WALKING_TIME" if radius_applied else "RADIUS_CAP_NOT_BINDING"
            ),
            language=language,
            details={
                "requested_radius_m": requested_radius_m,
                "effective_radius_m": effective_radius_m,
                "effective_one_way_minutes": one_way_minutes,
                "source_fields": list(one_way_source_fields),
                "walking_estimate": "haversine_4kmh",
            },
            requested_radius_m=requested_radius_m,
            effective_radius_m=effective_radius_m,
            one_way_minutes=one_way_minutes,
        )
    )
    if preferred_direction is None:
        effects.append(
            _effect_entry(
                field="indoor_outdoor",
                applied=False,
                reason_code="INDOOR_ORDERING_NOT_DIRECTIONAL",
                language=language,
                details={"weather_outdoor_status": weather_outdoor_status},
            )
        )
    else:
        if not ordering_has_known:
            ordering_reason = "INDOOR_STATUS_UNAVAILABLE"
            ordering_applied = False
        elif not ordering_changed:
            ordering_reason = "INDOOR_ORDERING_NO_CHANGE"
            ordering_applied = False
        elif ordered_by == "weather_safety":
            ordering_reason = "WEATHER_SAFETY_INDOOR_PRIORITY"
            ordering_applied = True
        else:
            ordering_reason = "INDOOR_ORDERING_APPLIED"
            ordering_applied = True
        effects.append(
            _effect_entry(
                field="indoor_outdoor",
                applied=ordering_applied,
                reason_code=ordering_reason,
                language=language,
                details={
                    "weather_outdoor_status": weather_outdoor_status,
                    "ordered_by": ordered_by,
                    "preferred": preferred_direction,
                },
            )
        )
    effects.append(
        _effect_entry(
            field="food_cuisines",
            applied=False,
            reason_code="CUISINE_FACET_UNAVAILABLE",
            language=language,
        )
    )
    effects.append(
        _effect_entry(
            field="budget_band",
            applied=False,
            reason_code="PRICE_FACET_UNAVAILABLE",
            language=language,
        )
    )
    effects.append(
        _effect_entry(
            field="exclude_closing_soon",
            applied=False,
            reason_code="CLOSING_SOON_FACET_UNAVAILABLE",
            language=language,
        )
    )
    return effects


def intervention(*, lat: float, lng: float, radius_m: int, language: str = "en") -> dict:
    normalized = normalize_language(language)
    weather = current_weather(lat=lat, lng=lng)
    places = list_places(
        lat=lat,
        lng=lng,
        radius_m=radius_m,
        category="all",
        language="ko",
    )
    candidate = (places.get("places") or [None])[0]
    source = _combined_source(places.get("source"), weather.get("source"))
    candidate_name = (candidate or {}).get("name") or _fallback_candidate_name(normalized)
    outdoor_status = weather["outdoor_status"]
    # P4: distinct observed causes. Weather adversity comes only from the
    # weather-only provenance (KMA/DB weather flags); AQ adversity only from the
    # dust-derived provenance. The merged aggregate outdoor_status is preserved
    # for display/transport but is NEVER promoted to a weather cause or weather
    # reason — a legacy payload without provenance yields no observed cause and
    # unknown stays unknown.
    weather_cause_status = _weather_cause_status(weather)
    air_quality_status = _air_quality_cause_status(weather)
    is_bad_weather = weather_cause_status == "bad"
    is_bad_air_quality = air_quality_status == "bad"
    is_adverse_outdoor = is_bad_weather or is_bad_air_quality
    air_quality_grade = str(((weather.get("dust") or {}).get("grade")) or "").strip() or None
    full_slots = _full_slots_enabled()
    unavailable_reason = (
        "추천 장소가 부족해요" if normalized == "ko" else "Not enough nearby options"
    )
    # 기존 추천을 slot 구조로 옮김(P5A _plan_slot 재사용, period=afternoon).
    original_slot = _plan_slot(
        period="afternoon",
        title=("오후" if normalized == "ko" else "Afternoon"),
        place=candidate,
        weather_hint=outdoor_status,
        unavailable_reason=unavailable_reason,
        language=normalized,
        weather=weather,
        full_slots=full_slots,
    )
    # D5: closure trigger derived offline from original_slot's category-based
    # closure_state. No external feed (BLOCKED_EXTERNAL V7); flag-off → never emits.
    closure_factors: list[dict] = []
    is_closure = full_slots and original_slot.get("closure_state") == "closed"
    if is_closure:
        closure_factors = [
            {"factor": "slot_closure_state", "value": "closed", "period": "afternoon"}
        ]
    # P4 closing-soon: distinct trigger from the same category-based estimated-hours
    # projection — the slot start falls inside the bounded pre-close window
    # (opening_hours_service.CLOSING_SOON_WINDOW_MINUTES). Mutually exclusive with the
    # closure trigger by construction (closing-soon implies within-hours), and the
    # explicit `not is_closure` guard keeps that invariant even for degenerate inputs.
    # Flag-off / missing or malformed times → never triggers.
    is_closing_soon_trigger = (
        full_slots and not is_closure and original_slot.get("closing_soon") is True
    )
    closing_soon_factors: list[dict] = []
    if is_closing_soon_trigger:
        closing_soon_factors = [
            {
                "factor": "slot_closing_soon",
                "value": "within_estimated_window",
                "period": "afternoon",
            }
        ]
    # P4 truth: the reason/action copy must name the estimated-hours cause (never
    # permanent/temporary/holiday closure claims) and, when combined with bad
    # weather/air, must name every actual cause.
    closing_cause = "closed" if is_closure else "closing_soon" if is_closing_soon_trigger else None
    estimated_hours = original_slot.get("estimated_opening_hours") if closing_cause else None
    # P5B §12.4: observable trigger classification + honest-unavailable fields.
    # authority(travel-time/indoor-outdoor)가 없으면 값을 차단할 뿐 contract 는 유지.
    if is_adverse_outdoor and closing_cause:
        # Combined causes: the alternative must satisfy both — indoor (weather/AQ)
        # AND estimated hours that cover the slot without the closing-soon window.
        alternative_slot = _find_open_hours_alternative(
            place_candidates=places.get("places") or [],
            exclude_place_id=(candidate or {}).get("place_id"),
            language=normalized,
            weather_hint=outdoor_status,
            unavailable_reason=unavailable_reason,
            weather=weather,
            full_slots=full_slots,
            require_indoor=True,
        )
    elif is_adverse_outdoor:
        alternative_slot = _find_indoor_alternative(
            place_candidates=places.get("places") or [],
            exclude_place_id=(candidate or {}).get("place_id"),
            language=normalized,
            weather_hint=outdoor_status,
            unavailable_reason=unavailable_reason,
            weather=weather,
            full_slots=full_slots,
        )
    elif closing_cause:
        # Estimated-hours cause: a real existing candidate whose estimated hours
        # cover the slot outside the closing-soon window. Honest null when none.
        alternative_slot = _find_open_hours_alternative(
            place_candidates=places.get("places") or [],
            exclude_place_id=(candidate or {}).get("place_id"),
            language=normalized,
            weather_hint=outdoor_status,
            unavailable_reason=unavailable_reason,
            weather=weather,
            full_slots=full_slots,
            require_indoor=False,
        )
    else:
        alternative_slot = None
    return {
        "center": {"lat": lat, "lng": lng},
        "radius_m": radius_m,
        "should_intervene": is_adverse_outdoor or is_closure or is_closing_soon_trigger,
        "reason": _intervention_reason(
            weather_status=weather_cause_status,
            candidate_name=candidate_name,
            language=normalized,
            air_quality_status=air_quality_status,
            closing_cause=closing_cause,
            estimated_hours=estimated_hours,
        ),
        "recommended_action": _recommended_action(
            weather_status=weather_cause_status,
            candidate_name=candidate_name,
            language=normalized,
            air_quality_status=air_quality_status,
            closing_cause=closing_cause,
        ),
        "place": candidate,
        "source": source,
        "original_slot": original_slot,
        # alternative provenance: real already-fetched candidates only — indoor for
        # adverse weather/AQ (P4), estimated-hours-covered for closing causes.
        # No suitable candidate → honest null (no fixture/demo place).
        "alternative_slot": alternative_slot,
        # observable trigger 만. good/unknown + closure 없음 → null. 발명 금지.
        "trigger_type": _intervention_trigger_type(
            is_bad_weather=is_bad_weather,
            is_closure=is_closure,
            is_bad_air_quality=is_bad_air_quality,
            is_closing_soon=is_closing_soon_trigger,
        ),
        "trigger_factors": _intervention_trigger_factors(
            is_bad_weather=is_bad_weather,
            air_quality_grade=air_quality_grade if is_bad_air_quality else None,
            closure_factors=closure_factors,
            closing_soon_factors=closing_soon_factors,
        ),
        # travel-time authority 부재 → 거리/이동시간 비교 불가(honest null).
        "distance_comparison": None,
        # contract boundary: API 는 항상 default. 실제 상태 관리는 P5C UI/persistence.
        "user_decision": "pending",
        "apply_state": "not_applied",
        "history": [],
    }


def _weather_cause_status(weather: dict) -> str:
    """P4: weather cause from explicit weather-only provenance only.

    A payload without the provenance key carries no observable weather cause —
    the merged aggregate outdoor_status (which may already include dust) is
    never promoted to a weather cause or weather reason. Missing/empty/
    unrecognized values all stay "unknown".
    """
    text = str(weather.get("weather_outdoor_status") or "").strip()
    if text in {"good", "bad"}:
        return text
    return "unknown"


def _air_quality_cause_status(weather: dict) -> str:
    """P4: AQ cause only from the dust-derived provenance (weather_service
    derives it from the current normalized dust payload). A payload without the
    provenance key carries no observed AQ cause — unknown stays unknown."""
    text = str(weather.get("air_quality_outdoor_status") or "").strip()
    if text in {"good", "bad"}:
        return text
    return "unknown"


def _fallback_candidate_name(language: str) -> str:
    return "근처 로컬 장소" if language == "ko" else "nearby local places"


def _full_slots_enabled() -> bool:
    # PLAN_FULL_SLOTS gates the V3 additive slot projections (D2/D3/D4/D6) and the
    # closure trigger (D5). getattr fallback mirrors places_service: test doubles that
    # omit feature_flags stay flag-off (byte-for-byte pre-V3 behavior).
    flags = getattr(get_settings(), "feature_flags", None) or {}
    return bool(flags.get("PLAN_FULL_SLOTS", False))


def _intervention_trigger_type(
    *,
    is_bad_weather: bool,
    is_closure: bool,
    is_bad_air_quality: bool = False,
    is_closing_soon: bool = False,
) -> str | None:
    # D5: additive enum widening on a nullable string. Flag-off ⇒ is_closure False ⇒
    # the pre-V3 "bad_weather"/None result is preserved exactly.
    # P4: bad_air_quality / combinations are additive widenings with a fixed
    # deterministic order (weather → air quality → closure); the pre-P4
    # bad_weather / closure_detected / bad_weather_and_closure payloads are
    # unchanged for weather/closure-only causes.
    # P4 closing-soon: closing_soon is a distinct estimated-hours trigger, mutually
    # exclusive with closure (closing-soon implies within-hours). If a degenerate
    # input ever set both, closure deterministically dominates.
    if is_closure:
        if is_bad_weather and is_bad_air_quality:
            return "bad_weather_and_air_quality_and_closure"
        if is_bad_air_quality:
            return "bad_air_quality_and_closure"
        if is_bad_weather:
            return "bad_weather_and_closure"
        return "closure_detected"
    if is_closing_soon:
        if is_bad_weather and is_bad_air_quality:
            return "bad_weather_and_air_quality_and_closing_soon"
        if is_bad_air_quality:
            return "bad_air_quality_and_closing_soon"
        if is_bad_weather:
            return "bad_weather_and_closing_soon"
        return "closing_soon"
    if is_bad_weather and is_bad_air_quality:
        return "bad_weather_and_air_quality"
    if is_bad_weather:
        return "bad_weather"
    if is_bad_air_quality:
        return "bad_air_quality"
    return None


def _intervention_trigger_factors(
    *,
    is_bad_weather: bool,
    air_quality_grade: str | None = None,
    closure_factors: list[dict] | None = None,
    closing_soon_factors: list[dict] | None = None,
) -> list[dict]:
    """관측가능 trigger 요소만. 발명된 factor 없음(honest).

    P4: factors disclose the actual observed cause(s) — a bad dust grade emits
    its own air_quality_dust_grade factor with the observed grade value, never
    collapsed into the weather factor. Deterministic order: weather → air
    quality → closure → closing-soon.
    """
    factors: list[dict] = []
    if is_bad_weather:
        factors.append({"factor": "weather_outdoor_status", "value": "bad"})
    if air_quality_grade in _BAD_DUST_GRADES:
        factors.append({"factor": "air_quality_dust_grade", "value": air_quality_grade})
    if closure_factors:
        factors.extend(closure_factors)
    if closing_soon_factors:
        factors.extend(closing_soon_factors)
    return factors


def _find_indoor_alternative(
    *,
    place_candidates: list[dict],
    exclude_place_id: str | None,
    language: str,
    weather_hint: str | None,
    unavailable_reason: str,
    weather: dict | None = None,
    full_slots: bool = False,
) -> dict | None:
    """AI enrichment is_indoor=true 인 첫 번째 대체 장소를 slot 으로 반환.

    provenance 없거나 실내 장소가 없으면 None(honest). 발명된 대체 금지.
    """
    for place in place_candidates:
        if place.get("place_id") == exclude_place_id:
            continue
        if place.get("is_indoor") is True:
            return _plan_slot(
                period="afternoon",
                title="오후" if language == "ko" else "Afternoon",
                place=place,
                weather_hint=weather_hint,
                unavailable_reason=unavailable_reason,
                language=language,
                weather=weather,
                full_slots=full_slots,
            )
    return None


def _find_open_hours_alternative(
    *,
    place_candidates: list[dict],
    exclude_place_id: str | None,
    language: str,
    weather_hint: str | None,
    unavailable_reason: str,
    weather: dict | None = None,
    full_slots: bool = False,
    require_indoor: bool = False,
) -> dict | None:
    """P4 closing-soon/closure 대안: 이미 가져온 실제 candidate 중 추정 운영시간이
    슬롯을 커버하면서 closing-soon window 밖인 첫 장소를 slot으로 반환.

    require_indoor=True면 adverse weather/air 조합 원인에서처럼 실내 장소만 쓴다.
    조건을 만족하는 candidate이 없으면 None(honest). 발명된 대체 금지 —
    fixture/demo 장소를 일반 경로에 넣지 않는다.
    """
    start_t = period_start_time("afternoon")
    for place in place_candidates:
        if place.get("place_id") == exclude_place_id:
            continue
        if require_indoor and place.get("is_indoor") is not True:
            continue
        open_t, close_t = estimated_opening_hours(place.get("category", ""))
        if is_within_hours(start_t, open_t, close_t) is not True:
            continue
        if is_closing_soon(start_t, open_t, close_t) is True:
            continue
        return _plan_slot(
            period="afternoon",
            title="오후" if language == "ko" else "Afternoon",
            place=place,
            weather_hint=weather_hint,
            unavailable_reason=unavailable_reason,
            language=language,
            weather=weather,
            full_slots=full_slots,
        )
    return None


def _combined_source(place_source: str | None, weather_source: str | None) -> str:
    sources = {place_source or "unavailable", weather_source or "unavailable"}
    if sources == {"db"}:
        return "db"
    if sources == {"public_mvp_snapshot"}:
        return "public_mvp_snapshot"
    if "db" in sources:
        return "mixed"
    if "public_mvp_snapshot" in sources:
        return "mixed"
    return "unavailable"


_PERIOD_ORDER = ("morning", "lunch", "afternoon", "dinner")


def _daily_plan_slots(
    *,
    place_candidates: list[dict],
    weather: dict,
    language: str,
    selected_place: dict | None = None,
) -> list[dict]:
    """정확히 4 period 슬롯(morning/lunch/afternoon/dinner)을 발생한다(순서 고정).

    truthfulness: place 는 실제 candidate 만 dedupe 배정한다. travel-time /
    opening-hours / franchise 등 authority 가 없으면 관련 필드는 null(honest
    unavailable)이고, 후보가 부족해 place 가 없는 slot 은 unavailable_reason 로
    정직한 부재를 전달한다. timestamp/fake authority 값은 절대 발명하지 않는다.

    D-1: selected_place 가 있으면 해당 종류의 첫 슬롯(restaurant → lunch, 그 외 →
    morning)에 정확히 한 번 배정하고 used 처리해 나머지 배정에서 제외한다(이중 배정 금지).
    """
    ko = language == "ko"
    titles = {
        "morning": "오전" if ko else "Morning",
        "lunch": "점심" if ko else "Lunch",
        "afternoon": "오후" if ko else "Afternoon",
        "dinner": "저녁" if ko else "Dinner",
    }
    weather_hint = weather.get("outdoor_status")
    unavailable_reason = "추천 장소가 부족해요" if ko else "Not enough nearby options"

    # restaurant 후보는 식사 slot(lunch/dinner) 에, non-restaurant 후보는
    # morning/afternoon 에 우선 배정(deterministic, 입력 순서 유지).
    restaurants = [p for p in place_candidates if p.get("category") == "restaurant"]
    others = [p for p in place_candidates if p.get("category") != "restaurant"]
    used_place_ids: set[str] = set()
    ri = 0
    ni = 0

    # D-1 고정 배정: 선택 장소는 첫 슬롯에 배정 후 used 처리 — 아래 deterministic
    # allocation 은 나머지 3슬롯만 채운다(선택 장소의 중복/재배정 없음).
    selected_period: str | None = None
    if selected_place is not None:
        selected_period = "lunch" if selected_place.get("category") == "restaurant" else "morning"
        selected_id = selected_place.get("place_id")
        if selected_id is not None:
            used_place_ids.add(selected_id)

    def _take_restaurant() -> dict | None:
        return _take_deduping(restaurants, "r")

    def _take_other() -> dict | None:
        return _take_deduping(others, "n")

    def _take_deduping(group: list[dict], state_key: str) -> dict | None:
        # advance the matching pointer, skipping already-used place_ids (dedupe).
        nonlocal ri, ni
        i = ri if state_key == "r" else ni
        while i < len(group):
            candidate = group[i]
            i += 1
            place_id = candidate.get("place_id")
            if place_id is not None and place_id in used_place_ids:
                continue
            if place_id is not None:
                used_place_ids.add(place_id)
            if state_key == "r":
                ri = i
            else:
                ni = i
            return candidate
        if state_key == "r":
            ri = i
        else:
            ni = i
        return None

    def _take_pinned_or(period: str, take: Callable[[], dict | None]) -> dict | None:
        if period == selected_period:
            return selected_place
        return take()

    # deterministic allocation: primary list, fallback to the other list.
    morning = _take_pinned_or("morning", _take_other)
    lunch = _take_pinned_or("lunch", _take_restaurant)
    if lunch is None:
        lunch = _take_other()
    afternoon = _take_other()
    if afternoon is None:
        afternoon = _take_restaurant()
    dinner = _take_restaurant()
    if dinner is None:
        dinner = _take_other()

    assigned = {
        "morning": morning,
        "lunch": lunch,
        "afternoon": afternoon,
        "dinner": dinner,
    }

    # Consecutive-slot estimated walking time (Haversine ÷ 4 km/h).
    # First slot has no previous → null. Slots without place → null.
    prev_place: dict | None = None
    travel_times: dict[str, int | None] = {}
    # V5-C routing seam: authoritative Directions ETA per slot. Gated hook — computed
    # only when LALA_ENABLE_LIVE_ROUTING is on; honestly null in V5 (Directions are
    # BLOCKED_EXTERNAL/V7). Flag-off keeps the slot key set byte-for-byte pre-V5.
    routing_authority_enabled = live_routing_enabled()
    travel_time_authorities: dict[str, int | None] = {}
    for period in _PERIOD_ORDER:
        place = assigned[period]
        if prev_place is not None and place is not None:
            travel_times[period] = estimate_walking_minutes(
                float(prev_place.get("lat") or 0),
                float(prev_place.get("lng") or 0),
                float(place.get("lat") or 0),
                float(place.get("lng") or 0),
            )
        else:
            travel_times[period] = None
        if routing_authority_enabled and prev_place is not None and place is not None:
            travel_time_authorities[period] = resolve_travel_time_authority_minutes(
                float(prev_place.get("lat") or 0),
                float(prev_place.get("lng") or 0),
                float(place.get("lat") or 0),
                float(place.get("lng") or 0),
            )
        else:
            travel_time_authorities[period] = None
        prev_place = place if place is not None else prev_place

    # D6: swappable_alternatives populated from the existing candidate-pool leftovers
    # (already-fetched places not assigned to any slot). Flag-off ⇒ empty dict ⇒ each
    # slot stays swappable_alternatives: [] (byte-for-byte pre-V3).
    full_slots = _full_slots_enabled()
    swappable = (
        _swappable_alternatives_by_period(assigned=assigned, place_candidates=place_candidates)
        if full_slots
        else {}
    )

    return [
        _plan_slot(
            period=period,
            title=titles[period],
            place=assigned[period],
            weather_hint=weather_hint,
            unavailable_reason=unavailable_reason,
            language=language,
            travel_time=travel_times[period],
            weather=weather,
            full_slots=full_slots,
            swappable_alternatives=swappable.get(period),
            routing_authority_enabled=routing_authority_enabled,
            travel_time_authority=travel_time_authorities[period],
        )
        for period in _PERIOD_ORDER
    ]


def _swappable_alternatives_by_period(
    *, assigned: dict[str, dict | None], place_candidates: list[dict]
) -> dict[str, list[dict]]:
    # D6: per-slot swap candidates = pool leftovers (not assigned to any slot), same
    # category first, capped at 3. Honest [] when the pool is exhausted. No new fetch.
    assigned_places = [p for p in assigned.values() if p is not None]
    assigned_ids = {p.get("place_id") for p in assigned_places if p.get("place_id") is not None}
    assigned_obj_ids = {id(p) for p in assigned_places}
    leftovers = [
        p
        for p in place_candidates
        if id(p) not in assigned_obj_ids and p.get("place_id") not in assigned_ids
    ]
    by_period: dict[str, list[dict]] = {}
    for period in _PERIOD_ORDER:
        slot_place = assigned[period]
        if slot_place is None:
            by_period[period] = []
            continue
        category = slot_place.get("category")
        same = [p for p in leftovers if p.get("category") == category]
        other = [p for p in leftovers if p.get("category") != category]
        by_period[period] = (same + other)[:3]
    return by_period


_RECOMMENDATION_REASON = {
    "restaurant": ("맛집으로 추천해요", "Recommended as a local restaurant"),
    "attraction": ("명소로 추천해요", "Recommended as a local attraction"),
    "event": ("진행 중인 행사예요", "An ongoing event"),
    "culture_venue": ("문화 공간이에요", "A culture venue"),
}
_DEFAULT_REASON = ("가까운 추천 장소예요", "A nearby recommended stop")


def _recommendation_reason(place: dict, language: str) -> str:
    ko_label, en_label = _RECOMMENDATION_REASON.get(
        place.get("category") or "other", _DEFAULT_REASON
    )
    return ko_label if language == "ko" else en_label


def _plan_slot(
    *,
    period: str,
    title: str,
    place: dict | None,
    weather_hint: str | None,
    unavailable_reason: str,
    language: str,
    travel_time: int | None = None,
    weather: dict | None = None,
    full_slots: bool = False,
    swappable_alternatives: list[dict] | None = None,
    routing_authority_enabled: bool = False,
    travel_time_authority: int | None = None,
) -> dict:
    # start_time: 관용적 시간대 시작 시각(09:00/12:00/14:00/18:00). opening-hours authority
    # 확보 전까지 표준 관례 기반 추정값.
    # travel_time: Haversine 직선거리 기반 도보 추정(분). routing authority 확보 전까지 추정.
    # stay_duration/opening_hours_valid/indoor_outdoor/franchise: authority 부재 → null.
    indoor_outdoor = None
    if place and place.get("is_indoor") is not None:
        indoor_outdoor = "indoor" if place["is_indoor"] else "outdoor"

    # opening_hours: 카테고리 기반 추정 운영시간 (authority 아님, estimated).
    open_t, close_t = estimated_opening_hours(place.get("category", "") if place else "")
    start_t = period_start_time(period)
    oh_valid = is_within_hours(start_t, open_t, close_t) if place else None
    # P4 closing-soon: 슬롯 시작~추정 마감 거리가 bounded window 이내인지(estimated).
    # is_closing_soon=True는 운영시간 내에서만 나오므로 closure_state="closed"와
    # 구조적으로 상호 배제다. 파싱 불가/장소 없음 → None(unknown).
    cs_valid = is_closing_soon(start_t, open_t, close_t) if place else None

    slot = {
        "period": period,
        "title": title,
        "place": place,
        "weather_hint": weather_hint,
        "start_time": start_t,
        "stay_duration_minutes": None,
        "travel_time_from_previous_minutes": travel_time,
        "opening_hours_valid": oh_valid,
        "estimated_opening_hours": f"{open_t}-{close_t}" if place else None,
        "indoor_outdoor": indoor_outdoor,
        "recommendation_reason": (_recommendation_reason(place, language) if place else None),
        "local_franchise_confidence": None,
        "swappable_alternatives": (
            list(swappable_alternatives) if (full_slots and swappable_alternatives) else []
        ),
        "unavailable_reason": None if place else unavailable_reason,
    }
    if full_slots:
        # PLAN_FULL_SLOTS additive projections (D2/D3/D4). Flag-off omits these keys so
        # the slot payload stays byte-for-byte the pre-V3 shape; values are projections
        # of already-fetched weather/AQ + opening-hours data (no new external call).
        slot["closure_state"] = _closure_state(oh_valid=oh_valid, place=place)
        slot["closing_soon"] = cs_valid
        slot["forecast_window"] = _nearest_forecast_window(start_time=start_t, weather=weather)
        slot["air_quality_bad"] = _air_quality_bad(indoor_outdoor=indoor_outdoor, weather=weather)
    if routing_authority_enabled:
        # V5-C routing-seam projection (C3/D4). Flag-off omits this key so the slot
        # payload stays byte-for-byte pre-V5. Honestly null in V5: real Kakao/Naver
        # Directions are BLOCKED_EXTERNAL/V7, so the authority never guesses a route.
        slot["travel_time_authority_minutes"] = travel_time_authority
    return slot


_KST = timezone(timedelta(hours=9))
_BAD_DUST_GRADES = frozenset({"bad", "very_bad"})
_OK_DUST_GRADES = frozenset({"good", "normal"})


def _closure_state(*, oh_valid: bool | None, place: dict | None) -> str:
    # D4: projection of the category-based opening-hours estimate. Real temporary/holiday
    # closure is NOT knowable here — those map to "unknown" (BLOCKED_EXTERNAL V7).
    if place is None or oh_valid is None:
        return "unknown"
    return "open" if oh_valid else "closed"


def _hhmm_to_minutes(value: str | None) -> int | None:
    if not value or len(value) < 5:
        return None
    try:
        return int(value[:2]) * 60 + int(value[3:5])
    except (ValueError, IndexError):
        return None


def _forecast_item_minutes(time_str: object) -> int | None:
    # Forecast items carry ISO datetime strings; the slot start is a Korean-local HH:MM
    # convention, so normalize the forecast side to KST before comparing minute-of-day.
    if not isinstance(time_str, str) or not time_str:
        return None
    text = time_str.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_KST)
    dt_kst = dt.astimezone(_KST)
    return dt_kst.hour * 60 + dt_kst.minute


def _nearest_forecast_window(*, start_time: str | None, weather: dict | None) -> dict | None:
    # D2: nearest-time projection from the existing plan-level forecast list — no new
    # weather call. Tie-break on equidistant items: earliest (contract A4). Null when the
    # forecast list is empty (AirKorea-only / unavailable paths).
    if not start_time or not weather:
        return None
    forecast = weather.get("forecast") or []
    if not forecast:
        return None
    target = _hhmm_to_minutes(start_time)
    if target is None:
        return None
    best_item: dict | None = None
    best_key: tuple[int, int] | None = None
    for item in forecast:
        if not isinstance(item, dict):
            continue
        minutes = _forecast_item_minutes(item.get("time"))
        if minutes is None:
            continue
        # Sort by (abs delta, forecast minute-of-day) so equidistant ties go to earliest.
        key = (abs(minutes - target), minutes)
        if best_key is None or key < best_key:
            best_key = key
            best_item = item
    if best_item is None:
        return None
    # Project exactly the ForecastItem shape {time,temp,icon} (schema-closed).
    return {
        "time": best_item.get("time"),
        "temp": best_item.get("temp"),
        "icon": best_item.get("icon"),
    }


def _air_quality_bad(*, indoor_outdoor: str | None, weather: dict | None) -> bool | None:
    # D3: outdoor-relevance flag projected from the plan-level dust grade (one station per
    # region; per-slot AQ would be fabricated). Indoor → null; unknown grade → null.
    if indoor_outdoor == "indoor":
        return None
    grade = ((weather or {}).get("dust") or {}).get("grade")
    if grade in _BAD_DUST_GRADES:
        return True
    if grade in _OK_DUST_GRADES:
        return False
    return None


def _intervention_reason(
    *,
    weather_status: str,
    candidate_name: str,
    language: str = "en",
    air_quality_status: str = "unknown",
    closing_cause: str | None = None,
    estimated_hours: str | None = None,
) -> str:
    ko = language == "ko"
    # P4: cause-correct copy. Air-quality adversity is never described as
    # weather; both-bad states both causes explicitly.
    # P4 closing-soon/closure: the estimated-hours cause is always named as an
    # estimate with a check-needed caveat — never observed/confirmed/permanent/
    # temporary/holiday closure. Combined causes name every actual cause.
    if closing_cause is not None:
        hours = estimated_hours or ""
        ko_clause = (
            f"이번 일정 시간은 {candidate_name}의 추정 운영시간({hours}) 마감에 가까워요."
            if closing_cause == "closing_soon"
            else f"이번 일정 시간은 {candidate_name}의 추정 운영시간({hours}) 밖이에요."
        )
        en_clause = (
            f"This slot is near the estimated closing time for {candidate_name} "
            f"(estimated hours {hours})"
            if closing_cause == "closing_soon"
            else f"This slot is outside the estimated hours ({hours}) for {candidate_name}"
        )
        ko_suffix = "실제 영업 여부는 확인이 필요해요."
        en_suffix = "; the actual opening status needs a check."
        if air_quality_status == "bad" and weather_status == "bad":
            return (
                f"날씨와 미세먼지가 모두 좋지 않아요. {ko_clause} {ko_suffix}"
                if ko
                else f"Weather and air quality are both poor. {en_clause}{en_suffix}"
            )
        if air_quality_status == "bad":
            return (
                f"미세먼지가 나빠요. {ko_clause} {ko_suffix}"
                if ko
                else f"Air quality is poor. {en_clause}{en_suffix}"
            )
        if weather_status == "bad":
            return (
                f"날씨가 좋지 않아요. {ko_clause} {ko_suffix}"
                if ko
                else f"Weather is not ideal. {en_clause}{en_suffix}"
            )
        return f"{ko_clause} {ko_suffix}" if ko else f"{en_clause}{en_suffix}"
    if air_quality_status == "bad" and weather_status == "bad":
        return (
            f"날씨와 미세먼지가 모두 좋지 않아요. {candidate_name} 근처의 가까운 실내 동선을 우선해요."
            if ko
            else (
                "Weather and air quality are both poor; prioritize short-walk or "
                f"indoor-friendly options near {candidate_name}."
            )
        )
    if air_quality_status == "bad":
        return (
            f"미세먼지가 나빠요. {candidate_name} 근처의 가까운 실내 동선을 우선해요."
            if ko
            else (
                "Air quality is poor; prioritize short-walk or indoor-friendly "
                f"options near {candidate_name}."
            )
        )
    if weather_status == "good":
        return (
            f"날씨가 좋아 {candidate_name} 방향으로 일정을 유지해요."
            if ko
            else f"Weather is suitable, so keep the current route toward {candidate_name}."
        )
    if weather_status == "unknown":
        return (
            f"날씨 정보를 확인 중이에요. {candidate_name}을(를) 우선 유지해요."
            if ko
            else f"Weather data is still pending, so keep {candidate_name} as the current option."
        )
    return (
        f"날씨가 좋지 않아요. {candidate_name} 근처의 가까운 실내 동선을 우선해요."
        if ko
        else (
            "Weather is not ideal; prioritize short-walk or indoor-friendly "
            f"options near {candidate_name}."
        )
    )


def _recommended_action(
    *,
    weather_status: str,
    candidate_name: str,
    language: str = "en",
    air_quality_status: str = "unknown",
    closing_cause: str | None = None,
) -> str:
    ko = language == "ko"
    # P4 closing-soon/closure: the action names the estimated-hours cause (and
    # each combined weather/air cause) without claiming any closure authority.
    if closing_cause is not None:
        if air_quality_status == "bad" and weather_status == "bad":
            return (
                f"날씨, 미세먼지와 추정 운영시간을 함께 고려해 {candidate_name} 근처의 실내 옵션을 확인해 보세요."
                if ko
                else f"Weigh weather, air quality and the estimated hours together: check indoor options near {candidate_name}."
            )
        if air_quality_status == "bad":
            return (
                f"미세먼지와 추정 운영시간을 함께 고려해 {candidate_name} 근처의 실내 옵션을 확인해 보세요."
                if ko
                else f"Weigh air quality and the estimated hours together: check indoor options near {candidate_name}."
            )
        if weather_status == "bad":
            return (
                f"날씨와 추정 운영시간을 함께 고려해 {candidate_name} 근처의 실내 옵션을 확인해 보세요."
                if ko
                else f"Weigh the weather and the estimated hours together: check indoor options near {candidate_name}."
            )
        if closing_cause == "closing_soon":
            return (
                f"{candidate_name}의 추정 마감 시간을 확인하고 근처 다른 옵션도 함께 검토해 보세요."
                if ko
                else f"Check the estimated closing time for {candidate_name} and review other nearby options too."
            )
        return (
            f"{candidate_name} 대신 추정 운영시간이 이번 일정을 커버하는 근처 옵션을 확인해 보세요."
            if ko
            else f"Check nearby options covered by the estimated hours instead of {candidate_name}."
        )
    if air_quality_status == "bad" or weather_status == "bad":
        # Weather-neutral adverse-outdoor action: indoor/short-walk alternatives
        # help for bad weather and bad air quality alike.
        return (
            f"{candidate_name} 주변의 실내 또는 가까운 동선을 보여줘요."
            if ko
            else f"Show indoor or short-walk alternatives around {candidate_name}."
        )
    if weather_status == "good":
        return (
            f"{candidate_name}을(를) 우선 추천해요."
            if ko
            else f"Keep {candidate_name} as the primary local stop."
        )
    if weather_status == "unknown":
        return (
            f"날씨 확인까지 {candidate_name}을(를) 유지해요."
            if ko
            else f"Keep {candidate_name} while weather data is pending."
        )
    return (
        f"{candidate_name} 주변의 실내 또는 가까운 동선을 보여줘요."
        if ko
        else f"Show indoor or short-walk alternatives around {candidate_name}."
    )


def daily_plan_identity(
    request: DailyPlanRequest, *, language: str | None = None
) -> dict[str, str]:
    # D-1: selected_place_id 는 None(미지정)일 때 페이로드에 키를 넣지 않는다 —
    # 기존 비지정 플랜의 request_hash/cache_key 를 바이트 단위로 보존하기 위해서다.
    payload: dict[str, object] = {
        "lat": request.lat,
        "lng": request.lng,
        "radius_m": request.radius_m,
        "language": language or normalize_language(request.language),
    }
    if request.selected_place_id is not None:
        payload["selected_place_id"] = request.selected_place_id
    # CP1: preference_context 도 None 이면 페이로드에 키를 넣지 않는다 —
    # 컨텍스트 없는 요청의 정체성이 기존 바이트와 동일하게 유지되기 위해서다.
    if request.preference_context is not None:
        payload["preference_context"] = request.preference_context.model_dump()
    return generation_identity("daily_plan", payload)
