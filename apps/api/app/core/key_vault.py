from __future__ import annotations

import subprocess
import shutil
from functools import lru_cache
from urllib.parse import urlparse

ALLOWED_KEY_VAULT_HOSTS = {"lala-next-kv-27db5e.vault.azure.net"}


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
    return parsed.scheme == "https" and parsed.netloc.lower() in ALLOWED_KEY_VAULT_HOSTS


def key_vault_name_from_url(vault_url: str) -> str:
    if not is_allowed_key_vault_url(vault_url):
        return ""
    return urlparse(vault_url.strip()).netloc.split(".")[0]


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
