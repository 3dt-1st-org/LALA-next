from __future__ import annotations

from functools import lru_cache


@lru_cache(maxsize=64)
def get_secret_if_configured(vault_url: str, secret_name: str) -> str:
    if not vault_url:
        return ""
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
