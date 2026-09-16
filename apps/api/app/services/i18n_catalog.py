from __future__ import annotations

from collections.abc import Mapping

from apps.api.app.services.normalization import normalize_language

_MESSAGES: dict[str, dict[str, str]] = {
    "ko": {
        "category.label.attraction": "명소",
        "category.label.culture_venue": "문화공간",
        "category.label.event": "행사",
        "category.label.restaurant": "맛집",
        "category.label.default": "로컬 장소",
        "source.organization.tour_api": "한국관광공사",
        "source.organization.kcisa": "문화정보원",
        "source.organization.kopis": "공연예술통합전산망",
        "source.evidence.tour_api": "한국관광공사 데이터",
        "source.evidence.kcisa": "문화정보원 데이터",
        "source.evidence.kopis": "공연예술통합전산망 데이터",
        "source.evidence.db": "운영 DB",
        "source.evidence.public_mvp_snapshot": "제한적 오프라인 데이터",
        "source.evidence.place_profile": "검증된 장소 프로필",
        "source.evidence.place_mention": "주간 로컬 언급 수",
        "source.evidence.review": "방문자 리뷰",
        "source.evidence.naver_blog": "로컬 블로그 글",
        "prompt.evidence_type.tour_api": "official tourism data",
        "prompt.evidence_type.place_profile": "verified place profile",
        "prompt.evidence_type.place_mention": "weekly local mention counts",
        "prompt.evidence_type.review": "visitor reviews",
        "prompt.evidence_type.naver_blog": "local blog posts",
        "weather.icon.partly_cloudy": "구름 조금",
        "weather.icon.cloudy": "흐림",
        "weather.icon.clear": "맑음",
        "weather.icon.sunny": "맑음",
        "weather.icon.rain": "비",
        "weather.icon.sleet": "비 또는 눈",
        "weather.icon.snow": "눈",
        "weather.air.good": "좋음",
        "weather.air.normal": "보통",
        "weather.air.bad": "나쁨",
        "weather.air.very_bad": "매우나쁨",
        "weather.air.outdoor": "실외",
        "weather.air.indoor": "실내",
        "weather.air.indoor_outdoor": "실내외",
        "reason.activity.active": "로컬 소비 활발",
        "reason.weather.indoor_friendly": "실내활동 적합",
        "reason.weather.cold": "추운 날씨",
        "reason.weather.cool": "선선한 날씨",
        "reason.weather.warm": "따뜻한 날씨",
        "reason.weather.hot": "더운 날씨",
        "reason.event.ongoing": "진행 중인 행사",
        "reason.event.linked": "행사 연계",
        "reason.proximity.nearby": "근접",
        "freshness.now": "방금 전",
        "freshness.minutes_ago": "{count}분 전",
        "freshness.hours_ago": "{count}시간 전",
        "freshness.days_ago": "{count}일 전",
        "docent.category_context.attraction": "주변 산책 동선과 생활권 상권을 함께 보면, 대표 명소가 지역 안에서 어떤 역할을 하는지 더 또렷해집니다.",
        "docent.category_context.restaurant": "상호와 주변 소비 흐름을 함께 보며, 프랜차이즈보다 지역 식당의 개성과 골목의 분위기를 우선 살핍니다.",
        "docent.category_context.event": "행사 자체뿐 아니라 방문 전후에 머무를 수 있는 근처 문화공간과 소상공인 상권까지 이어서 보는 코스입니다.",
        "docent.category_context.culture_venue": "전시나 공연 관람 전후의 짧은 이동 반경 안에서 로컬 카페, 식당, 골목 경험을 함께 연결합니다.",
        "docent.category_context.default": "공식 데이터와 주변 장소를 함께 살펴볼 수 있는 로컬 경험입니다.",
        "docent.route_action.restaurant": "식사 전후에는 가까운 문화공간이나 골목 산책으로 다음 장소를 이어가 보세요.",
        "docent.route_action.event": "행사 방문 전후에는 주변 상권과 가까운 문화공간을 하나의 동선으로 함께 연결해 보세요.",
        "docent.route_action.culture_venue": "관람 전후에는 가까운 카페, 식당, 골목 산책을 하나의 동선으로 이어가 보세요.",
        "docent.route_action.attraction": "방문 전후에는 주변 산책길과 로컬 상권을 함께 묶어 다음 장소로 이어가 보세요.",
        "docent.route_action.default": "방문 전후에는 가까운 다음 장소와 로컬 상권을 함께 이어가 보세요.",
        "intervention.reason.estimated.both.closed": "날씨와 미세먼지가 모두 좋지 않아요. 이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 밖이에요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.both.closing_soon": "날씨와 미세먼지가 모두 좋지 않아요. 이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 마감에 가까워요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.air.closed": "미세먼지가 나빠요. 이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 밖이에요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.air.closing_soon": "미세먼지가 나빠요. 이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 마감에 가까워요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.weather.closed": "날씨가 좋지 않아요. 이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 밖이에요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.weather.closing_soon": "날씨가 좋지 않아요. 이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 마감에 가까워요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.only.closed": "이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 밖이에요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.estimated.only.closing_soon": "이번 일정 시간은 {candidate_name}의 추정 운영시간({estimated_hours}) 마감에 가까워요. 실제 영업 여부는 확인이 필요해요.",
        "intervention.reason.adverse.both": "날씨와 미세먼지가 모두 좋지 않아요. {candidate_name} 근처의 가까운 실내 동선을 우선해요.",
        "intervention.reason.adverse.air": "미세먼지가 나빠요. {candidate_name} 근처의 가까운 실내 동선을 우선해요.",
        "intervention.reason.weather.good": "날씨가 좋아 {candidate_name} 방향으로 일정을 유지해요.",
        "intervention.reason.weather.unknown": "날씨 정보를 확인 중이에요. {candidate_name}을(를) 우선 유지해요.",
        "intervention.reason.weather.bad": "날씨가 좋지 않아요. {candidate_name} 근처의 가까운 실내 동선을 우선해요.",
        "intervention.action.estimated.both": "날씨, 미세먼지와 추정 운영시간을 함께 고려해 {candidate_name} 근처의 실내 옵션을 확인해 보세요.",
        "intervention.action.estimated.air": "미세먼지와 추정 운영시간을 함께 고려해 {candidate_name} 근처의 실내 옵션을 확인해 보세요.",
        "intervention.action.estimated.weather": "날씨와 추정 운영시간을 함께 고려해 {candidate_name} 근처의 실내 옵션을 확인해 보세요.",
        "intervention.action.estimated.closing_soon": "{candidate_name}의 추정 마감 시간을 확인하고 근처 다른 옵션도 함께 검토해 보세요.",
        "intervention.action.estimated.closed": "{candidate_name} 대신 추정 운영시간이 이번 일정을 커버하는 근처 옵션을 확인해 보세요.",
        "intervention.action.adverse": "{candidate_name} 주변의 실내 또는 가까운 동선을 보여줘요.",
        "intervention.action.weather.good": "{candidate_name}을(를) 우선 추천해요.",
        "intervention.action.weather.unknown": "날씨 확인까지 {candidate_name}을(를) 유지해요.",
    },
    "en": {
        "category.label.attraction": "attraction",
        "category.label.culture_venue": "culture venue",
        "category.label.event": "event",
        "category.label.restaurant": "restaurant",
        "category.label.default": "local place",
        "source.organization.tour_api": "Korea Tourism Organization",
        "source.organization.kcisa": "Korea Culture Information Service",
        "source.organization.kopis": "KOPIS performing arts",
        "source.evidence.tour_api": "Korea Tourism Organization data",
        "source.evidence.kcisa": "Korea Culture Information Service data",
        "source.evidence.kopis": "KOPIS performing arts data",
        "source.evidence.db": "the live LALA database",
        "source.evidence.public_mvp_snapshot": "limited offline data",
        "source.evidence.place_profile": "verified place profile",
        "source.evidence.place_mention": "weekly local mention counts",
        "source.evidence.review": "visitor reviews",
        "source.evidence.naver_blog": "local blog posts",
        "prompt.evidence_type.tour_api": "official tourism data",
        "prompt.evidence_type.place_profile": "verified place profile",
        "prompt.evidence_type.place_mention": "weekly local mention counts",
        "prompt.evidence_type.review": "visitor reviews",
        "prompt.evidence_type.naver_blog": "local blog posts",
        "weather.icon.partly_cloudy": "partly cloudy",
        "weather.icon.cloudy": "cloudy",
        "weather.icon.clear": "clear",
        "weather.icon.sunny": "sunny",
        "weather.icon.rain": "rainy",
        "weather.icon.sleet": "mixed rain and snow",
        "weather.icon.snow": "snowy",
        "weather.air.good": "good",
        "weather.air.normal": "moderate",
        "weather.air.bad": "unhealthy",
        "weather.air.very_bad": "very unhealthy",
        "weather.air.outdoor": "outdoor",
        "weather.air.indoor": "indoor",
        "weather.air.indoor_outdoor": "indoor and outdoor",
        "reason.activity.active": "Active local spending",
        "reason.weather.indoor_friendly": "Indoor-friendly",
        "reason.weather.cold": "Cold weather",
        "reason.weather.cool": "Cool weather",
        "reason.weather.warm": "Warm weather",
        "reason.weather.hot": "Hot weather",
        "reason.event.ongoing": "Ongoing event",
        "reason.event.linked": "Linked event",
        "reason.proximity.nearby": "Nearby",
        "freshness.now": "just now",
        "freshness.minutes_ago": "{count} min ago",
        "freshness.hours_ago": "{count} hr ago",
        "freshness.days_ago": "{count} days ago",
        "docent.category_context.attraction": "Read it together with nearby walking routes and small local businesses to understand its role in the neighborhood.",
        "docent.category_context.restaurant": "LALA looks for local character and neighborhood spending signals instead of treating every food stop as a generic listing.",
        "docent.category_context.event": "The route is designed to connect the event with nearby culture spaces and small local businesses before or after the visit.",
        "docent.category_context.culture_venue": "Use it as an anchor for a short route that connects exhibitions, performances, cafes, restaurants, and nearby streets.",
        "docent.category_context.default": "LALA reads official data together with nearby local context.",
        "docent.route_action.restaurant": "Before or after eating, continue to a nearby culture space or short neighborhood walk.",
        "docent.route_action.event": "Before or after the event, connect it with nearby local businesses and culture spaces.",
        "docent.route_action.culture_venue": "Before or after the visit, continue through nearby cafes, restaurants, and walkable streets.",
        "docent.route_action.attraction": "Before or after the stop, connect it with nearby walking paths and local businesses.",
        "docent.route_action.default": "Before or after the stop, continue to a nearby place and local business area.",
        "intervention.reason.estimated.both.closed": "Weather and air quality are both poor. This slot is outside the estimated hours ({estimated_hours}) for {candidate_name}; the actual opening status needs a check.",
        "intervention.reason.estimated.both.closing_soon": "Weather and air quality are both poor. This slot is near the estimated closing time for {candidate_name} (estimated hours {estimated_hours}); the actual opening status needs a check.",
        "intervention.reason.estimated.air.closed": "Air quality is poor. This slot is outside the estimated hours ({estimated_hours}) for {candidate_name}; the actual opening status needs a check.",
        "intervention.reason.estimated.air.closing_soon": "Air quality is poor. This slot is near the estimated closing time for {candidate_name} (estimated hours {estimated_hours}); the actual opening status needs a check.",
        "intervention.reason.estimated.weather.closed": "Weather is not ideal. This slot is outside the estimated hours ({estimated_hours}) for {candidate_name}; the actual opening status needs a check.",
        "intervention.reason.estimated.weather.closing_soon": "Weather is not ideal. This slot is near the estimated closing time for {candidate_name} (estimated hours {estimated_hours}); the actual opening status needs a check.",
        "intervention.reason.estimated.only.closed": "This slot is outside the estimated hours ({estimated_hours}) for {candidate_name}; the actual opening status needs a check.",
        "intervention.reason.estimated.only.closing_soon": "This slot is near the estimated closing time for {candidate_name} (estimated hours {estimated_hours}); the actual opening status needs a check.",
        "intervention.reason.adverse.both": "Weather and air quality are both poor; prioritize short-walk or indoor-friendly options near {candidate_name}.",
        "intervention.reason.adverse.air": "Air quality is poor; prioritize short-walk or indoor-friendly options near {candidate_name}.",
        "intervention.reason.weather.good": "Weather is suitable, so keep the current route toward {candidate_name}.",
        "intervention.reason.weather.unknown": "Weather data is still pending, so keep {candidate_name} as the current option.",
        "intervention.reason.weather.bad": "Weather is not ideal; prioritize short-walk or indoor-friendly options near {candidate_name}.",
        "intervention.action.estimated.both": "Weigh weather, air quality and the estimated hours together: check indoor options near {candidate_name}.",
        "intervention.action.estimated.air": "Weigh air quality and the estimated hours together: check indoor options near {candidate_name}.",
        "intervention.action.estimated.weather": "Weigh the weather and the estimated hours together: check indoor options near {candidate_name}.",
        "intervention.action.estimated.closing_soon": "Check the estimated closing time for {candidate_name} and review other nearby options too.",
        "intervention.action.estimated.closed": "Check nearby options covered by the estimated hours instead of {candidate_name}.",
        "intervention.action.adverse": "Show indoor or short-walk alternatives around {candidate_name}.",
        "intervention.action.weather.good": "Keep {candidate_name} as the primary local stop.",
        "intervention.action.weather.unknown": "Keep {candidate_name} while weather data is pending.",
    },
}

