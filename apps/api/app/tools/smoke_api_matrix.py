from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
import re
import sys
from typing import Any
from urllib import error, parse, request


@dataclass(frozen=True)
class SmokeCase:
    method: str
    path: str
    body: bytes | None = None
    response_kind: str = "json"
    validator: str | None = None

    @property
    def route_label(self) -> str:
        return self.path.split("?", 1)[0]


@dataclass(frozen=True)
class SmokeFailure:
    case: SmokeCase
    status: int | str
    reason: str


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run a broader LALA-next API smoke matrix."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument(
        "--profile",
        choices=("deploy", "full"),
        default="full",
        help="Use deploy for a bounded CI gate or full for the wider route matrix.",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    result = run_matrix(
        base_url=args.base_url, timeout=args.timeout, profile=args.profile
    )
    if args.json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        _print_human(result)
    return 0 if result["ok"] else 1


def run_matrix(
    *, base_url: str, timeout: float, profile: str = "full"
) -> dict[str, Any]:
    base_url = base_url.rstrip("/")
    readyz = _request_json(
        SmokeCase("GET", "/readyz"),
        base_url=base_url,
        headers={},
        timeout=timeout,
    )
    deploy_readyz_failure = (
        _deploy_readyz_failure(readyz) if profile == "deploy" else None
    )
    if deploy_readyz_failure:
        return {
            "ok": False,
            "mode": "api_matrix_smoke",
            "profile": profile,
            "checked": 0,
            "failures": [deploy_readyz_failure],
        }
    auth_headers = _matching_auth_headers(readyz)
    if auth_headers is None:
        return {
            "ok": False,
            "mode": "api_matrix_smoke",
            "profile": profile,
            "checked": 0,
            "failures": [
                {
                    "method": "AUTH",
                    "path": "/readyz",
                    "status": "missing",
                    "reason": "no_matching_client_auth",
                }
            ],
        }

    failures: list[SmokeFailure] = []
    cases = _build_cases(
        profile=profile,
        live_speech_enabled=_live_speech_enabled(readyz),
    )
    for case in cases:
        failure = _run_case(
            case,
            base_url=base_url,
            headers=auth_headers,
            timeout=timeout,
        )
        if failure:
            failures.append(failure)
    checked = len(cases)
    if profile == "deploy":
        checked += 1
        live_docent_failure = _run_live_docent_context_case(
            base_url=base_url,
            headers=auth_headers,
            timeout=timeout,
        )
        if live_docent_failure:
            failures.append(live_docent_failure)

    return {
        "ok": not failures,
        "mode": "api_matrix_smoke",
        "profile": profile,
        "checked": checked,
        "failures": [
            {
                "method": failure.case.method,
                "path": failure.case.route_label,
                "status": failure.status,
                "reason": failure.reason,
            }
            for failure in failures
        ],
    }


def _deploy_readyz_failure(readyz_payload: dict[str, Any]) -> dict[str, Any] | None:
    data = readyz_payload.get("data") or {}
    if data.get("status") != "ok":
        return _readyz_failure("readyz_not_ok")
    mode = data.get("mode") or {}
    checks = data.get("checks") or {}
    if mode.get("data") != "db-backed":
        return _readyz_failure("data_mode_not_db_backed")
    if checks.get("db") != "configured":
        return _readyz_failure("db_not_configured")
    if checks.get("postgis") != "configured":
        return _readyz_failure("postgis_not_configured")
    if checks.get("static_snapshot_fallback") == "enabled":
        return _readyz_failure("static_snapshot_fallback_enabled")
    if checks.get("client_auth") == "snapshot-fallback":
        return _readyz_failure("snapshot_fallback_auth_enabled")
    return None


def _readyz_failure(reason: str) -> dict[str, Any]:
    return {
        "method": "READYZ",
        "path": "/readyz",
        "status": "failed",
        "reason": reason,
    }


def _build_cases(*, profile: str, live_speech_enabled: bool) -> list[SmokeCase]:
    if profile == "deploy":
        return _build_deploy_cases(live_speech_enabled=live_speech_enabled)
    if profile != "full":
        raise ValueError(f"Unsupported smoke matrix profile: {profile}")
    return _build_full_cases(live_speech_enabled=live_speech_enabled)


