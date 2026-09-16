from __future__ import annotations

import argparse
import contextlib
import os
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.core.runtime_secrets import get_runtime_profile, resolve_runtime_secret
from apps.api.app.services.job_runs import duration_ms


@dataclass(frozen=True)
class CliRunContext:
    mode: str
    started_at: datetime


def cli_mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


def cli_start(args: argparse.Namespace) -> CliRunContext:
    return CliRunContext(mode=cli_mode(args), started_at=datetime.now(UTC))


def mutually_exclusive_mode_error(args: argparse.Namespace) -> str:
    return "Use either --apply or --preview." if args.apply and args.preview else ""


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


def redact_cli_error(exc: Exception, *secrets: str | None) -> str:
    return redact_secret_text(
        str(exc) or exc.__class__.__name__,
        tuple(secret for secret in secrets if secret),
    )


def record_apply_job_failure(
    *,
    args: argparse.Namespace,
    dsn: str,
    job_name: str,
    started_at: datetime,
    error_message: str,
    connect_timeout: int,
    record_job_run: Callable[..., Any],
) -> None:
    if not args.apply:
        return
    finished_at = datetime.now(UTC)
    with contextlib.suppress(Exception):
        record_job_run(
            dsn=dsn,
            job_name=job_name,
            status="failed",
            started_at=started_at,
            finished_at=finished_at,
            duration_ms=duration_ms(started_at, finished_at),
            error_message=error_message,
            connect_timeout=connect_timeout,
        )


def record_apply_job_success(
    *,
    dsn: str,
    job_name: str,
    started_at: datetime,
    connect_timeout: int,
    record_job_run: Callable[..., Any],
    suppress_errors: bool = False,
) -> bool:
    finished_at = datetime.now(UTC)

    def _record() -> None:
        record_job_run(
            dsn=dsn,
            job_name=job_name,
            status="succeeded",
            started_at=started_at,
            finished_at=finished_at,
            duration_ms=duration_ms(started_at, finished_at),
            error_message=None,
            connect_timeout=connect_timeout,
        )

    if suppress_errors:
        with contextlib.suppress(Exception):
            _record()
            return True
        return False
    _record()
    return True
