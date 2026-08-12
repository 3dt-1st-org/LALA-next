from __future__ import annotations

from datetime import UTC, datetime

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services import (
    db_repository,
    opening_hours_service,
    public_mvp_data,
)
from apps.api.app.services.normalization import normalize_language

_ALLOWED_CATEGORIES = {"all", "attraction", "restaurant", "event", "culture_venue"}

_INDOOR_PREFERRED_CATEGORIES = {"restaurant", "culture_venue"}


def list_places(
    *,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    language: str,
    include_scores: bool = False,
    limit: int = 60,
) -> dict:
    category = (category or "all").strip().lower()
    language = normalize_language(language)
    settings = get_settings()
    if category not in _ALLOWED_CATEGORIES:
        raise ServiceError(
            status_code=400,
            code="INVALID_CATEGORY",
            message="category must be all|attraction|restaurant|event|culture_venue.",
            retryable=False,
        )
    try:
        db_places = db_repository.fetch_places(
            lat=lat,
            lng=lng,
            radius_m=radius_m,
            category=category,
            language=language,
            include_scores=include_scores,
            limit=limit,
        )
    except db_repository.DatabaseReadError as exc:
        if not settings.static_snapshot_fallback:
            raise ServiceError(
                status_code=503,
                code="PLACES_DB_UNAVAILABLE",
                message="Place recommendations are temporarily unavailable.",
                retryable=True,
            ) from exc
        db_places = []

    # Collect current signals for reason/freshness derivation
    current_time = datetime.now(UTC)
    # Local DB-cached weather only — place search must never trigger the live
    # KMA/AirKorea provider. When nothing is cached the indoor-fit reason is
    # honestly omitted (current_weather stays {}); never fabricated.
    current_weather = db_repository.fetch_latest_weather(lat=lat, lng=lng) or {}
    slot_time = current_time.strftime("%H:%M")

    # Enrich places with reason and freshness
    enriched_places = []
    for place in db_places:
        enriched_place = dict(place)
        reason = _derive_place_reason(
            place=place,
            current_weather=current_weather,
            slot_time=slot_time,
        )
        freshness = _format_freshness(place.get("updated_at"), current_time)

        enriched_place["reason"] = reason
        enriched_place["freshness"] = freshness
        enriched_places.append(enriched_place)

    if enriched_places:
        return {
            "count": len(enriched_places),
            "places": enriched_places,
            "query": {
                "lat": lat,
                "lng": lng,
                "radius_m": radius_m,
                "category": category,
                "language": language,
                "include_scores": include_scores,
                "limit": limit,
            },
            "source": "db",
            "location_engine": "postgis",
            # Honest absence: without a live DB max(updated_at) probe we must not
            # invent a data-as-of, so the UI shows no freshness label here.
            "data_as_of": None,
        }

    if settings.static_snapshot_fallback:
        public_places = public_mvp_data.fetch_places(
            lat=lat,
            lng=lng,
            radius_m=radius_m,
            category=category,
            language=language,
            limit=limit,
        )
        if public_places:
            # Enrich static places with reason/freshness
            enriched_public = []
            for place in public_places:
                enriched_place = dict(place)
                reason = _derive_place_reason(
                    place=place,
                    current_weather=current_weather,
                    slot_time=slot_time,
                )
                freshness = _format_freshness(public_mvp_data.snapshot_generated_at(), current_time)

                enriched_place["reason"] = reason
                enriched_place["freshness"] = freshness
                enriched_public.append(enriched_place)

            return {
                "count": len(enriched_public),
                "places": enriched_public
                if include_scores
                else _places_without_scores(enriched_public),
                "query": {
                    "lat": lat,
                    "lng": lng,
                    "radius_m": radius_m,
                    "category": category,
                    "language": language,
                    "include_scores": include_scores,
                    "limit": limit,
                },
                "source": public_mvp_data.SOURCE_NAME,
                "location_engine": "static_snapshot",
                # Truthful snapshot build timestamp (or honest None if absent).
                "data_as_of": public_mvp_data.snapshot_generated_at(),
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
            "include_scores": include_scores,
            "limit": limit,
        },
        "source": "db",
        "location_engine": "postgis" if settings.db_dsn else "none",
        # No results → no data-as-of (honest absence).
        "data_as_of": None,
    }


def _places_without_scores(places: list[dict]) -> list[dict]:
    return [{**place, "score": None} for place in places]


def _derive_place_reason(*, place: dict, current_weather: dict, slot_time: str) -> str:
    """Derive a deterministic, human-readable reason for a place recommendation.

    Rules (honest, signal-only, KO-only):
    - Operating status: "영업중" if open, "곧 닫음" if closing_soon, skip if closed
    - Weather fit: "실내활동 적합" only for indoor-pref categories + bad weather
    - Proximity: "근접" if ≤500m, skip otherwise
    - Source freshness: "공식 데이터" if official source, skip otherwise
    - Empty signals → honest empty string (never "이유 없음" or similar)

    Returns:
        A single-line Korean reason string, or empty string if no signals qualify.
    """
    reasons = []

    # 1. Operating status (highest priority)
    category = place.get("category", "")
    open_time, close_time = opening_hours_service.estimated_opening_hours(category)
    is_open = opening_hours_service.is_within_hours(slot_time, open_time, close_time)

    if is_open is True:
        reasons.append("영업중")
    elif is_open is False:
        # Closed: no operating reason (honest empty)
        pass
    # is_open is None: slot_time parsing failed, skip operating status

    # 2. Weather fit (indoor-pref categories + bad weather)
    if category in _INDOOR_PREFERRED_CATEGORIES:
        outdoor_status = current_weather.get("outdoor_status", "")
        if outdoor_status == "bad":
            reasons.append("실내활동 적합")
    # Good weather: no weather reason (honest)

    # 3. Proximity (≤500m)
    distance_m = place.get("distance_m", 0)
    if isinstance(distance_m, (int, float)) and distance_m <= 500:
        reasons.append("근접")
    # >500m: no proximity reason (honest)

    # 4. Source freshness
    upstream_source = place.get("upstream_source", "")
    if upstream_source and upstream_source != "canonical":
        reasons.append("공식 데이터")
    # canonical source: no source reason (honest)

    return " · ".join(reasons)


def _format_freshness(updated_at: str | None, now: datetime) -> str | None:
    """Format data freshness as human-readable relative time.

    Rules:
    - updated_at None → None (honest empty)
    - <1 minute → "방금 전"
    - <1 hour → "N분 전"
    - <1 day → "N시간 전"
    - ≥1 day → "N일 전" (truthful elapsed days; never the misleading "오늘")
    - Parse errors → None (honest degradation)

    Returns:
        Korean freshness string or None.
    """
    if not updated_at:
        return None

    try:
        if isinstance(updated_at, str):
            updated_at_dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        elif isinstance(updated_at, datetime):
            updated_at_dt = updated_at
        else:
            return None

        # Ensure timezone awareness
        if updated_at_dt.tzinfo is None:
            updated_at_dt = updated_at_dt.replace(tzinfo=UTC)

        diff = now - updated_at_dt
        total_seconds = diff.total_seconds()

        if total_seconds < 0:
            # Future timestamp (data corruption), treat as now
            return "방금 전"

        if total_seconds < 60:
            return "방금 전"
        elif total_seconds < 3600:
            minutes = int(total_seconds / 60)
            return f"{minutes}분 전"
        elif total_seconds < 86400:
            hours = int(total_seconds / 3600)
            return f"{hours}시간 전"
        else:
            days = int(total_seconds / 86400)
            return f"{days}일 전"

    except (ValueError, AttributeError):
        return None