_WEATHER_ICON_KEYS = {
    "partly-cloudy": "partly_cloudy",
    "partly_cloudy": "partly_cloudy",
    "partly cloudy": "partly_cloudy",
    "cloudy": "cloudy",
    "clear": "clear",
    "sunny": "sunny",
    "rain": "rain",
    "sleet": "sleet",
    "snow": "snow",
}

_AIR_KEYS = {
    "좋음": "good",
    "good": "good",
    "보통": "normal",
    "normal": "normal",
    "moderate": "normal",
    "나쁨": "bad",
    "bad": "bad",
    "unhealthy": "bad",
    "매우나쁨": "very_bad",
    "very_bad": "very_bad",
    "very unhealthy": "very_bad",
    "실외": "outdoor",
    "outdoor": "outdoor",
    "실내": "indoor",
    "indoor": "indoor",
    "실내외": "indoor_outdoor",
    "indoor_outdoor": "indoor_outdoor",
    "indoor and outdoor": "indoor_outdoor",
}


def locale_code(language: str | None, *, default: str = "ko") -> str:
    return normalize_language(language, default=default)


def message(key: str, *, language: str = "ko", values: Mapping[str, object] | None = None) -> str:
    locale = locale_code(language)
    template = _MESSAGES.get(locale, {}).get(key) or _MESSAGES["ko"].get(key)
    if template is None:
        raise KeyError(key)
    return template.format(**dict(values or {}))


