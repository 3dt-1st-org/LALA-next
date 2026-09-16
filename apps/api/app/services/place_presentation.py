from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from apps.api.app.services import i18n_catalog, region_catalog

_INDOOR_PREFERRED_CATEGORIES = {"restaurant", "culture_venue"}
_UPSTREAM_REASON_SOURCES = {"tour_api", "kcisa", "kopis"}


def english_display_name(row: dict[str, Any]) -> str:
    region = english_region(row)
    category_label = i18n_catalog.category_label(
        row.get("category"), language="en", title_case=True
    )
    return f"{category_label} in {region}" if region else category_label


def english_display_address(row: dict[str, Any]) -> str:
    region = english_region(row)
    province = english_province(row)
    if region and province:
        return f"{region}, {province}"
    return region or province or ""


def english_region(row: dict[str, Any]) -> str | None:
    region_ko = str(row.get("region_ko") or "").strip()
    canonical = region_catalog.REGION_NAME_EN.get(region_ko)
    if canonical:
        return canonical
    value = str(row.get("region_en") or "").strip()
    return value or None


def english_province(row: dict[str, Any]) -> str | None:
    province_ko = region_catalog.infer_province_name_from_address(
        row.get("address_ko") or row.get("region_ko")
    )
    if province_ko and province_ko in region_catalog.PROVINCE_NAME_EN:
        return region_catalog.PROVINCE_NAME_EN[province_ko]
    return region_catalog.province_name_en_for_region(row.get("region_ko"))


def upstream_source_reason_phrase(upstream_source: str, *, language: str = "ko") -> str | None:
    if (upstream_source or "").strip() not in _UPSTREAM_REASON_SOURCES:
        return None
    return i18n_catalog.source_label(upstream_source, language=language, namespace="evidence")


def local_activity_reason_phrase(
    local_activity_band: str | None, *, language: str = "ko"
) -> str | None:
    if not local_activity_band:
        return None
    return i18n_catalog.message("reason.activity.active", language=language)


def weather_band_phrase(
    current_weather: dict, *, category: str, language: str = "ko"
) -> str | None:
    if not current_weather:
        return None
    if current_weather.get("outdoor_status") == "bad":
        if category not in _INDOOR_PREFERRED_CATEGORIES:
            return None
        return i18n_catalog.message("reason.weather.indoor_friendly", language=language)
    try:
        temp_c = float(current_weather.get("temp"))
    except (TypeError, ValueError):
        return None
    if temp_c < 5:
        key = "reason.weather.cold"
    elif temp_c < 18:
        key = "reason.weather.cool"
    elif temp_c < 27:
        key = "reason.weather.warm"
    else:
        key = "reason.weather.hot"
    return i18n_catalog.message(key, language=language)


def linked_event_reason_phrase(
    has_linked_event: bool | None, *, is_ongoing: bool | None, language: str = "ko"
) -> str | None:
    if not has_linked_event:
        return None
    key = "reason.event.ongoing" if is_ongoing else "reason.event.linked"
    return i18n_catalog.message(key, language=language)


def derive_place_reason(*, place: dict, current_weather: dict, language: str = "ko") -> str:
    reasons: list[str] = []
    category = place.get("category", "")
    for phrase in (
        weather_band_phrase(current_weather, category=category, language=language),
        local_activity_reason_phrase(place.get("_local_activity_band"), language=language),
        linked_event_reason_phrase(
            place.get("_has_linked_event"),
            is_ongoing=place.get("is_ongoing"),
            language=language,
        ),
    ):
        if phrase:
            reasons.append(phrase)
    distance_m = place.get("distance_m", 0)
    if isinstance(distance_m, (int, float)) and distance_m <= 500:
        reasons.append(i18n_catalog.message("reason.proximity.nearby", language=language))
    if source_phrase := upstream_source_reason_phrase(
        place.get("upstream_source", ""), language=language
    ):
        reasons.append(source_phrase)
    return " · ".join(reasons)


def format_freshness(
    updated_at: str | datetime | None, now: datetime, language: str = "ko"
) -> str | None:
    if not updated_at:
        return None
    try:
        if isinstance(updated_at, str):
            updated_at_dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        elif isinstance(updated_at, datetime):
            updated_at_dt = updated_at
        else:
            return None
        if updated_at_dt.tzinfo is None:
            updated_at_dt = updated_at_dt.replace(tzinfo=UTC)
        total_seconds = (now - updated_at_dt).total_seconds()
        if total_seconds < 0 or total_seconds < 60:
            return i18n_catalog.message("freshness.now", language=language)
        if total_seconds < 3600:
            return i18n_catalog.message(
                "freshness.minutes_ago",
                language=language,
                values={"count": int(total_seconds // 60)},
            )
        if total_seconds < 86400:
            return i18n_catalog.message(
                "freshness.hours_ago",
                language=language,
                values={"count": int(total_seconds // 3600)},
            )
        return i18n_catalog.message(
            "freshness.days_ago", language=language, values={"count": int(total_seconds // 86400)}
        )
    except (TypeError, ValueError):
        return None
