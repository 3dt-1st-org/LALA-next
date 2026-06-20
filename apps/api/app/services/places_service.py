from __future__ import annotations

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services import db_repository, public_mvp_data
from apps.api.app.services.normalization import normalize_language

_ALLOWED_CATEGORIES = {"all", "attraction", "restaurant", "event", "culture_venue"}


def list_places(
    *,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    language: str,
) -> dict:
    category = (category or "all").strip().lower()
    language = normalize_language(language)
    if category not in _ALLOWED_CATEGORIES:
        raise ServiceError(
            status_code=400,
            code="INVALID_CATEGORY",
            message="category must be all|attraction|restaurant|event|culture_venue.",
            retryable=False,
        )
    db_places = db_repository.fetch_places(
        lat=lat,
        lng=lng,
        radius_m=radius_m,
        category=category,
        language=language,
    )
    if db_places:
        return {
            "count": len(db_places),
            "places": db_places,
            "query": {
                "lat": lat,
                "lng": lng,
                "radius_m": radius_m,
                "category": category,
                "language": language,
            },
            "source": "db",
        }

    if get_settings().static_snapshot_fallback:
        public_places = public_mvp_data.fetch_places(
            lat=lat,
            lng=lng,
            radius_m=radius_m,
            category=category,
            language=language,
        )
        if public_places:
            return {
                "count": len(public_places),
                "places": public_places,
                "query": {
                    "lat": lat,
                    "lng": lng,
                    "radius_m": radius_m,
                    "category": category,
                    "language": language,
                },
                "source": public_mvp_data.SOURCE_NAME,
            }

    return {
        "count": 0,
        "places": [],
        "query": {
            "lat": lat,
            "lng": lng,
            "radius_m": radius_m,
            "category": category,
            "language": language,
        },
        "source": "db",
    }