def category_label(category: str | None, *, language: str = "ko", title_case: bool = False) -> str:
    category_key = category_label_key(category, language=language)
    label = message(f"category.label.{category_key}", language=language)
    return label.capitalize() if title_case and language == "en" else label


def category_label_key(category: str | None, *, language: str = "ko") -> str:
    category_key = (category or "").strip() or "default"
    if f"category.label.{category_key}" not in _MESSAGES[locale_code(language)]:
        return "default"
    return category_key


def source_label(
    source: str | None, *, language: str = "ko", namespace: str = "evidence"
) -> str | None:
    source_key = (source or "").strip()
    if not source_key:
        return None
    return _MESSAGES[locale_code(language)].get(f"source.{namespace}.{source_key}")


def prompt_evidence_type(source: str | None) -> str | None:
    source_key = (source or "").strip()
    if not source_key:
        return None
    return _MESSAGES["en"].get(f"prompt.evidence_type.{source_key}")


def weather_icon_label(icon: str | None, *, language: str = "ko") -> str | None:
    icon_key = _WEATHER_ICON_KEYS.get((icon or "").strip().lower())
    if not icon_key:
        return None
    return message(f"weather.icon.{icon_key}", language=language)


def air_label(value: str | None, *, language: str = "ko") -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    if locale_code(language) != "en":
        return stripped
    if stripped.isascii():
        return stripped
    air_key = _AIR_KEYS.get(stripped)
    if not air_key:
        return stripped
    return message(f"weather.air.{air_key}", language=language)


def source_labels_by_locale(*, namespace: str, language: str) -> dict[str, str]:
    prefix = f"source.{namespace}."
    return {
        key.removeprefix(prefix): value
        for key, value in _MESSAGES[locale_code(language)].items()
        if key.startswith(prefix)
    }


def iter_catalog_keys() -> dict[str, set[str]]:
    return {locale: set(messages) for locale, messages in _MESSAGES.items()}


def docent_category_context(category: str | None, *, language: str) -> str:
    category_key = (category or "").strip() or "default"
    key = f"docent.category_context.{category_key}"
    if key not in _MESSAGES[locale_code(language)]:
        key = "docent.category_context.default"
    return message(key, language=language)


def docent_route_action(category: str | None, *, language: str) -> str:
    category_key = (category or "").strip() or "default"
    key = f"docent.route_action.{category_key}"
    if key not in _MESSAGES[locale_code(language)]:
        key = "docent.route_action.default"
    return message(key, language=language)


def format_intervention_template(
    key: str,
    *,
    language: str,
    values: Mapping[str, object],
) -> str:
    return message(f"intervention.{key}", language=language, values=values)
