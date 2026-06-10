from __future__ import annotations

from apps.api.app.core.errors import ServiceError

_ALLOWED_CATEGORIES = {"all", "attraction", "restaurant", "event"}
_ALLOWED_LANGUAGES = {"ko", "en"}


def list_places(
    *,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    language: str,
) -> dict:
    category = (category or "all").strip().lower()
    language = (language or "ko").strip().lower()
    if category not in _ALLOWED_CATEGORIES:
        raise ServiceError(
            status_code=400,
            code="INVALID_CATEGORY",
            message="category must be all|attraction|restaurant|event.",
            retryable=False,
        )
    if language not in _ALLOWED_LANGUAGES:
        language = "ko"

    resolved_category = "attraction" if category == "all" else category
    name = "Suwon Hwaseong" if language == "en" else "수원화성"
    address = "Suwon-si, Gyeonggi-do" if language == "en" else "경기도 수원시"
    place = {
        "place_id": "skeleton-suwon-hwaseong",
        "name": name,
        "name_ko": "수원화성",
        "name_en": "Suwon Hwaseong",
        "category": resolved_category,
        "lat": lat,
        "lng": lng,
        "address": address,
        "distance_m": min(radius_m, 1000),
        "source": "skeleton",
    }
    return {
        "count": 1,
        "places": [place],
        "query": {
            "lat": lat,
            "lng": lng,
            "radius_m": radius_m,
            "category": category,
            "language": language,
        },
        "source": "skeleton",
    }