def _build_deploy_cases(*, live_speech_enabled: bool) -> list[SmokeCase]:
    location = {"lat": 37.5665, "lng": 126.9780, "radius_m": 3000}
    nearby_location = {**location, "radius_m": 1000}
    gyeonggi_location = {"lat": 37.2819, "lng": 127.0142, "radius_m": 3000}
    place_query = parse.urlencode(
        {**location, "category": "all", "language": "ko", "include_scores": "true"}
    )
    nearby_place_query = parse.urlencode(
        {
            **nearby_location,
            "category": "all",
            "language": "ko",
            "include_scores": "true",
        }
    )
    gyeonggi_place_query = parse.urlencode(
        {
            **gyeonggi_location,
            "category": "all",
            "language": "ko",
            "include_scores": "true",
        }
    )
    weather_query = parse.urlencode(location)
    gyeonggi_weather_query = parse.urlencode(gyeonggi_location)
    return [
        SmokeCase("GET", f"/api/v1/places?{place_query}", validator="places_live_data"),
        SmokeCase(
            "GET",
            f"/api/v1/places?{nearby_place_query}",
            validator="places_location_data",
        ),
        SmokeCase(
            "GET",
            f"/api/v1/places?{gyeonggi_place_query}",
            validator="places_local_value_data",
        ),
        SmokeCase(
            "GET", f"/api/v1/weather?{weather_query}", validator="weather_live_data"
        ),
        SmokeCase(
            "GET",
            f"/api/v1/weather?{gyeonggi_weather_query}",
            validator="weather_live_data",
        ),
        SmokeCase(
            "GET",
            f"/api/v1/plans/intervention?{weather_query}",
            validator="intervention_live_data",
        ),
        SmokeCase(
            "POST",
            "/api/v1/plans/daily",
            _json_body({**location, "language": "ko"}),
            validator="daily_plan_live_data",
        ),
        SmokeCase(
            "POST",
            "/api/v1/docents/script",
            _json_body(
                {
                    "place_id": "tour-api-3066000",
                    "place_name": "중랑아트센터",
                    "address": "서울특별시 중랑구 망우로 353",
                    "region_ko": "중랑구",
                    "distance_m": 840,
                    "source": "db",
                    "upstream_source": "tour_api",
                    "final_score": 0.86,
                    "local_spending_score": 0.82,
                    "small_merchant_fit_score": 0.76,
                    "demand_dispersion_score": 0.78,
                    "weather_fit_score": 0.74,
                    "culture_relevance_score": 0.91,
                    "weather_temp": "21.6",
                    "weather_icon": "partly-cloudy",
                    "weather_outdoor_status": "good",
                    "dust_grade": "good",
                    "dust_pm10": "6",
                    "dust_pm25": "2",
                    "dust_pm10_grade": "좋음",
                    "dust_pm25_grade": "좋음",
                    "category": "culture_venue",
                    "language": "ko",
                    "mode": "brief",
                }
            ),
            validator="docent_quality",
        ),
        SmokeCase(
            "POST",
            "/api/v1/docents/audio",
            _json_body({"script": "스모크 오디오", "language": "ko"}),
            response_kind="audio" if live_speech_enabled else "speech_disabled",
        ),
    ]


def _build_full_cases(*, live_speech_enabled: bool) -> list[SmokeCase]:
    cases: list[SmokeCase] = []
    for category in ("all", "attraction", "restaurant", "event", "culture_venue"):
        for language in ("ko", "en", "English", "kr"):
            query = parse.urlencode(
                {
                    "lat": 37.2636,
                    "lng": 127.0286,
                    "radius_m": 1000,
                    "category": category,
                    "language": language,
                }
            )
            cases.append(SmokeCase("GET", f"/api/v1/places?{query}"))

    for lat, lng in (
        (37.2636, 127.0286),
        (37.5665, 126.9780),
        (0, 0),
        (33.4996, 126.5312),
    ):
        query = parse.urlencode({"lat": lat, "lng": lng, "radius_m": 50000})
        cases.append(SmokeCase("GET", f"/api/v1/weather?{query}"))
        cases.append(SmokeCase("GET", f"/api/v1/plans/intervention?{query}"))
        cases.append(
            SmokeCase(
                "POST",
                "/api/v1/plans/daily",
                _json_body(
                    {"lat": lat, "lng": lng, "radius_m": 50000, "language": "ko"}
                ),
            )
        )

    for category in ("attraction", "restaurant", "event", "culture_venue"):
        cases.append(
            SmokeCase(
                "POST",
                "/api/v1/docents/script",
                _json_body(
                    {
                        "place_id": f"smoke-{category}",
                        "place_name": "스모크",
                        "category": category,
                        "language": "ko",
                        "mode": "brief",
                    }
                ),
            )
        )

    cases.append(
        SmokeCase(
            "POST",
            "/api/v1/docents/audio",
            _json_body({"script": "스모크 오디오", "language": "ko"}),
            response_kind="audio" if live_speech_enabled else "speech_disabled",
        )
    )
    return cases


