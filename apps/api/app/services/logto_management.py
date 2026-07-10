from __future__ import annotations

from typing import Any
from urllib.parse import quote, urlsplit, urlunsplit

import httpx

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError


REQUEST_TIMEOUT_SECONDS = 5.0


class LogtoManagementError(ServiceError):
    pass


class LogtoManagementUnavailable(LogtoManagementError):
    def __init__(self) -> None:
        super().__init__(
            status_code=503,
            code="LOGTO_MANAGEMENT_UNAVAILABLE",
            message="Account deletion service is temporarily unavailable.",
            retryable=True,
        )


class LogtoManagementRejected(LogtoManagementError):
    def __init__(self, *, code: str = "LOGTO_MANAGEMENT_REJECTED") -> None:
        super().__init__(
            status_code=503,
            code=code,
            message="Account deletion service cannot process this request.",
            retryable=False,
        )


class LogtoManagementClient:
    def __init__(self, settings: Settings, *, client: httpx.Client | Any | None = None) -> None:
        self._settings = settings
        self._client = client
        self._endpoint = _management_endpoint(
            settings.logto_management_endpoint or settings.logto_endpoint
        )

    def delete_user(self, subject: str) -> None:
        self._validate_configuration()
        if self._client is not None:
            self._delete_with_client(self._client, subject)
            return
        with httpx.Client(timeout=httpx.Timeout(REQUEST_TIMEOUT_SECONDS)) as client:
            self._delete_with_client(client, subject)

    def _delete_with_client(self, client: httpx.Client | Any, subject: str) -> None:
        token_response = self._request(
            client,
            "POST",
            f"{self._endpoint}/oidc/token",
            data={
                "grant_type": "client_credentials",
                "resource": f"{self._endpoint}/api",
                "scope": "all",
            },
            auth=(
                self._settings.logto_management_client_id,
                self._settings.logto_management_client_secret,
            ),
        )
        token = _access_token(token_response)
        user_id = quote(subject, safe="")
        headers = {"Authorization": f"Bearer {token}"}

        grants_response = self._request(
            client,
            "GET",
            f"{self._endpoint}/api/users/{user_id}/grants",
            headers=headers,
            params={"appType": "firstParty"},
            allow_not_found=True,
        )
        if grants_response is None:
            return
        for grant_id in _resource_ids(grants_response):
            self._request(
                client,
                "DELETE",
                f"{self._endpoint}/api/users/{user_id}/grants/{quote(grant_id, safe='')}",
                headers=headers,
                allow_not_found=True,
            )

        sessions_response = self._request(
            client,
            "GET",
            f"{self._endpoint}/api/users/{user_id}/sessions",
            headers=headers,
            allow_not_found=True,
        )
        if sessions_response is None:
            return
        for session_id in _resource_ids(sessions_response):
            self._request(
                client,
                "DELETE",
                f"{self._endpoint}/api/users/{user_id}/sessions/{quote(session_id, safe='')}",
                headers=headers,
                allow_not_found=True,
            )

        self._request(
            client,
            "DELETE",
            f"{self._endpoint}/api/users/{user_id}",
            headers=headers,
            allow_not_found=True,
        )

    def _validate_configuration(self) -> None:
        if logto_management_configuration_status(self._settings) != "configured":
            raise LogtoManagementRejected(code="LOGTO_MANAGEMENT_NOT_CONFIGURED")

    def _request(self, client, method: str, url: str, *, allow_not_found: bool = False, **kwargs):
        try:
            response = client.request(method, url, **kwargs)
        except httpx.RequestError as exc:
            raise LogtoManagementUnavailable() from exc
        except Exception as exc:
            raise LogtoManagementUnavailable() from exc
        if 200 <= response.status_code < 300:
            return response
        if allow_not_found and response.status_code == 404:
            return None
        if response.status_code in {408, 429} or response.status_code >= 500:
            raise LogtoManagementUnavailable()
        raise LogtoManagementRejected()


def get_logto_management_client() -> LogtoManagementClient:
    return LogtoManagementClient(get_settings())


def logto_management_configuration_status(settings: Settings) -> str:
    endpoint_value = settings.logto_management_endpoint or settings.logto_endpoint
    values_present = (
        bool(endpoint_value),
        bool(settings.logto_management_client_id),
        bool(settings.logto_management_client_secret),
    )
    if (
        _management_endpoint(endpoint_value)
        and settings.logto_management_client_id
        and settings.logto_management_client_secret
    ):
        return "configured"
    return "partial" if any(values_present) else "skipped"


def _management_endpoint(value: str) -> str:
    try:
        parsed = urlsplit(value)
    except ValueError:
        return ""
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        return ""
    return urlunsplit((parsed.scheme.lower(), parsed.netloc, "", "", ""))


def _access_token(response) -> str:
    try:
        payload = response.json()
    except Exception as exc:
        raise LogtoManagementRejected() from exc
    token = payload.get("access_token") if isinstance(payload, dict) else None
    if not isinstance(token, str) or not token:
        raise LogtoManagementRejected()
    return token


def _resource_ids(response) -> list[str]:
    try:
        payload = response.json()
    except Exception as exc:
        raise LogtoManagementRejected() from exc
    if not isinstance(payload, list):
        raise LogtoManagementRejected()
    return [
        item["id"]
        for item in payload
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    ]
