"""Create an isolated Docker database, inject generated settings, then remove it."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from contextlib import closing
from pathlib import Path
from urllib.parse import quote, urlunsplit

import psycopg2

ROOT = Path(__file__).resolve().parents[4]
SUITES = (
    "test_identity_lifecycle.py",
    "test_community_production_regressions.py",
    "test_paid_cost_controls.py",
    "test_production_runtime.py",
)


def run(*args: str, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=ROOT, check=True, text=True, **kwargs)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", help="Existing local PostgreSQL/PostGIS/vector image")
    args = parser.parse_args()
    name = f"lala-test-{secrets.token_hex(6)}"
    image = args.image or name
    if not args.image:
        run("docker", "build", "-t", image, "infra/local-postgres")
    user, database = f"u_{secrets.token_hex(6)}", f"db_{secrets.token_hex(6)}"
    password = secrets.token_urlsafe(32)
    # Loopback is a safety invariant, not a deployment endpoint. Docker chooses the port.
    host = socket.gethostbyname("localhost")
    env = {
        key: value
        for key, value in os.environ.items()
        if key
        in {
            "PATH",
            "HOME",
            "SYSTEMROOT",
            "TEMP",
            "TMP",
            "TMPDIR",
            "LANG",
            "LC_ALL",
        }
    }
    env.update(
        LALA_RUNTIME_PROFILE="ci",
        PYTHONPATH=f"{ROOT / 'apps/api/tests/network_guard'}{os.pathsep}{ROOT}",
    )
    try:
        with tempfile.TemporaryDirectory(prefix="lala-test-config-") as directory:
            config = Path(directory) / "database.env"
            config.write_text(
                f"POSTGRES_USER={user}\nPOSTGRES_DB={database}\nPOSTGRES_PASSWORD={password}\n"
            )
            config.chmod(0o600)
            run(
                "docker",
                "run",
                "-d",
                "--name",
                name,
                "--env-file",
                str(config),
                "--tmpfs",
                "/var/lib/postgresql/data",
                "-p",
                f"{host}::5432",
                image,
                stdout=subprocess.DEVNULL,
            )
        inspected = json.loads(run("docker", "inspect", name, capture_output=True).stdout)[0]
        port = inspected["NetworkSettings"]["Ports"]["5432/tcp"][0]["HostPort"]
        dsn = urlunsplit(
            (
                "postgresql",
                f"{quote(user)}:{quote(password)}@{host}:{port}",
                f"/{quote(database)}",
                "",
                "",
            )
        )
        deadline = time.monotonic() + 60
        while True:
            try:
                with (
                    closing(psycopg2.connect(dsn, connect_timeout=2)) as conn,
                    conn.cursor() as cur,
                ):
                    cur.execute("SELECT 1")
                break
            except psycopg2.OperationalError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Disposable database did not become TCP-ready") from None
                time.sleep(0.5)
        env.update(TEST_DB_DSN=dsn, DB_DSN=dsn, ALLOW_CANONICAL_SQL_APPLY="1")
        run(
            sys.executable,
            "-m",
            "apps.api.app.tools.apply_canonical_sql",
            "--apply",
            "--confirm",
            "APPLY_CANONICAL_SQL",
            env=env,
        )
        del env["DB_DSN"]
        run(
            sys.executable,
            "-m",
            "pytest",
            *(f"apps/api/tests/{suite}" for suite in SUITES),
            env=env,
        )
        return 0
    except (subprocess.CalledProcessError, RuntimeError):
        subprocess.run(["docker", "logs", "--tail", "80", name], check=False)
        return 1
    finally:
        subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, check=False)
        if not args.image:
            subprocess.run(["docker", "image", "rm", image], stdout=subprocess.DEVNULL, check=False)


if __name__ == "__main__":
    raise SystemExit(main())
