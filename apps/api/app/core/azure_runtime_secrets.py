"""Managed-identity-only Key Vault lookup for operational runtimes."""

from __future__ import annotations

import logging
import os
import re
from collections import OrderedDict
from collections.abc import Mapping
from dataclasses import dataclass, field
from functools import lru_cache
from threading import Lock
from time import monotonic
from urllib.parse import urlsplit


@dataclass(frozen=True)
class AzureSecretLookupResult:
    outcome: str
    logical_name: str
    value: str = field(default="", repr=False)

    def to_dict(self) -> dict[str, str]:
        return {"outcome": self.outcome, "logical_name": self.logical_name}


# Settings is resolved on request paths too. Bound Key Vault traffic and the
# lifetime of cached credentials; never serve an expired value after a failure.
_cache: OrderedDict[tuple[str, str, str], tuple[float, AzureSecretLookupResult]] = OrderedDict()
_cache_lock = Lock()
_SUCCESS_TTL = 300
_FAILURE_TTL = 15
_CACHE_LIMIT = 256


def _allowed_url(env: Mapping[str, str]) -> str:
    raw = (env.get("KEY_VAULT_URL") or "").strip()
    allowed = {
        host.strip().lower()
        for host in (env.get("LALA_ALLOWED_KEY_VAULT_HOSTS") or "").split(",")
        if host.strip()
    }
    try:
        parsed = urlsplit(raw)
        host = (parsed.hostname or "").lower()
        if (
            parsed.scheme != "https"
            or parsed.port is not None
            or parsed.username is not None
            or parsed.password is not None
            or parsed.path not in {"", "/"}
            or parsed.query
            or parsed.fragment
            or not re.fullmatch(r"[a-z][a-z0-9-]{1,22}[a-z0-9]\.vault\.azure\.net", host)
            or "--" in host
            or "onmu" in host
            or host not in allowed
        ):
            return ""
    except ValueError:
        return ""
    return f"https://{host}"


@lru_cache(maxsize=8)
def _client(vault_url: str, client_id: str):
    from azure.identity import ManagedIdentityCredential
    from azure.keyvault.secrets import SecretClient

    # Provider diagnostics can contain resource identifiers or response bodies.
    # The resolver returns safe outcome categories instead.
    for name in ("azure.core", "azure.identity", "azure.keyvault"):
        logging.getLogger(name).setLevel(logging.CRITICAL)
    options = {"connection_timeout": 5, "read_timeout": 10, "retry_total": 1}
    credential = ManagedIdentityCredential(
        **({"client_id": client_id} if client_id else {}), **options
    )
    return SecretClient(vault_url=vault_url, credential=credential, logging_enable=False, **options)


def get_azure_runtime_secret_structured(
    logical_name: str, *, environ: Mapping[str, str] | None = None
) -> AzureSecretLookupResult:
    env = environ if environ is not None else os.environ
    vault_url = _allowed_url(env)
    if not vault_url:
        return AzureSecretLookupResult("invalid", logical_name)
    client_id = (env.get("AZURE_CLIENT_ID") or "").strip()
    key = (vault_url, client_id, logical_name)
    with _cache_lock:
        cached = _cache.get(key)
        if cached is not None and monotonic() < cached[0]:
            _cache.move_to_end(key)
            return cached[1]
        result = _lookup(vault_url, client_id, logical_name)
        ttl = _SUCCESS_TTL if result.outcome == "found" else _FAILURE_TTL
        _cache[key] = (monotonic() + ttl, result)
        _cache.move_to_end(key)
        while len(_cache) > _CACHE_LIMIT:
            _cache.popitem(last=False)
        return result


def _lookup(vault_url: str, client_id: str, logical_name: str) -> AzureSecretLookupResult:
    try:
        client = _client(vault_url, client_id)
        secret = client.get_secret(logical_name, logging_enable=False)
        value = secret.value
    except Exception as exc:
        status = getattr(exc, "status_code", None)
        if status == 404:
            outcome = "missing"
        elif status in {401, 403}:
            outcome = "denied"
        else:
            outcome = "unavailable"
        return AzureSecretLookupResult(outcome, logical_name)
    if not isinstance(value, str) or not value.strip():
        return AzureSecretLookupResult("invalid", logical_name)
    return AzureSecretLookupResult("found", logical_name, value.strip())
