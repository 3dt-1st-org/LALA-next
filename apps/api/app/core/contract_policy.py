from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

CLIENT_AUTH_SECURITY = [{}, {"BearerAuth": []}, {"MigrationApiKey": []}]
OAUTH_SECURITY = [{"OAuthBearerAuth": []}]

AuthPolicy = Literal["client", "oauth"]
ErrorPolicy = Literal[
    "standard", "account", "local_signal_read", "local_signal_write", "community_write"
]


@dataclass(frozen=True)
class OperationContractPolicy:
    auth: AuthPolicy
    error_policy: ErrorPolicy = "standard"
    timeout_seconds: int | None = None
    success_schema: str | None = None
    remove_generated_auth_parameters: bool = False
    account_include_conflict: bool = False

    @property
    def auth_required(self) -> bool:
        return self.auth == "oauth"

    @property
    def security(self) -> list[dict[str, list]]:
        return OAUTH_SECURITY if self.auth == "oauth" else CLIENT_AUTH_SECURITY


EXACT_PATH_POLICIES: dict[str, OperationContractPolicy] = {
    "/healthz": OperationContractPolicy(
        auth="client",
        timeout_seconds=3,
        success_schema="HealthzSuccessEnvelope",
    ),
    "/metrics": OperationContractPolicy(auth="client", timeout_seconds=3),
    "/readyz": OperationContractPolicy(
        auth="client",
        timeout_seconds=3,
        success_schema="ReadyzSuccessEnvelope",
    ),
    "/api/v1/places": OperationContractPolicy(
        auth="client",
        timeout_seconds=12,
        success_schema="PlacesSuccessEnvelope",
    ),
    "/api/v1/places/lookup": OperationContractPolicy(
        auth="client",
        timeout_seconds=12,
        success_schema="PlaceBatchLookupSuccessEnvelope",
    ),
    "/api/v1/places/{place_id}": OperationContractPolicy(
        auth="client",
        timeout_seconds=12,
        success_schema="PlaceLookupSuccessEnvelope",
    ),
    "/api/v1/weather": OperationContractPolicy(
        auth="client",
        timeout_seconds=12,
        success_schema="WeatherSuccessEnvelope",
    ),
    "/api/v1/docents/script": OperationContractPolicy(
        auth="client",
        timeout_seconds=30,
        success_schema="DocentScriptSuccessEnvelope",
    ),
    "/api/v1/docents/audio": OperationContractPolicy(auth="client", timeout_seconds=30),
    "/api/v1/plans/daily": OperationContractPolicy(
        auth="client",
        timeout_seconds=20,
        success_schema="DailyPlanSuccessEnvelope",
    ),
    "/api/v1/plans/intervention": OperationContractPolicy(
        auth="client",
        timeout_seconds=12,
        success_schema="InterventionSuccessEnvelope",
    ),
    "/api/v1/me": OperationContractPolicy(
        auth="oauth",
        error_policy="account",
        timeout_seconds=12,
        success_schema="MeSuccessEnvelope",
        remove_generated_auth_parameters=True,
        account_include_conflict=True,
    ),
}

COMMUNITY_MUTATION_PATHS = frozenset(
    {
        "/api/v1/community/posts",
        "/api/v1/community/posts/{post_id}/comments",
        "/api/v1/community/posts/{post_id}/like",
        "/api/v1/community/posts/{post_id}/reports",
        "/api/v1/community/follows",
        "/api/v1/community/chat/rooms",
        "/api/v1/community/chat/rooms/{room_id}/messages",
        "/api/v1/community/chat/rooms/{room_id}/ws-ticket",
        "/api/v1/community/chat/rooms/{room_id}/members",
    }
)


def policy_for_operation(path: str, method: str) -> OperationContractPolicy:
    exact = EXACT_PATH_POLICIES.get(path)
    if exact is not None:
        if path == "/api/v1/me" and method.lower() != "get":
            return OperationContractPolicy(
                auth="oauth",
                error_policy="account",
                timeout_seconds=12,
                success_schema=exact.success_schema,
                remove_generated_auth_parameters=True,
                account_include_conflict=False,
            )
        return exact
    if path.startswith("/api/v1/me/"):
        return OperationContractPolicy(
            auth="oauth",
            timeout_seconds=12,
            remove_generated_auth_parameters=True,
        )
    if _is_local_signal_path(path):
        write = method.lower() != "get"
        return OperationContractPolicy(
            auth="oauth" if write else "client",
            error_policy="local_signal_write" if write else "local_signal_read",
            timeout_seconds=12,
            remove_generated_auth_parameters=write,
        )
    if path in COMMUNITY_MUTATION_PATHS and method.lower() == "post":
        return OperationContractPolicy(auth="client", error_policy="community_write")
    return OperationContractPolicy(auth="client")


def _is_local_signal_path(path: str) -> bool:
    return path.startswith("/api/v1/community/signals") or path.startswith(
        "/api/v1/community/places/"
    )
