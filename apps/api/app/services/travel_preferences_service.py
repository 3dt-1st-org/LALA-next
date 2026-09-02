from __future__ import annotations

from typing import Any

from apps.api.app.core.errors import ServiceError
from apps.api.app.services.travel_preferences_repository import (
    TravelPreferencesRecord,
    TravelPreferencesRepository,
    TravelPreferencesRepositoryUnavailable,
    TravelPreferencesRevisionConflict,
    get_travel_preferences_repository,
)


class TravelPreferencesService:
    def __init__(self, repository: TravelPreferencesRepository) -> None:
        self._repository = repository

    def get(self, *, issuer: str, subject: str) -> TravelPreferencesRecord | None:
        try:
            return self._repository.get(issuer=issuer, subject=subject)
        except TravelPreferencesRepositoryUnavailable as exc:
            raise _unavailable() from exc

    def put(
        self,
        *,
        issuer: str,
        subject: str,
        expected_revision: int,
        preferences: dict[str, Any],
    ) -> TravelPreferencesRecord:
        try:
            return self._repository.put(
                issuer=issuer,
                subject=subject,
                expected_revision=expected_revision,
                preferences=preferences,
            )
        except TravelPreferencesRevisionConflict as exc:
            raise ServiceError(
                status_code=409,
                code="PREFERENCES_REVISION_CONFLICT",
                message="Travel preferences changed on another device.",
                retryable=False,
            ) from exc
        except TravelPreferencesRepositoryUnavailable as exc:
            raise _unavailable() from exc


def get_travel_preferences_service() -> TravelPreferencesService:
    return TravelPreferencesService(get_travel_preferences_repository())


def _unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="PREFERENCES_DB_UNAVAILABLE",
        message="Travel preferences are temporarily unavailable.",
        retryable=True,
    )
