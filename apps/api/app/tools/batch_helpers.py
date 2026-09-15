from __future__ import annotations

import argparse
import os

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.runtime_secrets import get_runtime_profile, resolve_runtime_secret


def apply_guard_error(
    args: argparse.Namespace,
    *,
    confirm_text: str,
    allow_env: str,
) -> str:
    if args.confirm != confirm_text:
        return f"--apply requires --confirm {confirm_text}."
    if os.getenv(allow_env) != "1":
        return f"--apply requires {allow_env}=1 in the process environment."
    return ""


def env_or_secret(env_name: str, secret_name: str) -> str:
    return resolve_runtime_secret(
        env_name,
        secret_name,
        key_vault_loader=lambda _url, name: get_secret_if_configured(
            (os.getenv("KEY_VAULT_URL") or "").strip(), name
        ),
        required=get_runtime_profile() in {"api", "worker"},
    )
