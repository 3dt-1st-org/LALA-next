from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services import (
    db_repository,
    place_presentation,
    public_mvp_data,
)
from apps.api.app.services.normalization import normalize_language

_ALLOWED_CATEGORIES = {"all", "attraction", "restaurant", "event", "culture_venue"}

_INDOOR_PREFERRED_CATEGORIES = {"restaurant", "culture_venue"}

# Internal reason inputs are consumed by the composer and stripped before serialization.
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

    # current_time stays a UTC anchor: freshness is elapsed absolute time, so a
    # UTC anchor keeps it correct regardless of venue timezone.
    current_time = datetime.now(UTC)
    # Local DB-cached weather only — place search must never trigger the live
    # KMA/AirKorea provider. When nothing is cached the indoor-fit reason is
    # honestly omitted (current_weather stays {}); never fabricated.
    current_weather = db_repository.fetch_latest_weather(lat=lat, lng=lng) or {}

    enriched_places = _enrich_places(
        db_places,
        current_weather=current_weather,
        current_time=current_time,
        language=language,
        freshness_timestamp=lambda place: place.get("updated_at"),
    )

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
            snapshot_generated_at = public_mvp_data.snapshot_generated_at()
            enriched_public = _enrich_places(
                public_places,
                current_weather=current_weather,
                current_time=current_time,
                language=language,
                freshness_timestamp=lambda _place: snapshot_generated_at,
            )

            return {
                "count": len(enriched_public),
                "places": enriched_public
                if include_scores
                else _places_without_scores(enriched_public),
                "query": query_echo,
                "source": public_mvp_data.SOURCE_NAME,
                "location_engine": "static_snapshot",
                # Truthful snapshot build timestamp (or honest None if absent).
                "data_as_of": snapshot_generated_at,
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


def _enrich_places(
    places: list[dict],
    *,
    current_weather: dict,
    current_time: datetime,
    language: str,
    freshness_timestamp: Callable[[dict], str | datetime | None],
) -> list[dict]:
    enriched_places = []
    for place in places:
        enriched_place = dict(place)
        enriched_place["reason"] = _derive_place_reason(
            place=place,
            current_weather=current_weather,
            language=language,
        )
        enriched_place["freshness"] = _format_freshness(
            freshness_timestamp(place), current_time, language
        )
        _strip_internal_reason_inputs(enriched_place)
        enriched_places.append(enriched_place)
    return enriched_places


def _strip_internal_reason_inputs(place: dict) -> None:
    """Remove Lane-1 internal reason inputs so they never leave the service (§8)."""
    for key in _INTERNAL_REASON_KEYS:
        place.pop(key, None)


def _upstream_source_reason_phrase(upstream_source: str, *, language: str = "ko") -> str | None:
    """S1 provenance phrase; None for canonical/empty/unknown (contract D2).

    Replaces the old generic "공식 데이터" stamp: a phrase without a real source is
    less honest than silence.
    """
    return place_presentation.upstream_source_reason_phrase(upstream_source, language=language)


def _local_activity_reason_phrase(
    local_activity_band: str | None, *, language: str = "ko"
) -> str | None:
    """S2 binary activity hint from the SQL-projected band token (contract D1).

    Derives ONLY from the min-sample-gated band (Lane 1's token) — never from
    final_score or any component score (the number is unreachable from this phrase).
    """
    return place_presentation.local_activity_reason_phrase(local_activity_band, language=language)


def _weather_band_phrase(
    current_weather: dict, *, category: str, language: str = "ko"
) -> str | None:
    """S3 coarse weather band for the LIST reason (contract D3).

    Distinct granularity from RC3's publicWeatherSummary (band, not numbers), so it
    cannot diverge. The indoor-fit bit is retained only for indoor-pref ∧ bad weather.
    """
    return place_presentation.weather_band_phrase(
        current_weather, category=category, language=language
    )


def _linked_event_reason_phrase(
    has_linked_event: bool | None, *, is_ongoing: bool | None, language: str = "ko"
) -> str | None:
    """D4 linked/ongoing event phrase for ANY category (contract D4); None if none."""
    return place_presentation.linked_event_reason_phrase(
        has_linked_event, is_ongoing=is_ongoing, language=language
    )


def _derive_place_reason(*, place: dict, current_weather: dict, language: str = "ko") -> str:
    """Compose the normal-path reason — ONE ' · '-joined string (contract §3).

    Single SSOT for the reason text; no client recomputes or rewords it. Language
    follows the /places `language` param; en-branch selector (docent_service style)
    so unnormalized values fall back to ko, matching normalize_language's contract.
    Canonical segment order (head = most decision-useful, tail = first to ellipsize):
    [weather(S3)] · [activity(S2)] · [event(D4)] · [proximity] · [source(S1)]

    Honesty invariants (playbook §4.1/§4.2): phrases only — never the score number,
    formula, component value, or raw transactions. Each segment is independently
    null-gated; an all-null place yields "" (rendered as nothing, never "이유 없음").

    Operating status is deliberately ABSENT: the only hours source here is the
    category-level Korean-convention estimate (opening_hours_service), which is not
    a per-venue authority, so it must not produce any open-now claim — qualified or
    not. Comparing a UTC wall-clock slot against those estimates also mistook KST
    midnight for afternoon. Honest silence instead (removed legacy 영업중/Open now).
    """
    return place_presentation.derive_place_reason(
        place=place, current_weather=current_weather, language=language
    )


def _format_freshness(updated_at: str | None, now: datetime, language: str = "ko") -> str | None:
    """Format data freshness as human-readable relative time.

    Language follows the /places `language` param (same contract as
    _derive_place_reason): non-ko request languages get English strings so a
    visitor locale never renders Korean copy.

    Rules:
    - updated_at None → None (honest empty)
    - <1 minute → "방금 전" / "just now"
    - <1 hour → "N분 전" / "N min ago"
    - <1 day → "N시간 전" / "N hr ago"
    - ≥1 day → "N일 전" / "N days ago" (truthful elapsed days)
    - Parse errors → None (honest degradation)

    Returns:
        Localized freshness string or None.
    """
    return place_presentation.format_freshness(updated_at, now, language=language)
