from __future__ import annotations

import json
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[3]


class _SmokeHandler(BaseHTTPRequestHandler):
    server: "_SmokeServer"

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        return

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/healthz":
            self._write_json({"ok": True, "data": {"status": "ok"}})
            return
        if path == "/readyz":
            if self.server.public_access:
                self._write_json(
                    {
                        "ok": True,
                        "data": {
                            "checks": {
                                "client_identity": "public-contest",
                                "jwt_validation": "skipped",
                                "client_auth": "public-contest",
                                "api_key": "skipped",
                                "bearer_token": "skipped",
                            },
                            "mode": {
                                "overall": "db-backed",
                                "data": "db-backed",
                                "ai": "disabled",
                                "speech": "disabled",
                                "worker": "dry-run",
                            },
                        },
                    }
                )
                return
            self._write_json(
                {
                    "ok": True,
                    "data": {
                        "checks": {
                            "client_identity": "static",
                            "jwt_validation": "skipped",
                            "client_auth": "configured",
                            "api_key": "skipped",
                            "bearer_token": "configured",
                        },
                        "mode": {
                            "overall": "db-backed",
                            "data": "db-backed",
                            "ai": "disabled",
                            "speech": "disabled",
                            "worker": "dry-run",
                        },
                    },
                }
            )
            return
        if path in {"/metrics", "/openapi.json"}:
            self._write_json({"ok": True})
            return
        if path.startswith("/api/v1/"):
            self.server.protected_paths.append(path)
            if not self.server.public_access and self.headers.get("Authorization") != "Bearer server-token":
                self._write_json({"ok": False}, status=401)
                return
            self._write_json({"ok": True, "data": {}})
            return
        self._write_json({"ok": False}, status=404)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/api/v1/"):
            self.server.protected_paths.append(path)
            if not self.server.public_access and self.headers.get("Authorization") != "Bearer server-token":
                self._write_json({"ok": False}, status=401)
                return
            if path == "/api/v1/docents/audio":
                self._write_bytes(b"ID3smoke-audio", content_type="audio/mpeg")
                return
            self._write_json({"ok": True, "data": {"source": "rule_based_curation", "script": "ok"}})
            return
        self._write_json({"ok": False}, status=404)

    def _write_bytes(self, body: bytes, *, content_type: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class _SmokeServer(ThreadingHTTPServer):
    protected_paths: list[str]
    public_access: bool


def _run_smoke(base_url: str, env_overrides: dict[str, str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(
        {
            "KEY_VAULT_URL": "",
            "LALA_ALLOWED_KEY_VAULT_HOSTS": "",
            "LALA_SMOKE_BEARER_TOKEN": "",
            "LALA_SMOKE_API_KEY": "",
            "API_BEARER_TOKEN": "",
            "IOS_API_KEY": "",
        }
    )
    env.update(env_overrides)
    return subprocess.run(
        ["bash", "scripts/unix/smoke_api.sh", "--base-url", base_url],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def _run_matrix_smoke(
    base_url: str,
    env_overrides: dict[str, str],
    *,
    profile: str = "full",
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(
        {
            "KEY_VAULT_URL": "",
            "LALA_ALLOWED_KEY_VAULT_HOSTS": "",
            "LALA_SMOKE_BEARER_TOKEN": "",
            "LALA_SMOKE_API_KEY": "",
            "API_BEARER_TOKEN": "",
            "IOS_API_KEY": "",
        }
    )
    env.update(env_overrides)
    return subprocess.run(
        [
            "bash",
            "scripts/unix/smoke_api_matrix.sh",
            "--base-url",
            base_url,
            "--timeout",
            "3",
            "--profile",
            profile,
        ],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def _start_server(*, public_access: bool = False) -> tuple[_SmokeServer, threading.Thread, str]:
    server = _SmokeServer(("127.0.0.1", 0), _SmokeHandler)
    server.protected_paths = []
    server.public_access = public_access
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    return server, thread, f"http://{host}:{port}"


def test_unix_smoke_skips_mismatched_api_key_instead_of_failing_with_401():
    server, thread, base_url = _start_server()
    try:
        result = _run_smoke(base_url, {"IOS_API_KEY": "stale-api-key"})
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "Matching client auth is not available" in result.stdout
    assert server.protected_paths == []


def test_unix_smoke_uses_bearer_when_readyz_reports_bearer_configured():
    server, thread, base_url = _start_server()
    try:
        result = _run_smoke(base_url, {"API_BEARER_TOKEN": "server-token"})
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "LALA-next API smoke completed." in result.stdout
    assert "/api/v1/places" in server.protected_paths
    assert "/api/v1/weather" in server.protected_paths
    assert "/api/v1/plans/intervention" in server.protected_paths
    assert "/api/v1/plans/daily" in server.protected_paths
    assert "/api/v1/docents/script" in server.protected_paths
    assert "/api/v1/docents/audio" in server.protected_paths


def test_unix_smoke_uses_public_contest_access_without_auth_headers():
    server, thread, base_url = _start_server(public_access=True)
    try:
        result = _run_smoke(base_url, {})
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "LALA-next API smoke completed." in result.stdout
    assert "/api/v1/places" in server.protected_paths
    assert "/api/v1/weather" in server.protected_paths
    assert "/api/v1/plans/intervention" in server.protected_paths
    assert "/api/v1/plans/daily" in server.protected_paths
    assert "/api/v1/docents/script" in server.protected_paths
    assert "/api/v1/docents/audio" in server.protected_paths


def test_unix_matrix_smoke_covers_route_variants_without_printing_auth():
    server, thread, base_url = _start_server()
    try:
        result = _run_matrix_smoke(base_url, {"API_BEARER_TOKEN": "server-token"})
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "LALA-next API matrix smoke" in result.stdout
    assert "checked=37" in result.stdout
    assert "server-token" not in result.stdout
    assert "server-token" not in result.stderr
    assert server.protected_paths.count("/api/v1/places") == 20
    assert server.protected_paths.count("/api/v1/weather") == 4
    assert server.protected_paths.count("/api/v1/plans/intervention") == 4
    assert server.protected_paths.count("/api/v1/plans/daily") == 4
    assert server.protected_paths.count("/api/v1/docents/script") == 4
    assert server.protected_paths.count("/api/v1/docents/audio") == 1


def test_unix_matrix_smoke_deploy_profile_keeps_ci_gate_bounded():
    server, thread, base_url = _start_server(public_access=True)
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "LALA-next API matrix smoke" in result.stdout
    assert "profile=deploy" in result.stdout
    assert "checked=6" in result.stdout
    assert server.protected_paths.count("/api/v1/places") == 1
    assert server.protected_paths.count("/api/v1/weather") == 1
    assert server.protected_paths.count("/api/v1/plans/intervention") == 1
    assert server.protected_paths.count("/api/v1/plans/daily") == 1
    assert server.protected_paths.count("/api/v1/docents/script") == 1
    assert server.protected_paths.count("/api/v1/docents/audio") == 1


def test_unix_matrix_smoke_uses_public_contest_access_without_auth_headers():
    server, thread, base_url = _start_server(public_access=True)
    try:
        result = _run_matrix_smoke(base_url, {})
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "LALA-next API matrix smoke" in result.stdout
    assert "checked=37" in result.stdout
    assert server.protected_paths.count("/api/v1/places") == 20
    assert server.protected_paths.count("/api/v1/weather") == 4
    assert server.protected_paths.count("/api/v1/plans/intervention") == 4
    assert server.protected_paths.count("/api/v1/plans/daily") == 4
    assert server.protected_paths.count("/api/v1/docents/script") == 4
    assert server.protected_paths.count("/api/v1/docents/audio") == 1
