from __future__ import annotations

import os
import shutil
import subprocess
from functools import lru_cache
from urllib.parse import urlparse

KEY_VAULT_HOST_SUFFIX = ".vault.azure.net"


@lru_cache(maxsize=64)
def get_secret_if_configured(vault_url: str, secret_name: str) -> str:
    if not vault_url:
        return ""
    if not is_allowed_key_vault_url(vault_url):
        return ""
    sdk_value = _get_secret_with_sdk(vault_url, secret_name)
    if sdk_value:
        return sdk_value
    return _get_secret_with_azure_cli(vault_url, secret_name)


def _get_secret_with_sdk(vault_url: str, secret_name: str) -> str:
    try:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient
    except Exception:
        return ""
    try:
        credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)
        client = SecretClient(vault_url=vault_url, credential=credential)
        secret = client.get_secret(secret_name)
        return (secret.value or "").strip()
    except Exception:
        return ""


def is_allowed_key_vault_url(vault_url: str) -> bool:
    parsed = urlparse(vault_url.strip())
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme != "https" or parsed.port is not None:
        return False
    if not _looks_like_lala_key_vault_host(host):
        return False
    allowed_hosts = _configured_allowed_key_vault_hosts()
    return not allowed_hosts or host in allowed_hosts


def key_vault_name_from_url(vault_url: str) -> str:
    if not is_allowed_key_vault_url(vault_url):
        return ""
    return (urlparse(vault_url.strip()).hostname or "").split(".")[0]


def _looks_like_lala_key_vault_host(host: str) -> bool:
    if not host.endswith(KEY_VAULT_HOST_SUFFIX):
        return False
    vault_name = host[: -len(KEY_VAULT_HOST_SUFFIX)]
    return bool(vault_name) and "onmu" not in vault_name


def _configured_allowed_key_vault_hosts() -> set[str]:
    raw = os.getenv("LALA_ALLOWED_KEY_VAULT_HOSTS", "")
    hosts = {_normalize_allowed_host(item) for item in raw.split(",")}
    return {host for host in hosts if host}


def _normalize_allowed_host(value: str) -> str:
    candidate = value.strip()
    if not candidate:
        return ""
    if "://" in candidate:
        parsed = urlparse(candidate)
        if parsed.scheme != "https" or parsed.port is not None:
            return ""
        candidate = parsed.hostname or ""
    else:
        candidate = candidate.split("/", 1)[0]
    return candidate.lower().rstrip(".")


def _get_secret_with_azure_cli(vault_url: str, secret_name: str) -> str:
    vault_name = key_vault_name_from_url(vault_url)
    if not vault_name:
        return ""
    az_executable = shutil.which("az.cmd") or shutil.which("az.exe") or shutil.which("az")
    if not az_executable:
        return ""
    try:
        completed = subprocess.run(
            [
                az_executable,
                "keyvault",
                "secret",
                "show",
                "--vault-name",
                vault_name,
                "--name",
                secret_name,
                "--query",
                "value",
                "-o",
                "tsv",
            ],
            capture_output=True,
            check=False,
            text=True,
            timeout=20,
        )
    except Exception:
        return ""
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()
