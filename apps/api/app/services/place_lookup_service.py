from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.places import validate_place_id
from apps.api.app.services import db_repository, public_mvp_data
from apps.api.app.services.normalization import normalize_language


@dataclass(frozen=True)
class PlaceLookupResult:
    places: list[dict[str, Any]]
    missing_place_ids: list[str]
    place_ids: list[str]
    language: str
    include_scores: bool
    source: str
    data_as_of: str | None


def lookup_places(
    *,
    place_ids: list[str],
    language: str,
    include_scores: bool,
) -> PlaceLookupResult:
    normalized_ids = _validated_unique_ids(place_ids)
    normalized_language = normalize_language(language)
    settings = get_settings()

    if settings.db_dsn:
        try:
            places = db_repository.fetch_places_by_ids(
                place_ids=normalized_ids,
                language=normalized_language,
                include_scores=include_scores,
            )
        except db_repository.DatabaseReadError as exc:
            if not settings.static_snapshot_fallback:
                raise _unavailable_error() from exc
        else:
            return _result(
                places=places,
                place_ids=normalized_ids,
                language=normalized_language,
                include_scores=include_scores,
                source="db",
                data_as_of=None,
            )
    elif not settings.static_snapshot_fallback:
        raise _unavailable_error()

    if public_mvp_data.snapshot_status() != "configured":
        raise _unavailable_error()

    places = public_mvp_data.fetch_places_by_ids(
        place_ids=normalized_ids,
        language=normalized_language,
        include_scores=include_scores,
    )
    return _result(
        places=places,
        place_ids=normalized_ids,
        language=normalized_language,
        include_scores=include_scores,
        source=public_mvp_data.SOURCE_NAME,
        data_as_of=public_mvp_data.snapshot_generated_at(),
    )


def require_place(
    *,
    place_id: str,
    language: str,
    include_scores: bool,
) -> tuple[dict[str, Any], PlaceLookupResult]:
    result = lookup_places(
        place_ids=[place_id],
        language=language,
        include_scores=include_scores,
    )
    if not result.places:
        raise ServiceError(
            status_code=404,
            code="PLACE_NOT_FOUND",
            message="The place ID is unknown in the selected public data source.",
            retryable=False,
        )
    return result.places[0], result


def _validated_unique_ids(place_ids: list[str]) -> list[str]:
    if not 1 <= len(place_ids) <= 100:
        raise ServiceError(
            status_code=422,
            code="VALIDATION_ERROR",
            message="Request validation failed.",
            retryable=False,
        )
    validated: list[str] = []
    try:
        for place_id in place_ids:
            if not isinstance(place_id, str):
                raise ValueError("place_id must be a string")
            validated.append(validate_place_id(place_id))
    except (TypeError, ValueError) as exc:
        raise ServiceError(
            status_code=422,
            code="VALIDATION_ERROR",
            message="Request validation failed.",
            retryable=False,
        ) from exc
    return list(dict.fromkeys(validated))


def _result(
    *,
    places: list[dict[str, Any]],
    place_ids: list[str],
    language: str,
    include_scores: bool,
    source: str,
    data_as_of: str | None,
) -> PlaceLookupResult:
    public_places = [_public_lookup_place(place) for place in places]
    found_ids = {str(place["place_id"]) for place in public_places}
    missing_place_ids = [place_id for place_id in place_ids if place_id not in found_ids]
    return PlaceLookupResult(
        places=public_places,
        missing_place_ids=missing_place_ids,
        place_ids=place_ids,
        language=language,
        include_scores=include_scores,
        source=source,
        data_as_of=data_as_of,
    )


def _public_lookup_place(place: dict[str, Any]) -> dict[str, Any]:
    payload = {key: value for key, value in place.items() if not key.startswith("_")}
    payload["distance_m"] = None
    payload["reason"] = None
    payload["freshness"] = None
    return payload


def _unavailable_error() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="PLACES_DB_UNAVAILABLE",
        message="Place lookup is temporarily unavailable.",
        retryable=True,
    )
