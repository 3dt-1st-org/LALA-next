from __future__ import annotations

from dataclasses import dataclass

from fastapi import Request

from apps.api.app.core.auth import RequestIdentity
from apps.api.app.services.identity_repository import LocalUser


@dataclass(frozen=True)
class CurrentAccountContext:
    identity: RequestIdentity
    user: LocalUser

    @property
    def issuer(self) -> str:
        return self.identity.issuer or ""

    @property
    def subject(self) -> str:
        return self.identity.subject or ""


def get_request_account_context(request: Request) -> CurrentAccountContext | None:
    value = getattr(request.state, "current_account", None)
    if isinstance(value, CurrentAccountContext):
        return value
    return None


def set_request_account_context(
    request: Request,
    *,
    identity: RequestIdentity,
    user: LocalUser,
) -> CurrentAccountContext:
    context = CurrentAccountContext(identity=identity, user=user)
    request.state.current_account = context
    return context
