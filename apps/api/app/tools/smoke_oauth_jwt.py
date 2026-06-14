from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

DEFAULT_API_HOST = "127.0.0.1"
DEFAULT_API_PORT = 0
DEFAULT_ISSUER = "https://login.microsoftonline.com/local-smoke/v2.0"
DEFAULT_AUDIENCE = "api://lala-next-dev"
DEFAULT_CLIENT_ID = "00000000-0000-0000-0000-000000000000"
DEFAULT_SCOPE = "access_as_user"
TOKEN_KID = "lala-local-smoke-key"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run a local OAuth/JWT smoke test without Azure, Entra, or Key Vault mutation."
    )
    parser.add_argument("--api-host", default=DEFAULT_API_HOST)
    parser.add_argument("--api-port", type=int, default=DEFAULT_API_PORT)
    parser.add_argument("--issuer", default=DEFAULT_ISSUER)
    parser.add_argument("--audience", default=DEFAULT_AUDIENCE)
    parser.add_argument("--client-id", default=DEFAULT_CLIENT_ID)
    parser.add_argument("--scope", default=DEFAULT_SCOPE)
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    args = parser.parse_args(argv)

    result = run_smoke(
        api_host=args.api_host,
        api_port=args.api_port,
        issuer=args.issuer,
        audience=args.audience,
        client_id=args.client_id,
        scope=args.scope,
    )
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        _write_human(result)
    return 0 if result["ok"] else 1


def run_smoke(
    *,
    api_host: str,
    api_port: int,
    issuer: str,
    audience: str,
    client_id: str,
    scope: str,
) -> dict[str, Any]:
    api_port = api_port or _free_port(api_host)
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwks_payload = {"keys": [_public_jwk(private_key)]}
    jwks_server = _JwksServer(host=api_host, jwks_payload=jwks_payload)
    jwks_server.start()

    api_process: subprocess.Popen[str] | None = None
    base_url = f"http://{api_host}:{api_port}"
    try:
        token = _signed_token(private_key, issuer=issuer, audience=audience, scope=scope)
        wrong_scope_token = _signed_token(
            private_key,
            issuer=issuer,
            audience=audience,
            scope="wrong.scope",
        )
        env = _api_env(
            issuer=issuer,
            audience=audience,
            jwks_url=jwks_server.jwks_url,
            client_id=client_id,
            scope=scope,
        )
        api_process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "apps.api.app.main:app",
                "--host",
                api_host,
                "--port",
                str(api_port),
                "--no-access-log",
            ],
            cwd=_repo_root(),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        _wait_for_api(base_url, api_process)

        readyz = _request_json(f"{base_url}/readyz")
        checks = (readyz.get("data") or {}).get("checks") or {}
        if checks.get("client_identity") != "oauth-configured":
            raise RuntimeError(f"Unexpected client_identity: {checks.get('client_identity')}")
        if checks.get("jwt_validation") != "configured":
            raise RuntimeError(f"Unexpected jwt_validation: {checks.get('jwt_validation')}")

        places = _request_json(
            f"{base_url}/api/v1/places?lat=37.2636&lng=127.0286&radius_m=1000",
            bearer_token=token,
        )
        if places.get("ok") is not True:
            raise RuntimeError("Authenticated places smoke did not return ok=true.")

        rejected = _request_json(
            f"{base_url}/api/v1/places",
            bearer_token=wrong_scope_token,
            expected_status=401,
        )
        if (rejected.get("error") or {}).get("code") != "UNAUTHORIZED":
            raise RuntimeError("Wrong-scope JWT did not return UNAUTHORIZED.")

        return {
            "ok": True,
            "mode": "local-oauth-jwt-smoke",
            "applies_changes": False,
            "api_base_url": base_url,
            "jwks_url": jwks_server.jwks_url,
            "client_identity": checks.get("client_identity"),
            "jwt_validation": checks.get("jwt_validation"),
            "places_count": (places.get("data") or {}).get("count"),
            "wrong_scope_status": "rejected",
        }
    except Exception as exc:
        return {
            "ok": False,
            "mode": "local-oauth-jwt-smoke",
            "applies_changes": False,
            "api_base_url": base_url,
            "jwks_url": jwks_server.jwks_url,
            "error": str(exc),
            "api_output": _collect_process_output(api_process),
        }
    finally:
        if api_process is not None:
            _stop_process(api_process)
        jwks_server.stop()