def _run_case(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> SmokeFailure | None:
    try:
        status, content_type, body = _request_raw(
            case,
            base_url=base_url,
            headers=headers,
            timeout=timeout,
        )
    except Exception as exc:
        return SmokeFailure(case=case, status="exception", reason=type(exc).__name__)

    if case.response_kind == "speech_disabled":
        if status != 503:
            return SmokeFailure(case=case, status=status, reason="speech_not_disabled")
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            return SmokeFailure(case=case, status=status, reason="invalid_json")
        error_payload = payload.get("error")
        if not isinstance(error_payload, dict):
            return SmokeFailure(case=case, status=status, reason="missing_error_object")
        if error_payload.get("code") != "SPEECH_NOT_CONFIGURED":
            return SmokeFailure(
                case=case,
                status=status,
                reason="unexpected_speech_disabled_error",
            )
        if b"LALA docent audio" in body:
            return SmokeFailure(case=case, status=status, reason="fake_audio_body")
        return None

    if status >= 500:
        return SmokeFailure(case=case, status=status, reason="server_error")
    if case.response_kind == "audio":
        if not content_type.startswith("audio/mpeg"):
            return SmokeFailure(
                case=case, status=status, reason="unexpected_audio_content_type"
            )
        if not body:
            return SmokeFailure(case=case, status=status, reason="empty_audio_body")
        return None

    try:
        payload = json.loads(body.decode("utf-8"))
    except Exception:
        return SmokeFailure(case=case, status=status, reason="invalid_json")
    if payload.get("ok") is not True:
        return SmokeFailure(case=case, status=status, reason="ok_false")
    validation_failure = _validate_payload(case.validator, payload)
    if validation_failure:
        return SmokeFailure(case=case, status=status, reason=validation_failure)
    return None


def _run_live_docent_context_case(
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> SmokeFailure | None:
    chain_case = SmokeCase("CHAIN", "/api/v1/docents/script:live-context")
    location = {"lat": 37.5665, "lng": 126.9780, "radius_m": 3000}
    place_query = parse.urlencode(
        {
            **location,
            "category": "all",
            "language": "ko",
            "include_scores": "true",
        }
    )
    weather_query = parse.urlencode(
        {"lat": location["lat"], "lng": location["lng"], "force": "false"}
    )
    try:
        places_status, places_payload = _request_json_with_status(
            SmokeCase("GET", f"/api/v1/places?{place_query}"),
            base_url=base_url,
            headers=headers,
            timeout=timeout,
        )
        if places_status >= 500:
            return SmokeFailure(
                case=chain_case, status=places_status, reason="live_places_server_error"
            )
        places_failure = _validate_payload("places_live_data", places_payload)
        if places_failure:
            return SmokeFailure(
                case=chain_case, status=places_status, reason=places_failure
            )
        places_data = places_payload.get("data") or {}
        places = places_data.get("places")
        if (
            not isinstance(places, list)
            or not places
            or not isinstance(places[0], dict)
        ):
            return SmokeFailure(
                case=chain_case, status=places_status, reason="live_places_empty"
            )
        place = places[0]

        weather_status, weather_payload = _request_json_with_status(
            SmokeCase("GET", f"/api/v1/weather?{weather_query}"),
            base_url=base_url,
            headers=headers,
            timeout=timeout,
        )
        if weather_status >= 500:
            return SmokeFailure(
                case=chain_case,
                status=weather_status,
                reason="live_weather_server_error",
            )
        weather_failure = _validate_payload("weather_live_data", weather_payload)
        if weather_failure:
            return SmokeFailure(
                case=chain_case, status=weather_status, reason=weather_failure
            )
        weather = weather_payload.get("data") or {}

        docent_body = _live_docent_body(place=place, weather=weather)
        docent_status, docent_payload = _request_json_with_status(
            SmokeCase(
                "POST",
                "/api/v1/docents/script",
                _json_body(docent_body),
                validator="docent_quality",
            ),
            base_url=base_url,
            headers=headers,
            timeout=timeout,
        )
        if docent_status >= 500:
            return SmokeFailure(
                case=chain_case,
                status=docent_status,
                reason="live_docent_server_error",
            )
        docent_failure = _validate_payload("docent_quality", docent_payload)
        if docent_failure:
            return SmokeFailure(
                case=chain_case, status=docent_status, reason=docent_failure
            )
        context_failure = _validate_live_docent_context(
            docent_payload.get("data") or {},
            place=place,
            weather=weather,
        )
        if context_failure:
            return SmokeFailure(
                case=chain_case, status=docent_status, reason=context_failure
            )
    except Exception as exc:
        return SmokeFailure(
            case=chain_case,
            status="exception",
            reason=type(exc).__name__,
        )
    return None


def _live_docent_body(
    *,
    place: dict[str, Any],
    weather: dict[str, Any],
) -> dict[str, Any]:
    score = place.get("score")
    if not isinstance(score, dict):
        score = {}
    components = score.get("components")
    if not isinstance(components, dict):
        components = {}
    dust = weather.get("dust")
    if not isinstance(dust, dict):
        dust = {}
    payload: dict[str, Any] = {
        "place_id": _text(place.get("place_id")) or _text(place.get("id")),
        "category": _docent_category(place.get("category")),
        "language": "ko",
        "mode": "brief",
    }
    _add_text(payload, "place_name", place.get("name"))
    _add_text(payload, "address", place.get("address"))
    _add_text(payload, "region_ko", place.get("region_ko"))
    _add_text(payload, "region_en", place.get("region_en"))
    _add_text(payload, "source", place.get("source"))
    _add_text(payload, "upstream_source", place.get("upstream_source"))
    _add_int(payload, "distance_m", place.get("distance_m"))
    _add_score(payload, "final_score", score.get("final_score"))
    _add_score(payload, "local_spending_score", components.get("local_spending_score"))
    _add_score(
        payload,
        "small_merchant_fit_score",
        components.get("small_merchant_fit_score"),
    )
    _add_score(
        payload,
        "demand_dispersion_score",
        components.get("demand_dispersion_score"),
    )
    _add_score(payload, "weather_fit_score", components.get("weather_fit_score"))
    _add_score(
        payload,
        "culture_relevance_score",
        components.get("culture_relevance_score"),
    )
    _add_text(payload, "weather_temp", weather.get("temp"))
    _add_text(payload, "weather_icon", weather.get("icon"))
    _add_text(payload, "weather_outdoor_status", weather.get("outdoor_status"))
    _add_text(payload, "dust_grade", dust.get("grade_ko") or dust.get("grade"))
    _add_text(payload, "dust_pm10", dust.get("pm10"))
    _add_text(payload, "dust_pm25", dust.get("pm25"))
    _add_text(
        payload,
        "dust_pm10_grade",
        dust.get("pm10_grade_ko") or dust.get("pm10_grade"),
    )
    _add_text(
        payload,
        "dust_pm25_grade",
        dust.get("pm25_grade_ko") or dust.get("pm25_grade"),
    )
    return payload


def _validate_live_docent_context(
    data: dict[str, Any],
    *,
    place: dict[str, Any],
    weather: dict[str, Any],
) -> str | None:
    script = str(data.get("script") or "")
    place_name = _text(place.get("name"))
    if place_name and place_name not in script:
        return "docent_missing_live_place_name"
    dust = weather.get("dust")
    if not isinstance(dust, dict):
        return "docent_missing_live_dust_payload"
    pm10 = _text(dust.get("pm10"))
    pm25 = _text(dust.get("pm25"))
    if pm10 and not re.search(rf"PM10\s*{re.escape(pm10)}(?!\d)", script):
        return "docent_missing_live_pm10_value"
    if pm25 and not re.search(rf"PM2\.5\s*{re.escape(pm25)}(?!\d)", script):
        return "docent_missing_live_pm25_value"
    return None


def _docent_category(value: Any) -> str:
    category = _text(value)
    if category in {"attraction", "restaurant", "event", "culture_venue"}:
        return category
    return "attraction"


def _add_text(payload: dict[str, Any], key: str, value: Any) -> None:
    text = _text(value)
    if text:
        payload[key] = text


def _add_int(payload: dict[str, Any], key: str, value: Any) -> None:
    if isinstance(value, bool):
        return
    if isinstance(value, int):
        payload[key] = value
        return
    if isinstance(value, float) and value.is_integer():
        payload[key] = int(value)
        return
    text = _text(value)
    if not text:
        return
    try:
        payload[key] = int(float(text))
    except ValueError:
        return


def _add_score(payload: dict[str, Any], key: str, value: Any) -> None:
    if isinstance(value, bool):
        return
    if isinstance(value, (int, float)):
        score = float(value)
    else:
        text = _text(value)
        if not text:
            return
        try:
            score = float(text)
        except ValueError:
            return
    if 0 <= score <= 1:
        payload[key] = score


def _text(value: Any) -> str:
    return str(value or "").strip()


def _validate_payload(validator: str | None, payload: dict[str, Any]) -> str | None:
    if not validator:
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return "missing_data_object"
    return {
        "places_live_data": _validate_places_live_data,
        "places_local_value_data": _validate_places_local_value_data,
        "places_location_data": _validate_places_location_data,
        "weather_live_data": _validate_weather_live_data,
        "intervention_live_data": _validate_intervention_live_data,
        "daily_plan_live_data": _validate_daily_plan_live_data,
        "docent_quality": _validate_docent_quality,
    }[validator](data)


def _validate_places_live_data(data: dict[str, Any]) -> str | None:
    if _is_fallback_source(data.get("source")):
        return "places_source_not_live_db"
    if str(data.get("location_engine") or "").strip() != "postgis":
        return "places_location_engine_not_postgis"
    places = data.get("places")
    if not isinstance(places, list) or not places:
        return "places_empty"
    if any(
        _is_fallback_source(place.get("source"))
        for place in places
        if isinstance(place, dict)
    ):
        return "place_contains_fallback_source"
    if any(
        str(place.get("upstream_source") or "").strip()
        in {"dev_seed", "local_fixture"}
        for place in places
        if isinstance(place, dict)
    ):
        return "place_contains_local_fixture_source"
    if any(
        _looks_synthetic_image_url(place.get("image_url"))
        for place in places
        if isinstance(place, dict)
    ):
        return "place_contains_synthetic_image"
    if not any(
        _has_live_score(place.get("score"))
        for place in places
        if isinstance(place, dict)
    ):
        return "places_missing_live_score"
    return None


def _validate_places_local_value_data(data: dict[str, Any]) -> str | None:
    live_failure = _validate_places_live_data(data)
    if live_failure:
        return live_failure
    places = data.get("places")
    if not isinstance(places, list) or not places:
        return "places_empty"
    if not any(
        _has_actual_local_spending_signal(place.get("score"))
        for place in places
        if isinstance(place, dict)
    ):
        return "places_missing_actual_local_spending_signal"
    return None


def _validate_places_location_data(data: dict[str, Any]) -> str | None:
    live_failure = _validate_places_live_data(data)
    if live_failure:
        return live_failure
    places = data.get("places")
    if not isinstance(places, list) or not places:
        return "places_empty"
    distances: list[float] = []
    for place in places:
        if not isinstance(place, dict):
            continue
        distance = place.get("distance_m")
        if isinstance(distance, bool) or not isinstance(distance, (int, float)):
            return "place_missing_postgis_distance"
        if distance < 0 or distance > 1000:
            return "place_distance_outside_radius"
        distances.append(float(distance))
    if not distances:
        return "places_missing_postgis_distances"
    if max(distances) <= 0:
        return "places_distance_not_location_specific"
    if len(distances) > 1 and len({round(distance) for distance in distances}) < 2:
        return "places_distance_not_varied"
    return None


def _validate_weather_live_data(data: dict[str, Any]) -> str | None:
    if _is_fallback_source(data.get("source")):
        return "weather_source_not_live"
    source = str(data.get("source") or "").strip().lower()
    if "airkorea" not in source:
        return "weather_missing_airkorea_source"
    location = str(data.get("location") or "").strip().lower().replace(" ", "")
    if location in {"", "기상청격자", "kmagrid"}:
        return "weather_internal_location_label"
    air_quality_location = (
        str(data.get("air_quality_location") or "").strip().lower().replace(" ", "")
    )
    if air_quality_location in {"", "기상청격자", "kmagrid"}:
        return "weather_missing_air_quality_location"
    if not str(data.get("air_quality_record_time") or "").strip():
        return "weather_missing_air_quality_record_time"
    if not str(data.get("temp") or "").strip():
        return "weather_missing_temperature"
    dust = data.get("dust")
    if not isinstance(dust, dict):
        return "weather_missing_dust"
    pm10_value = _parse_non_negative_number(dust.get("pm10"))
    pm25_value = _parse_non_negative_number(dust.get("pm25"))
    if pm10_value is None or pm25_value is None:
        return "weather_missing_dust_values"
    pm10_grade = str(dust.get("pm10_grade") or "").strip()
    pm25_grade = str(dust.get("pm25_grade") or "").strip()
    if pm10_grade in {"", "unknown"} or pm25_grade in {"", "unknown"}:
        return "weather_missing_dust_split"
    return None


def _validate_intervention_live_data(data: dict[str, Any]) -> str | None:
    if _is_fallback_source(data.get("source")):
        return "intervention_source_not_live"
    place = data.get("place")
    if isinstance(place, dict) and _is_fallback_source(place.get("source")):
        return "intervention_place_not_live"
    return None


def _validate_daily_plan_live_data(data: dict[str, Any]) -> str | None:
    if _is_fallback_source(data.get("source")):
        return "daily_plan_source_not_live"
    slots = data.get("slots")
    if not isinstance(slots, list) or not slots:
        return "daily_plan_empty_slots"
    for slot in slots:
        if not isinstance(slot, dict):
            continue
        place = slot.get("place")
        if isinstance(place, dict) and _is_fallback_source(place.get("source")):
            return "daily_plan_place_not_live"
    return None


def _validate_docent_quality(data: dict[str, Any]) -> str | None:
    if _is_fallback_source(data.get("source")):
        return "docent_source_not_live"
    script = str(data.get("script") or "").strip()
    if len(script) < 40:
        return "docent_script_too_short"
    lowered = script.lower()
    if any(term in lowered for term in ("skeleton", "placeholder", "mock", "demo")):
        return "docent_script_contains_placeholder"
    if any(
        term in script
        for term in ("종합 추천 점수", "최종 추천 점수", "장소 지식 인덱스", "°C°C")
    ):
        return "docent_script_contains_internal_evidence"
    if re.search(
        r"(추천 점수|내국인 소비|관광 수요 분산|날씨 적합도|리뷰 품질|문화 연계)"
        r"(?:는|은|:)?\s*\d",
        script,
    ) or re.search(
        r"(recommendation score|domestic spending score|tourism demand dispersion|"
        r"weather fit|review quality|culture relevance)\s*(?:is|:)?\s*\d",
        lowered,
    ):
        return "docent_script_contains_score_value"
    if re.search(
        r"(?:^|[.!?]\s*)\d{1,3}(?:\s*\.\s*\d{1,3})?\s*입니다",
        script,
    ):
        return "docent_script_contains_orphan_score_decimal"
    if any(
        term in lowered
        for term in (
            "culture_venue",
            "tour_api",
            "dev_seed",
            "local_fixture",
            "public_mvp_snapshot",
            "snapshot",
        )
    ) or "스냅샷" in script:
        return "docent_script_contains_internal_code"
    grounding_count = data.get("grounding_count")
    if not isinstance(grounding_count, int) or grounding_count < 1:
        return "docent_missing_grounding"
    grounding_sources = data.get("grounding_sources")
    if not isinstance(grounding_sources, list) or not grounding_sources:
        return "docent_missing_grounding_sources"
    if not any(term in script for term in ("현재 위치", "840m", "거리")):
        return "docent_missing_location_context"
    if not any(term in script for term in ("내국인 소비", "로컬 소비", "지역 소비")):
        return "docent_missing_local_value_context"
    if not any(term in script for term in ("소상공인", "상권", "골목", "로컬 카페", "local business")):
        return "docent_missing_small_merchant_context"
    if any(term in script for term in ("준비하고 있습니다", "준비 중입니다")):
        return "docent_script_too_generic"
    if not any(term in script for term in ("날씨", "미세먼지", "초미세먼지", "PM10")):
        return "docent_missing_weather_context"
    if "PM10" not in script or not any(term in script for term in ("PM2.5", "초미세먼지")):
        return "docent_missing_dust_split_context"
    if not any(term in script for term in ("방문 전후", "동선", "이어", "함께 연결", "continue to the next")):
        return "docent_missing_route_action_context"
    if not any(term in script for term in ("공식", "한국관광공사")):
        return "docent_missing_official_grounding"
    return None


def _is_fallback_source(value: Any) -> bool:
    source = str(value or "").strip()
    if not source:
        return False
    lowered = source.lower()
    return lowered in {
        "public_mvp_snapshot",
        "demo_fallback",
        "demo_seed",
        "dev_seed",
        "fallback",
        "local_fixture",
        "skeleton",
        "unavailable",
    } or lowered.endswith("_fallback")


def _looks_synthetic_image_url(value: Any) -> bool:
    url = str(value or "").strip().lower()
    return any(token in url for token in ("mock", "placeholder", "lorem", "dummy"))


def _parse_non_negative_number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        parsed = float(value)
    else:
        text = str(value or "").strip()
        if not text or text in {"-", "--"}:
            return None
        try:
            parsed = float(text)
        except ValueError:
            return None
    if parsed < 0:
        return None
    return parsed


def _has_live_score(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    data_basis = str(value.get("data_basis") or "").strip()
    return (
        data_basis == "analytics.place_score_snapshots"
        and value.get("final_score") is not None
    )


def _has_actual_local_spending_signal(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    if str(value.get("data_basis") or "").strip() != "analytics.place_score_snapshots":
        return False
    components = value.get("components")
    features = value.get("features")
    if not isinstance(components, dict) or not isinstance(features, dict):
        return False
    missing = {
        str(item).strip()
        for item in (features.get("missing_signals") or [])
        if str(item).strip()
    }
    return (
        components.get("local_spending_score") is not None
        and bool(str(features.get("card_month") or "").strip())
        and "card_spending_area_monthly" not in missing
    )


def _request_json(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> dict[str, Any]:
    _, _, body = _request_raw(case, base_url=base_url, headers=headers, timeout=timeout)
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError("Unexpected JSON response.")
    return payload


def _request_json_with_status(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> tuple[int, dict[str, Any]]:
    status, _, body = _request_raw(
        case, base_url=base_url, headers=headers, timeout=timeout
    )
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError("Unexpected JSON response.")
    if payload.get("ok") is not True:
        raise RuntimeError("Unexpected non-ok JSON response.")
    return status, payload


def _request_raw(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> tuple[int, str, bytes]:
    request_headers = dict(headers)
    if case.body is not None:
        request_headers["Content-Type"] = "application/json; charset=utf-8"
    req = request.Request(
        base_url + case.path,
        data=case.body,
        headers=request_headers,
        method=case.method,
    )
    try:
        with request.urlopen(req, timeout=timeout) as response:
            return (
                response.status,
                response.headers.get("content-type", ""),
                response.read(),
            )
    except error.HTTPError as exc:
        return exc.code, exc.headers.get("content-type", ""), exc.read()


def _matching_auth_headers(readyz_payload: dict[str, Any]) -> dict[str, str] | None:
    checks = (readyz_payload.get("data") or {}).get("checks") or {}
    bearer = os.getenv("LALA_SMOKE_BEARER_TOKEN") or os.getenv("API_BEARER_TOKEN")
    api_key = os.getenv("LALA_SMOKE_API_KEY") or os.getenv("IOS_API_KEY")
    if (
        checks.get("client_auth") == "public-contest"
        or checks.get("client_identity") == "public-contest"
    ):
        return {}
    if checks.get("bearer_token") == "configured" and bearer:
        return {"Authorization": f"Bearer {bearer}"}
    if checks.get("api_key") == "configured" and api_key:
        return {"X-API-Key": api_key}
    return None


def _live_speech_enabled(readyz_payload: dict[str, Any]) -> bool:
    data = readyz_payload.get("data") or {}
    checks = data.get("checks") or {}
    mode = data.get("mode") or {}
    return mode.get("speech") == "live-azure" or checks.get("live_speech") == "enabled"


def _json_body(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _print_human(result: dict[str, Any]) -> None:
    print("LALA-next API matrix smoke")
    print(f"mode={result['mode']}")
    print(f"profile={result['profile']}")
    print(f"status={'ok' if result['ok'] else 'failed'}")
    print(f"checked={result['checked']}")
    for failure in result.get("failures") or []:
        print(
            "failure="
            f"{failure['method']} {failure['path']} "
            f"status={failure['status']} reason={failure['reason']}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    raise SystemExit(main())
