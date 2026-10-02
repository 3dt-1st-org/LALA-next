"""Isolated desktop DB/API runner. Never imports cloud credentials or repo dotenv."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys
import urllib.request
from pathlib import Path
from urllib.parse import urlunsplit

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / "runtime" / "desktop-dev"
CONFIG = STATE / "database.json"


def environment() -> dict[str, str]:
    # Keep only OS/runtime paths; inherited DB, AWS and paid-provider settings
    # must never leak into this local development process.
    allowed = {
        "path",
        "systemroot",
        "windir",
        "comspec",
        "pathext",
        "temp",
        "tmp",
        "userprofile",
        "home",
        "localappdata",
        "appdata",
        "programdata",
        "programfiles",
        "programfiles(x86)",
        "systemdrive",
    }
    env = {k: v for k, v in os.environ.items() if k.lower() in allowed}
    env.update(
        LALA_RUNTIME_PROFILE="local",
        LALA_LOCAL_ENV_FILE=str(STATE / "empty.env"),
        LALA_LOCAL_USE_AWS_SECRETS="false",  # pragma: allowlist secret
        AWS_EC2_METADATA_DISABLED="true",
        LALA_GUEST_ACCESS="true",
        LALA_STATIC_SNAPSHOT_FALLBACK="false",
        LALA_ENABLE_LIVE_AI="false",
        LALA_ENABLE_LIVE_SPEECH="false",
        CORS_ALLOW_ORIGINS="http://127.0.0.1:8765,http://localhost:8765",
        PYTHONIOENCODING="utf-8",
        PYTHONPATH=str(ROOT),
    )
    return env


def run(args: list[str], env: dict[str, str], *, timeout: int = 600) -> str:
    result = subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    if result.returncode:
        # Tool failures may contain DSNs, so keep stdout/stderr private.
        raise RuntimeError(
            f"{Path(args[0]).name} failed (exit {result.returncode}); output withheld"
        )
    return result.stdout


def database_env(*, create: bool = False) -> dict[str, str]:
    if not CONFIG.exists():
        if not create:
            raise RuntimeError("Run setup first.")
        STATE.mkdir(parents=True, exist_ok=True)
        CONFIG.write_text(json.dumps({"password": secrets.token_hex(24)}), encoding="utf-8")
    password = json.loads(CONFIG.read_text(encoding="utf-8"))["password"]
    if (
        not isinstance(password, str)
        or len(password) != 48
        or any(char not in "0123456789abcdef" for char in password)
    ):
        raise RuntimeError("Invalid local credential file; no DB operation performed.")
    (STATE / "empty.env").touch(exist_ok=True)
    env = environment()
    env.update(
        LALA_POSTGRES_USER="lala_desktop",
        LALA_POSTGRES_PASSWORD=password,
        LALA_POSTGRES_DB="lala_desktop",
        LALA_POSTGRES_PORT="55433",
        DB_DSN=urlunsplit(
            ("postgresql", f"lala_desktop:{password}@127.0.0.1:55433", "/lala_desktop", "", "")
        ),
    )
    return env


def setup() -> None:
    env = database_env(create=True)
    # Explicit context prevents DOCKER_HOST or the current context selecting a remote host.
    docker = ["docker", "--context", "desktop-linux"]
    run(docker + ["info", "--format", "{{.ServerVersion}}"], env, timeout=30)
    run(
        docker
        + [
            "compose",
            "--env-file",
            str(STATE / "empty.env"),
            "--project-name",
            "lala-desktop-dev",
            "-f",
            "compose.local.yml",
            "-f",
            "compose.desktop-dev.yml",
            "up",
            "-d",
            "--wait",
            "--wait-timeout",
            "120",
            "postgres",
        ],
        env,
    )
    print("Local PostgreSQL healthy (127.0.0.1:55433).", flush=True)
    import psycopg2

    # Only seed an empty dedicated database. Re-running setup preserves edits.
    with psycopg2.connect(env["DB_DSN"], connect_timeout=5) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT to_regclass('travel.places') IS NULL")
            empty = cursor.fetchone()[0]
    steps = [("apply_canonical_sql", "ALLOW_CANONICAL_SQL_APPLY", "APPLY_CANONICAL_SQL")]
    if empty:
        steps.extend(
            [
                ("plan_dev_reset", "ALLOW_DEV_RESET_APPLY", "APPLY_DEV_RESET_SQL"),
                (
                    "run_place_score_batch",
                    "ALLOW_PLACE_SCORE_BATCH_APPLY",
                    "APPLY_PLACE_SCORE_BATCH",
                ),
            ]
        )
    for module, gate, confirmation in steps:
        step_env = dict(env, **{gate: "1"})
        output = run(
            [
                sys.executable,
                "-m",
                f"apps.api.app.tools.{module}",
                "--apply",
                "--confirm",
                confirmation,
                "--json",
            ],
            step_env,
        )
        if not json.loads(output).get("ok"):
            raise RuntimeError(f"{module} did not report success")
        print(f"{module}: passed", flush=True)
    with psycopg2.connect(env["DB_DSN"], connect_timeout=5) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT count(*) FROM travel.places")
            count = cursor.fetchone()[0]
    print(f"DB-backed local fixture places: {count}. No production data imported.")


def serve() -> None:
    env = database_env()
    # Public Logto settings are optional and separate from local DB credentials.
    public_file = STATE / "flutter-public.json"
    if public_file.exists():
        public = json.loads(public_file.read_text(encoding="utf-8"))
        for name in ("LOGTO_ENDPOINT", "LOGTO_API_AUDIENCE"):
            if public.get(name):
                env[name] = public[name]
    print("API: http://127.0.0.1:8080; local fixture DB; live AI/Speech disabled.", flush=True)
    raise SystemExit(
        subprocess.call(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "apps.api.app.main:app",
                "--host",
                "127.0.0.1",
                "--port",
                "8080",
                "--no-access-log",
            ],
            cwd=ROOT,
            env=env,
        )
    )


def check() -> None:
    for path in ("/healthz", "/readyz"):
        with urllib.request.urlopen(f"http://127.0.0.1:8080{path}", timeout=15) as response:
            print(f"{path}: HTTP {response.status}")
    request = urllib.request.Request(
        "http://127.0.0.1:8080/api/v1/places",
        method="OPTIONS",
        headers={"Origin": "http://127.0.0.1:8765", "Access-Control-Request-Method": "GET"},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.headers.get("Access-Control-Allow-Origin") != "http://127.0.0.1:8765":
            raise RuntimeError("Local preview CORS check failed")
        print("Local preview CORS: passed")
    # Fixed fixture coordinates, never the user's current location.
    with urllib.request.urlopen(
        "http://127.0.0.1:8080/api/v1/places?lat=37.2879&lng=127.0116&radius_m=5000",
        timeout=15,
    ) as response:
        payload = json.load(response)
        print(f"Fixture places request: HTTP {response.status}")
        data = payload.get("data", {})
        if data.get("source") != "db" or not data.get("places"):
            raise RuntimeError("Expected nonempty DB-backed fixture places")
        print(f"DB-backed fixture results: {len(data['places'])}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "serve", "check"))
    args = parser.parse_args()
    try:
        {"setup": setup, "serve": serve, "check": check}[args.action]()
    except Exception as exc:
        if isinstance(exc, RuntimeError):
            print(str(exc), file=sys.stderr)
        else:
            print(f"Local development step failed: {type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