def _write_human(result: dict[str, Any]) -> None:
    print("LALA-next local OAuth/JWT smoke")
    print("mode=local-oauth-jwt-smoke")
    print("applies_changes=false")
    print(f"status={'ok' if result.get('ok') else 'failed'}")
    print(f"api_base_url={result.get('api_base_url')}")
    print(f"jwks_url={result.get('jwks_url')}")
    if result.get("ok"):
        print(f"client_identity={result.get('client_identity')}")
        print(f"jwt_validation={result.get('jwt_validation')}")
        print(f"places_count={result.get('places_count')}")
        print(f"wrong_scope_status={result.get('wrong_scope_status')}")
    else:
        print(f"error={result.get('error')}")


def _api_env(
    *,
    issuer: str,
    audience: str,
    jwks_url: str,
    client_id: str,
    scope: str,
) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "KEY_VAULT_URL": "",
            "IOS_API_KEY": "",
            "API_BEARER_TOKEN": "",
            "LALA_SMOKE_BEARER_TOKEN": "",
            "LALA_SMOKE_API_KEY": "",
            "OAUTH_ISSUER": issuer,
            "OAUTH_AUDIENCE": audience,
            "OAUTH_JWKS_URL": jwks_url,
            "OAUTH_CLIENT_ID": client_id,
            "OAUTH_REQUIRED_SCOPES": scope,
            "DB_DSN": "",
            "LALA_ENABLE_LIVE_AI": "false",
            "LALA_ENABLE_LIVE_SPEECH": "false",
            "PYTHONUNBUFFERED": "1",
        }
    )
    return env


def _public_jwk(private_key) -> dict[str, Any]:
    payload = json.loads(RSAAlgorithm.to_jwk(private_key.public_key()))
    payload.update({"kid": TOKEN_KID, "use": "sig", "alg": "RS256"})
    return payload


def _signed_token(private_key, *, issuer: str, audience: str, scope: str) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "iss": issuer,
            "aud": audience,
            "sub": "local-smoke-user",
            "scp": scope,
            "iat": now,
            "nbf": now - timedelta(seconds=5),
            "exp": now + timedelta(minutes=10),
        },
        private_key,
        algorithm="RS256",
        headers={"kid": TOKEN_KID},
    )


def _wait_for_api(base_url: str, api_process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 20
    last_error = ""
    while time.monotonic() < deadline:
        if api_process.poll() is not None:
            output = _collect_process_output(api_process)
            raise RuntimeError(f"API process exited early: {output}")
        try:
            payload = _request_json(f"{base_url}/healthz")
            if payload.get("ok") is True:
                return
        except Exception as exc:
            last_error = str(exc)
        time.sleep(0.25)
    raise RuntimeError(f"API did not become ready: {last_error}")


def _request_json(
    url: str,
    *,
    bearer_token: str = "",
    expected_status: int = 200,
) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    if bearer_token:
        headers["Authorization"] = f"Bearer {bearer_token}"
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=5) as response:
            status = response.status
            body = response.read().decode("utf-8")
    except HTTPError as exc:
        status = exc.code
        body = exc.read().decode("utf-8")
    except URLError as exc:
        raise RuntimeError(str(exc)) from exc
    if status != expected_status:
        raise RuntimeError(f"{url} returned HTTP {status}, expected {expected_status}.")
    return json.loads(body)


def _free_port(host: str) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        return int(sock.getsockname()[1])


def _repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))


def _stop_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def _collect_process_output(process: subprocess.Popen[str] | None) -> str:
    if process is None:
        return ""
    try:
        stdout, stderr = process.communicate(timeout=1)
    except subprocess.TimeoutExpired:
        return ""
    combined = "\n".join(part for part in (stdout, stderr) if part)
    return combined[-2000:]


class _JwksServer:
    def __init__(self, *, host: str, jwks_payload: dict[str, Any]) -> None:
        self._host = host
        self._jwks_payload = jwks_payload
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None
        self.jwks_url = ""

    def start(self) -> None:
        payload = self._jwks_payload

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler.
                if self.path != "/keys":
                    self.send_response(404)
                    self.end_headers()
                    return
                body = json.dumps(payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        self._server = ThreadingHTTPServer((self._host, 0), Handler)
        port = int(self._server.server_address[1])
        self.jwks_url = f"http://{self._host}:{port}/keys"
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if self._server is None:
            return
        self._server.shutdown()
        self._server.server_close()
        if self._thread is not None:
            self._thread.join(timeout=5)


if __name__ == "__main__":
    sys.exit(main())
