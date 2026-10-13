"""Validate manual rollout inputs locally; no SDK, credentials, or network calls."""

from __future__ import annotations

import os
import re
from collections.abc import Mapping


def validate(environ: Mapping[str, str]) -> None:
    def require(name: str, pattern: str | None = None) -> str:
        value = environ.get(name, "")
        if not value or (pattern is not None and re.fullmatch(pattern, value) is None):
            raise ValueError(f"Missing or invalid {name}.")
        return value

    require("AZURE_MANAGED_INFRA_READY", "true")
    target = require("ROLLOUT_TARGET", "staging|prod")
    sha = require("SOURCE_SHA", r"[0-9a-f]{40}")
    require("AZURE_RESOURCE_GROUP", r"[\w.()\-]{1,90}")
    require("AZURE_CONTAINER_APP_NAME", r"[a-z][a-z0-9-]{0,30}[a-z0-9]")
    require("AZURE_REGISTRY_NAME", r"[A-Za-z0-9]{5,50}")
    if target == "prod":
        if require("AZURE_STAGING_VERIFIED_SHA", r"[0-9a-f]{40}") != sha:
            raise ValueError("Production source does not match staging acceptance.")
        require(
            "AZURE_STAGING_VERIFIED_IMAGE",
            r"[a-z0-9-]+\.azurecr\.io/lala-api@sha256:[0-9a-f]{64}",
        )
        require(
            "AZURE_STAGING_REGISTRY_ID",
            r"/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[\w.()\-]{1,90}"
            r"/providers/Microsoft.ContainerRegistry/registries/[A-Za-z0-9]{5,50}",
        )


def main() -> int:
    try:
        validate(os.environ)
    except ValueError as exc:
        print(str(exc))  # Logical setting names only, never their values.
        return 1
    print("Rollout inputs valid; no cloud action performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
