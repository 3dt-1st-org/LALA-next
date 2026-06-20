from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
import sys
from typing import Any
from urllib import error, parse, request


@dataclass(frozen=True)
class SmokeCase:
    method: str
    path: str
    body: bytes | None = None
    response_kind: str = "json"

    @property
    def route_label(self) -> str:
        return self.path.split("?", 1)[0]


@dataclass(frozen=True)
class SmokeFailure:
    case: SmokeCase
    status: int | str
    reason: str


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run a broader LALA-next API smoke matrix.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument(
        "--profile",
        choices=("deploy", "full"),
        default="full",
        help="Use deploy for a bounded CI gate or full for the wider route matrix.",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    result = run_matrix(base_url=args.base_url, timeout=args.timeout, profile=args.profile)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        _print_human(result)
    return 0 if result["ok"] else 1


def run_matrix(*, base_url: str, timeout: float, profile: str = "full") -> dict[str, Any]:
    base_url = base_url.rstrip("/")
    readyz = _request_json(
        SmokeCase("GET", "/readyz"),
        base_url=base_url,
        headers={},
        timeout=timeout,
    )
    auth_headers = _matching_auth_headers(readyz)
    if auth_headers is None:
        return {
            "ok": False,
            "mode": "api_matrix_smoke",
            "checked": 0,
            "failures": [
                {
                    "method": "AUTH",
                    "path": "/readyz",
                    "status": "missing",
                    "reason": "no_matching_client_auth",
                }
            ],
        }

    failures: list[SmokeFailure] = []
    cases = _build_cases(profile=profile)
    for case in cases:
        failure = _run_case(
            case,
            base_url=base_url,
            headers=auth_headers,
            timeout=timeout,
        )
        if failure:
            failures.append(failure)

    return {
        "ok": not failures,
        "mode": "api_matrix_smoke",
        "profile": profile,
        "checked": len(cases),
        "failures": [
            {
                "method": failure.case.method,
                "path": failure.case.route_label,
                "status": failure.status,
                "reason": failure.reason,
            }
            for failure in failures
        ],
    }


def _build_cases(*, profile: str) -> list[SmokeCase]:
    if profile == "deploy":
        return _build_deploy_cases()
    if profile != "full":
        raise ValueError(f"Unsupported smoke matrix profile: {profile}")
    return _build_full_cases()


def _build_deploy_cases() -> list[SmokeCase]:
    location = {"lat": 37.5665, "lng": 126.9780, "radius_m": 50000}
    place_query = parse.urlencode({**location, "category": "all", "language": "ko"})
    weather_query = parse.urlencode(location)
    return [
        SmokeCase("GET", f"/api/v1/places?{place_query}"),
        SmokeCase("GET", f"/api/v1/weather?{weather_query}"),
        SmokeCase("GET", f"/api/v1/plans/intervention?{weather_query}"),
        SmokeCase("POST", "/api/v1/plans/daily", _json_body({**location, "language": "ko"})),
        SmokeCase(
            "POST",
            "/api/v1/docents/script",
            _json_body(
                {
                    "place_id": "tour-api-3066000",
                    "place_name": "중랑아트센터",
                    "category": "culture_venue",
                    "language": "ko",
                    "mode": "brief",
                }
            ),
        ),
        SmokeCase(
            "POST",
            "/api/v1/docents/audio",
            _json_body({"script": "스모크 오디오", "language": "ko"}),
            response_kind="audio",
        ),
    ]


def _build_full_cases() -> list[SmokeCase]:
    cases: list[SmokeCase] = []
    for category in ("all", "attraction", "restaurant", "event", "culture_venue"):
        for language in ("ko", "en", "English", "kr"):
            query = parse.urlencode(
                {
                    "lat": 37.2636,
                    "lng": 127.0286,
                    "radius_m": 1000,
                    "category": category,
                    "language": language,
                }
            )
            cases.append(SmokeCase("GET", f"/api/v1/places?{query}"))

    for lat, lng in ((37.2636, 127.0286), (37.5665, 126.9780), (0, 0), (33.4996, 126.5312)):
        query = parse.urlencode({"lat": lat, "lng": lng, "radius_m": 50000})
        cases.append(SmokeCase("GET", f"/api/v1/weather?{query}"))
        cases.append(SmokeCase("GET", f"/api/v1/plans/intervention?{query}"))
        cases.append(
            SmokeCase(
                "POST",
                "/api/v1/plans/daily",
                _json_body({"lat": lat, "lng": lng, "radius_m": 50000, "language": "ko"}),
            )
        )

    for category in ("attraction", "restaurant", "event", "culture_venue"):
        cases.append(
            SmokeCase(
                "POST",
                "/api/v1/docents/script",
                _json_body(
                    {
                        "place_id": f"smoke-{category}",
                        "place_name": "스모크",
                        "category": category,
                        "language": "ko",
                        "mode": "brief",
                    }
                ),
            )
        )

    cases.append(
        SmokeCase(
            "POST",
            "/api/v1/docents/audio",
            _json_body({"script": "스모크 오디오", "language": "ko"}),
            response_kind="audio",
        )
    )
    return cases


def _run_case(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> SmokeFailure | None:
    try:
        status, content_type, body = _request_raw(
            case,
            base_url=base_url,
            headers=headers,
            timeout=timeout,
        )
    except error.HTTPError as exc:
        return SmokeFailure(case=case, status=exc.code, reason="http_error")
    except Exception as exc:
        return SmokeFailure(case=case, status="exception", reason=type(exc).__name__)

    if status >= 500:
        return SmokeFailure(case=case, status=status, reason="server_error")
    if case.response_kind == "audio":
        if not content_type.startswith("audio/mpeg"):
            return SmokeFailure(case=case, status=status, reason="unexpected_audio_content_type")
        if not body:
            return SmokeFailure(case=case, status=status, reason="empty_audio_body")
        return None

    try:
        payload = json.loads(body.decode("utf-8"))
    except Exception:
        return SmokeFailure(case=case, status=status, reason="invalid_json")
    if payload.get("ok") is not True:
        return SmokeFailure(case=case, status=status, reason="ok_false")
    return None


def _request_json(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> dict[str, Any]:
    _, _, body = _request_raw(case, base_url=base_url, headers=headers, timeout=timeout)
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError("Unexpected JSON response.")
    return payload


def _request_raw(
    case: SmokeCase,
    *,
    base_url: str,
    headers: dict[str, str],
    timeout: float,
) -> tuple[int, str, bytes]:
    request_headers = dict(headers)
    if case.body is not None:
        request_headers["Content-Type"] = "application/json; charset=utf-8"
    req = request.Request(
        base_url + case.path,
        data=case.body,
        headers=request_headers,
        method=case.method,
    )
    with request.urlopen(req, timeout=timeout) as response:
        return (
            response.status,
            response.headers.get("content-type", ""),
            response.read(),
        )


def _matching_auth_headers(readyz_payload: dict[str, Any]) -> dict[str, str] | None:
    checks = (readyz_payload.get("data") or {}).get("checks") or {}
    bearer = os.getenv("LALA_SMOKE_BEARER_TOKEN") or os.getenv("API_BEARER_TOKEN")
    api_key = os.getenv("LALA_SMOKE_API_KEY") or os.getenv("IOS_API_KEY")
    if checks.get("client_auth") == "public-contest" or checks.get("client_identity") == "public-contest":
        return {}
    if checks.get("bearer_token") == "configured" and bearer:
        return {"Authorization": f"Bearer {bearer}"}
    if checks.get("api_key") == "configured" and api_key:
        return {"X-API-Key": api_key}
    return None


def _json_body(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _print_human(result: dict[str, Any]) -> None:
    print("LALA-next API matrix smoke")
    print(f"mode={result['mode']}")
    print(f"profile={result['profile']}")
    print(f"status={'ok' if result['ok'] else 'failed'}")
    print(f"checked={result['checked']}")
    for failure in result.get("failures") or []:
        print(
            "failure="
            f"{failure['method']} {failure['path']} "
            f"status={failure['status']} reason={failure['reason']}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    raise SystemExit(main())
