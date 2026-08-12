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

# D2 — S1 per-source provenance labels. Mirrors the KO branch of the client
# externalSourceLabel (home_view_helpers.dart); canonical/empty/unknown → omit.
_UPSTREAM_SOURCE_LABELS: dict[str, str] = {
    "tour_api": "한국관광공사",
    "kcisa": "문화정보원",
    "kopis": "공연예술통합전산망",
}

# Lane-1 internal reason inputs: projected into the place dict for the composer
# to read, then stripped before the /places response is serialized (§8).
_INTERNAL_REASON_KEYS = ("_local_activity_band", "_has_linked_event")


def list_places(
    *,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    language: str,
    sw_lat: float | None = None,
    sw_lng: float | None = None,
    ne_lat: float | None = None,
    ne_lng: float | None = None,
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
    # Bounds (contract §3 / §7 D3): validated and echoed only while the flag is on.
    # Flag-off ignores bounds entirely (B3: no 400, no echo, circle path) so a client
    # may start sending bounds before the rollout flips without breaking.
    # getattr: real Settings always carries feature_flags (config.py); the fallback
    # only covers incomplete test doubles that omit it, keeping their behavior intact.
    feature_flags = getattr(settings, "feature_flags", None) or {}
    bounds_values = (sw_lat, sw_lng, ne_lat, ne_lng)
    bounds_active = False
    if bool(feature_flags.get("PLACES_VIEWPORT_BOUNDS", False)) and any(
        value is not None for value in bounds_values
    ):
        if not all(value is not None for value in bounds_values):
            raise ServiceError(
                status_code=400,
                code="INVALID_BOUNDS",
                message="bounds must be all-or-none: sw_lat,sw_lng,ne_lat,ne_lng.",
                retryable=False,
            )
        if sw_lat > ne_lat or sw_lng > ne_lng:
            raise ServiceError(
                status_code=400,
                code="INVALID_BOUNDS",
                message="bounds require sw_lat<=ne_lat and sw_lng<=ne_lng.",
                retryable=False,
            )
        bounds_active = True
    try:
        db_places = db_repository.fetch_places(
            lat=lat,
            lng=lng,
            radius_m=radius_m,
            category=category,
            language=language,
            sw_lat=sw_lat,
            sw_lng=sw_lng,
            ne_lat=ne_lat,
            ne_lng=ne_lng,
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

    # Single source for the /places query echo: the existing 7 keys always, plus
    # the four optional bounds keys only while bounds mode is actually in effect
    # (B3: flag-off or bounds-absent stays byte-for-byte today's shape).
    query_echo = {
        "lat": lat,
        "lng": lng,
        "radius_m": radius_m,
        "category": category,
        "language": language,
        "include_scores": include_scores,
        "limit": limit,
    }
    if bounds_active:
        query_echo["sw_lat"] = sw_lat
        query_echo["sw_lng"] = sw_lng
        query_echo["ne_lat"] = ne_lat
        query_echo["ne_lng"] = ne_lng

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
        _strip_internal_reason_inputs(enriched_place)
        enriched_places.append(enriched_place)

    if enriched_places:
        return {
            "count": len(enriched_places),
            "places": enriched_places,
            "query": query_echo,
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
                _strip_internal_reason_inputs(enriched_place)
                enriched_public.append(enriched_place)

            return {
                "count": len(enriched_public),
                "places": enriched_public
                if include_scores
                else _places_without_scores(enriched_public),
                "query": query_echo,
                "source": public_mvp_data.SOURCE_NAME,
                "location_engine": "static_snapshot",
                # Truthful snapshot build timestamp (or honest None if absent).
                "data_as_of": public_mvp_data.snapshot_generated_at(),
            }

    return {
        "count": 0,
        "places": [],
        "query": query_echo,
        "source": "db",
        "location_engine": "postgis" if settings.db_dsn else "none",
        # No results → no data-as-of (honest absence).
        "data_as_of": None,
    }


def _places_without_scores(places: list[dict]) -> list[dict]:
    return [{**place, "score": None} for place in places]


def _strip_internal_reason_inputs(place: dict) -> None:
    """Remove Lane-1 internal reason inputs so they never leave the service (§8)."""
    for key in _INTERNAL_REASON_KEYS:
        place.pop(key, None)


def _upstream_source_reason_phrase(upstream_source: str) -> str | None:
    """S1 provenance phrase; None for canonical/empty/unknown (contract D2).

    Replaces the old generic "공식 데이터" stamp: a phrase without a real source is
    less honest than silence.
    """
    label = _UPSTREAM_SOURCE_LABELS.get((upstream_source or "").strip())
    return f"{label} 데이터" if label else None


def _local_activity_reason_phrase(local_activity_band: str | None) -> str | None:
    """S2 binary activity hint from the SQL-projected band token (contract D1).

    Derives ONLY from the min-sample-gated band (Lane 1's token) — never from
    final_score or any component score (the number is unreachable from this phrase).
    """
    # Lane 1 sets 'active' above the min-sample gate; any truthy token = active.
    return "로컬 소비 활발" if local_activity_band else None


def _weather_band_phrase(current_weather: dict, *, category: str) -> str | None:
    """S3 coarse weather band for the LIST reason (contract D3).

    Distinct granularity from RC3's publicWeatherSummary (band, not numbers), so it
    cannot diverge. The indoor-fit bit is retained only for indoor-pref ∧ bad weather.
    """
    if not current_weather:
        return None
    if current_weather.get("outdoor_status") == "bad":
        # A bare "bad weather" stamp on an outdoor attraction is not useful; honest silence.
        return "실내활동 적합" if category in _INDOOR_PREFERRED_CATEGORIES else None
    # Good/other weather → single comfort band from temp; unparseable temp → omit.
    try:
        temp_c = float(current_weather.get("temp"))
    except (TypeError, ValueError):
        return None
    if temp_c < 5:
        return "추운 날씨"
    if temp_c < 18:
        return "선선한 날씨"
    if temp_c < 27:
        return "따뜻한 날씨"
    return "더운 날씨"


def _linked_event_reason_phrase(
    has_linked_event: bool | None, *, is_ongoing: bool | None
) -> str | None:
    """D4 linked/ongoing event phrase for ANY category (contract D4); None if none."""
    if not has_linked_event:
        return None
    return "진행 중인 행사" if is_ongoing else "행사 연계"


def _derive_place_reason(*, place: dict, current_weather: dict, slot_time: str) -> str:
    """Compose the normal-path reason — ONE ' · '-joined KO string (contract §3).

    Single SSOT for the reason text; no client recomputes or rewords it. Canonical
    segment order (head = most decision-useful, tail = first to ellipsize):
    [operating] · [weather(S3)] · [activity(S2)] · [event(D4)] · [proximity] · [source(S1)]

    Honesty invariants (playbook §4.1/§4.2): phrases only — never the score number,
    formula, component value, or raw transactions. Each segment is independently
    null-gated; an all-null place yields "" (rendered as nothing, never "이유 없음").
    """
    reasons: list[str] = []
    category = place.get("category", "")

    # 1. Operating status (existing logic)
    open_time, close_time = opening_hours_service.estimated_opening_hours(category)
    is_open = opening_hours_service.is_within_hours(slot_time, open_time, close_time)
    if is_open is True:
        reasons.append("영업중")
    # closed (False) / unparseable slot (None) → omit operating (honest)

    # 2. Weather band (S3) — coarse phrase, never per-card numbers
    weather_phrase = _weather_band_phrase(current_weather, category=category)
    if weather_phrase:
        reasons.append(weather_phrase)

    # 3. Activity (S2) — binary hint from the SQL band token; never a number
    activity_phrase = _local_activity_reason_phrase(place.get("_local_activity_band"))
    if activity_phrase:
        reasons.append(activity_phrase)

    # 4. Linked/ongoing event (D4) — any category; internal key, stripped pre-serialize
    event_phrase = _linked_event_reason_phrase(
        place.get("_has_linked_event"),
        is_ongoing=place.get("is_ongoing"),
    )
    if event_phrase:
        reasons.append(event_phrase)

    # 5. Proximity (≤500m) — existing logic
    distance_m = place.get("distance_m", 0)
    if isinstance(distance_m, (int, float)) and distance_m <= 500:
        reasons.append("근접")
    # >500m → omit proximity (honest)

    # 6. Source provenance (S1) — per-source phrase; canonical/empty/unknown → omit
    source_phrase = _upstream_source_reason_phrase(place.get("upstream_source", ""))
    if source_phrase:
        reasons.append(source_phrase)

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
