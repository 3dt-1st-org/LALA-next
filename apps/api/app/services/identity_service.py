from __future__ import annotations

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.identity_repository import (
    DeletedIdentityError,
    IdentityRepository,
    IdentityRepositoryUnavailable,
    LocalUser,
    PendingDeletionError,
)


class IdentityService:
    def __init__(self, repository: IdentityRepository) -> None:
        self._repository = repository

    def provision_user(self, issuer: str, subject: str) -> LocalUser:
        try:
            return self._repository.provision_user(issuer, subject)
        except DeletedIdentityError as exc:
            raise ServiceError(
                status_code=410,
                code="ACCOUNT_DELETED",
                message="This account has been deleted.",
                retryable=False,
            ) from exc
        except PendingDeletionError as exc:
            raise ServiceError(
                status_code=409,
                code="ACCOUNT_DELETION_PENDING",
                message="Account deletion is already in progress.",
                retryable=False,
            ) from exc
        except IdentityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc

    def mark_user_deleting(self, issuer: str, subject: str) -> LocalUser | None:
        try:
            return self._repository.mark_user_deleting(issuer, subject)
        except IdentityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc

    def finalize_user_deletion(self, issuer: str, subject: str) -> bool:
        try:
            return self._repository.finalize_user_deletion(issuer, subject)
        except IdentityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc


def get_identity_service() -> IdentityService:
    return IdentityService(IdentityRepository(get_settings()))


def _database_unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="IDENTITY_DB_UNAVAILABLE",
        message="Local identity storage is temporarily unavailable.",
        retryable=True,
    )
