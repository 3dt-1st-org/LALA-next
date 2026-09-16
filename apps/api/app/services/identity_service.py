from __future__ import annotations

from contextlib import suppress

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

    def delete_account(self, issuer: str, subject: str, management_client) -> None:
        # Commit the local fence/job before contacting the external provider.
        self.mark_user_deleting(issuer, subject)
        self._resume_deletion(issuer, subject, management_client)

    def _resume_deletion(self, issuer: str, subject: str, management_client) -> None:
        try:
            phase = self._repository.deletion_phase(issuer, subject)
            if phase is None:
                return  # Already finalized by a concurrent request/reconciler.
            if phase != "external_deleted":
                # The provider treats 404 as success: a crash before recording
                # external success is recovered by repeating this operation.
                management_client.delete_user(subject)
                self._repository.mark_external_deleted(issuer, subject)
            self.finalize_user_deletion(issuer, subject)
        except Exception as exc:
            # The original durable job remains eligible if recording also fails.
            with suppress(IdentityRepositoryUnavailable):
                self._repository.record_deletion_failure(issuer, subject)
            if isinstance(exc, IdentityRepositoryUnavailable):
                raise _database_unavailable() from exc
            raise

    def reconcile_deletions(self, management_client, *, limit: int = 100) -> dict[str, int]:
        """Resume due jobs without requiring the deleted user's access token."""
        try:
            jobs = self._repository.pending_deletions(limit)
        except IdentityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        result = {"completed": 0, "failed": 0}
        for issuer, subject, _phase in jobs:
            try:
                self._resume_deletion(issuer, subject, management_client)
            except Exception:
                result["failed"] += 1
            else:
                result["completed"] += 1
        return result


def get_identity_service() -> IdentityService:
    return IdentityService(IdentityRepository(get_settings()))


def _database_unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="IDENTITY_DB_UNAVAILABLE",
        message="Local identity storage is temporarily unavailable.",
        retryable=True,
    )


if __name__ == "__main__":
    import argparse
    import json

    from apps.api.app.services.logto_management import get_logto_management_client

    parser = argparse.ArgumentParser(description="Resume durable account deletion jobs.")
    parser.add_argument("--reconcile-deletions", action="store_true", required=True)
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()
    outcome = get_identity_service().reconcile_deletions(
        get_logto_management_client(),
        limit=args.limit,
    )
    print(json.dumps(outcome))
    raise SystemExit(1 if outcome["failed"] else 0)
