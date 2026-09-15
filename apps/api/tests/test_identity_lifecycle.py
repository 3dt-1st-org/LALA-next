"""Identity lifecycle regressions. Database cases only run against an explicit loopback DSN."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi import Request

from apps.api.app.core.auth import RequestIdentity, require_logto_identity, require_oauth_identity
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.identity_repository import (
    DeletedIdentityError,
    IdentityRepository,
    IdentityRepositoryUnavailable,
    PendingDeletionError,
    lock_active_actor,
)
from apps.api.app.services.identity_service import IdentityService
from apps.api.tests.local_database import local_test_dsn


@pytest.mark.parametrize("dependency", ["oauth", "logto"])
@pytest.mark.parametrize("state", ["active", "deleting", "deleted"])
def test_user_auth_provisions_first_user_and_rejects_inactive(dependency, state):
    service = Mock()
    if state != "active":
        service.provision_user.side_effect = ServiceError(
            status_code=409 if state == "deleting" else 410,
            code="ACCOUNT_DELETION_PENDING" if state == "deleting" else "ACCOUNT_DELETED",
            message="Account unavailable",
        )
    identity = RequestIdentity(mode="oauth", issuer="https://tenant.example/oidc", subject="first")

    def authorize():
        if dependency == "oauth":
            return require_oauth_identity(identity, service)
        return require_logto_identity(
            identity,
            Settings(logto_endpoint="https://tenant.example", logto_api_audience="api"),
            Request({"type": "http", "method": "PUT"}),
            service,
        )

    if state == "active":
        assert authorize() == identity
    else:
        with pytest.raises(ServiceError) as error:
            authorize()
        assert error.value.status_code == (409 if state == "deleting" else 410)
    service.provision_user.assert_called_once_with(identity.issuer, identity.subject)


def test_delete_dependency_allows_resuming_a_pending_job():
    def delete_me():
        pass

    service = Mock()
    identity = RequestIdentity(
        mode="oauth", issuer="https://tenant.example/oidc", subject="pending"
    )
    assert (
        require_logto_identity(
            identity,
            Settings(logto_endpoint="https://tenant.example", logto_api_audience="api"),
            Request(
                {"type": "http", "method": "DELETE", "route": SimpleNamespace(endpoint=delete_me)}
            ),
            service,
        )
        == identity
    )
    service.provision_user.assert_not_called()


@pytest.fixture
def local_repository():
    dsn = local_test_dsn()
    import psycopg2

    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(Path("sql/canonical/069_identity_deletion_jobs.sql").read_text())
    repository = IdentityRepository(Settings(db_dsn=dsn))
    issuer, subject = "https://identity-regression.example/oidc", str(uuid4())
    yield repository, issuer, subject
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM identity.users WHERE issuer=%s AND subject=%s", (issuer, subject))
        cur.execute(
            "DELETE FROM identity.deletion_jobs WHERE issuer=%s AND subject=%s", (issuer, subject)
        )
        from apps.api.app.services.identity_repository import _identity_digest

        cur.execute(
            "DELETE FROM identity.deleted_users WHERE identity_digest=%s",
            (_identity_digest(issuer, subject),),
        )


def test_transaction_guard_provisions_and_fences_missing_user_deletion(local_repository):
    repository, issuer, subject = local_repository
    with repository._cursor() as cur:
        lock_active_actor(cur, issuer, subject)
    assert repository.find_user(issuer, subject).status == "active"
    repository.mark_user_deleting(issuer, subject)
    with pytest.raises(ServiceError) as error:
        # Deliberately bypass repository exception translation for shared guard.
        import psycopg2

        with psycopg2.connect(repository._settings.db_dsn) as conn, conn.cursor() as cur:
            lock_active_actor(cur, issuer, subject)
    assert error.value.code == "ACCOUNT_DELETION_PENDING"
    repository.finalize_user_deletion(issuer, subject)
    with pytest.raises(DeletedIdentityError):
        repository.provision_user(issuer, subject)


def test_deletion_of_never_provisioned_identity_prevents_first_write(local_repository):
    repository, issuer, subject = local_repository
    assert repository.mark_user_deleting(issuer, subject) is None
    with pytest.raises(PendingDeletionError):
        repository.provision_user(issuer, subject)


@pytest.mark.parametrize("failure_stage", ["external", "record_external", "local_finalize"])
def test_reconciler_recovers_without_user_token_after_failures(
    local_repository, monkeypatch, failure_stage
):
    repository, issuer, subject = local_repository
    repository.provision_user(issuer, subject)
    service = IdentityService(repository)
    management = Mock()
    if failure_stage == "external":
        management.delete_user.side_effect = [RuntimeError("injected external failure"), None]
    else:
        method = (
            "mark_external_deleted"
            if failure_stage == "record_external"
            else "finalize_user_deletion"
        )
        original = getattr(repository, method)

        def fail_once(*args):
            monkeypatch.setattr(repository, method, original)
            raise IdentityRepositoryUnavailable("injected local failure")

        monkeypatch.setattr(repository, method, fail_once)
    with pytest.raises(RuntimeError if failure_stage == "external" else ServiceError):
        service.delete_account(issuer, subject, management)
    assert repository.find_user(issuer, subject).status == "deleting"
    assert repository.deletion_phase(issuer, subject) == (
        "external_deleted" if failure_stage == "local_finalize" else "pending_external"
    )
    # Make the scheduled retry due without sleeping. A fresh service simulates restart.
    with repository._cursor() as cur:
        cur.execute(
            "UPDATE identity.deletion_jobs SET next_attempt_at=now() WHERE issuer=%s AND subject=%s",
            (issuer, subject),
        )
    outcome = IdentityService(repository).reconcile_deletions(management)
    assert outcome["completed"] >= 1
    assert outcome["failed"] == 0
    assert repository.find_user(issuer, subject) is None
    assert repository.deletion_phase(issuer, subject) is None
    assert management.delete_user.call_count == (1 if failure_stage == "local_finalize" else 2)
    with pytest.raises(DeletedIdentityError):
        repository.provision_user(issuer, subject)


def test_write_lock_serializes_deletion_until_transaction_commits(local_repository):
    repository, issuer, subject = local_repository
    started = Event()

    def delete():
        started.set()
        repository.mark_user_deleting(issuer, subject)

    with ThreadPoolExecutor(max_workers=1) as executor:
        with repository._cursor() as cur:
            lock_active_actor(cur, issuer, subject)
            future = executor.submit(delete)
            assert started.wait(2)
            # Observe the second backend waiting on the advisory lock, rather
            # than relying on a sleep to infer that deletion was serialized.
            import time

            import psycopg2

            deadline = time.monotonic() + 3
            waiting = False
            while time.monotonic() < deadline:
                with (
                    psycopg2.connect(repository._settings.db_dsn) as observer,
                    observer.cursor() as check,
                ):
                    check.execute(
                        "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE wait_event='advisory' AND datname=current_database())"
                    )
                    waiting = check.fetchone()[0]
                if waiting:
                    break
            assert waiting
            assert not future.done()
        future.result(timeout=3)
    assert repository.find_user(issuer, subject).status == "deleting"


def test_first_authenticated_plan_write_and_deleted_token_are_fenced(client, local_repository):
    from apps.api.app.core.auth import require_client_auth
    from apps.api.app.core.config import get_settings
    from apps.api.app.services.identity_service import get_identity_service
    from apps.api.app.services.logto_management import get_logto_management_client
    from apps.api.app.services.planning_repository import (
        PlanningRepository,
        get_planning_repository,
    )

    repository, issuer, subject = local_repository
    settings = Settings(
        db_dsn=repository._settings.db_dsn,
        logto_endpoint=issuer.removesuffix("/oidc"),
        logto_api_audience="api",
    )
    client.app.dependency_overrides[require_client_auth] = lambda: RequestIdentity(
        mode="oauth",
        issuer=issuer,
        subject=subject,
    )
    client.app.dependency_overrides[get_settings] = lambda: settings
    client.app.dependency_overrides[get_identity_service] = lambda: IdentityService(repository)
    client.app.dependency_overrides[get_planning_repository] = lambda: PlanningRepository(settings)
    management = Mock()
    client.app.dependency_overrides[get_logto_management_client] = lambda: management
    assert repository.find_user(issuer, subject) is None
    response = client.put("/api/v1/me/plans/2026-09-15", json={"plan": {"slots": []}})
    assert response.status_code == 200, response.text
    repository.mark_user_deleting(issuer, subject)
    pending = client.put("/api/v1/me/plans/2026-09-15", json={"plan": {"slots": []}})
    assert pending.status_code == 409
    assert pending.json()["error"]["code"] == "ACCOUNT_DELETION_PENDING"
    deleted = client.request("DELETE", "/api/v1/me", json={"confirmation": "delete-my-account"})
    assert deleted.status_code == 204, deleted.text
    management.delete_user.assert_called_once_with(subject)
    blocked = client.put("/api/v1/me/plans/2026-09-15", json={"plan": {"slots": []}})
    assert blocked.status_code == 410
    # Repeated delete remains successful even after external credentials disappear.
    assert (
        client.request(
            "DELETE", "/api/v1/me", json={"confirmation": "delete-my-account"}
        ).status_code
        == 204
    )
    management.delete_user.assert_called_once_with(subject)
