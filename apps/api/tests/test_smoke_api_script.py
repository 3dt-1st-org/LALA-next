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
                            "status": self.server.ready_status,
                            "checks": {
                                "client_identity": "public-contest",
                                "jwt_validation": "skipped",
                                "client_auth": "public-contest",
                                "api_key": "skipped",
                                "bearer_token": "skipped",
                                "db": "configured",
                                "postgis": "configured",
                                "live_speech": "enabled"
                                if self.server.live_speech
                                else "disabled",
                                "static_snapshot_fallback": self.server.static_snapshot_fallback,
                            },
                            "mode": {
                                "overall": self.server.data_mode,
                                "data": self.server.data_mode,
                                "ai": "disabled",
                                "speech": "live-azure"
                                if self.server.live_speech
                                else "disabled",
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
                        "status": self.server.ready_status,
                        "checks": {
                            "client_identity": "static",
                            "jwt_validation": "skipped",
                            "client_auth": "configured",
                            "api_key": "skipped",
                            "bearer_token": "configured",
                            "db": "configured",
                            "postgis": "configured",
                            "live_speech": "enabled"
                            if self.server.live_speech
                            else "disabled",
                            "static_snapshot_fallback": self.server.static_snapshot_fallback,
                        },
                        "mode": {
                            "overall": self.server.data_mode,
                            "data": self.server.data_mode,
                            "ai": "disabled",
                            "speech": "live-azure"
                            if self.server.live_speech
                            else "disabled",
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
            if (
                not self.server.public_access
                and self.headers.get("Authorization") != "Bearer server-token"
            ):
                self._write_json({"ok": False}, status=401)
                return
            if path == "/api/v1/places":
                self._write_json(self.server.places_payload)
                return
            if path == "/api/v1/weather":
                self._write_json(self.server.weather_payload)
                return
            if path == "/api/v1/plans/intervention":
                self._write_json(self.server.intervention_payload)
                return
            self._write_json({"ok": True, "data": {}})
            return
        self._write_json({"ok": False}, status=404)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/api/v1/"):
            self.server.protected_paths.append(path)
            if (
                not self.server.public_access
                and self.headers.get("Authorization") != "Bearer server-token"
            ):
                self._write_json({"ok": False}, status=401)
                return
            if path == "/api/v1/docents/audio":
                if self.server.live_speech:
                    self._write_bytes(b"ID3smoke-audio", content_type="audio/mpeg")
                    return
                self._write_json(
                    {
                        "ok": False,
                        "error": {
                            "code": "SPEECH_NOT_CONFIGURED",
                            "message": "Azure Speech live synthesis is not enabled.",
                            "retryable": False,
                        },
                    },
                    status=503,
                )
                return
            if path == "/api/v1/plans/daily":
                self._write_json(self.server.daily_plan_payload)
                return
            if path == "/api/v1/docents/script":
                self._write_json(self.server.docent_payload)
                return
            self._write_json({"ok": True, "data": {}})
            return
        self._write_json({"ok": False}, status=404)

    def _write_bytes(
        self, body: bytes, *, content_type: str, status: int = 200
    ) -> None:
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
    ready_status: str
    data_mode: str
    static_snapshot_fallback: str
    live_speech: bool
    places_payload: dict[str, Any]
    weather_payload: dict[str, Any]
    intervention_payload: dict[str, Any]
    daily_plan_payload: dict[str, Any]
    docent_payload: dict[str, Any]


def _run_smoke(
    base_url: str, env_overrides: dict[str, str]
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


def _start_server(
    *,
    public_access: bool = False,
    ready_status: str = "ok",
    data_mode: str = "db-backed",
    static_snapshot_fallback: str = "disabled",
    live_speech: bool = False,
    places_payload: dict[str, Any] | None = None,
    weather_payload: dict[str, Any] | None = None,
    intervention_payload: dict[str, Any] | None = None,
    daily_plan_payload: dict[str, Any] | None = None,
    docent_payload: dict[str, Any] | None = None,
) -> tuple[_SmokeServer, threading.Thread, str]:
    server = _SmokeServer(("127.0.0.1", 0), _SmokeHandler)
    server.protected_paths = []
    server.public_access = public_access
    server.ready_status = ready_status
    server.data_mode = data_mode
    server.static_snapshot_fallback = static_snapshot_fallback
    server.live_speech = live_speech
    server.places_payload = places_payload or _live_places_payload()
    server.weather_payload = weather_payload or _live_weather_payload()
    server.intervention_payload = intervention_payload or _live_intervention_payload()
    server.daily_plan_payload = daily_plan_payload or _live_daily_plan_payload()
    server.docent_payload = docent_payload or _live_docent_payload()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    return server, thread, f"http://{host}:{port}"


def _live_place(
    *, place_id: str = "tour-api-1", distance_m: int = 212
) -> dict[str, Any]:
    return {
        "place_id": place_id,
        "name": "중랑아트센터",
        "category": "culture_venue",
        "distance_m": distance_m,
        "source": "db",
        "upstream_source": "tour_api",
        "image_url": "https://tong.visitkorea.or.kr/cms/resource/01/1_image2_1.jpg",
        "score": {
            "final_score": 0.83,
            "data_basis": "analytics.place_score_snapshots",
        },
    }


def _live_places_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "data": {
            "source": "db",
            "count": 2,
            "places": [
                _live_place(place_id="tour-api-1", distance_m=212),
                _live_place(place_id="tour-api-2", distance_m=470),
            ],
        },
    }


def _live_weather_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "data": {
            "source": "kma_ultra_srt_ncst+airkorea_sido_realtime",
            "location": "중구",
            "air_quality_location": "중구",
            "air_quality_record_time": "2026-06-21 15:00",
            "temp": "23.4",
            "dust": {
                "pm10": "6",
                "pm25": "1",
                "grade": "good",
                "pm10_grade": "good",
                "pm25_grade": "good",
            },
        },
    }


def _live_intervention_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "data": {
            "source": "db",
            "should_intervene": False,
            "place": _live_place(),
        },
    }


def _live_daily_plan_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "data": {
            "source": "db",
            "slots": [
                {"period": "morning", "title": "문화 산책", "place": _live_place()}
            ],
        },
    }


def _live_docent_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "data": {
            "source": "rule_based_curation",
            "script": (
                "중랑아트센터는 현재 위치에서 약 840m 거리의 문화공간입니다. "
                "LALA는 실제 내국인 소비 흐름과 문화 경험 맥락을 함께 보고 이 장소를 고릅니다. "
                "현재 날씨는 기온 21.6°C, 미세먼지 좋음(PM10 6) · 초미세먼지 좋음(PM2.5 2)입니다. "
                "공식 한국관광공사 데이터와 장소 맥락을 함께 확인했습니다."
            ),
            "grounding_count": 1,
            "grounding_sources": ["place_profile"],
        },
    }


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


def test_unix_smoke_fails_when_readyz_reports_degraded():
    server, thread, base_url = _start_server(ready_status="degraded")
    try:
        result = _run_smoke(base_url, {"API_BEARER_TOKEN": "server-token"})
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "/readyz reported non-ok status: degraded" in result.stderr
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
    assert "checked=7" in result.stdout
    assert server.protected_paths.count("/api/v1/places") == 2
    assert server.protected_paths.count("/api/v1/weather") == 1
    assert server.protected_paths.count("/api/v1/plans/intervention") == 1
    assert server.protected_paths.count("/api/v1/plans/daily") == 1
    assert server.protected_paths.count("/api/v1/docents/script") == 1
    assert server.protected_paths.count("/api/v1/docents/audio") == 1


def test_unix_matrix_smoke_deploy_profile_accepts_live_speech_audio():
    server, thread, base_url = _start_server(public_access=True, live_speech=True)
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode == 0, result.stderr
    assert "checked=7" in result.stdout
    assert server.protected_paths.count("/api/v1/docents/audio") == 1


def test_unix_matrix_smoke_deploy_profile_rejects_snapshot_fallback_mode():
    server, thread, base_url = _start_server(
        public_access=True,
        data_mode="public-cache",
        static_snapshot_fallback="enabled",
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "profile=deploy" in result.stdout
    assert "checked=0" in result.stdout
    assert "data_mode_not_db_backed" in result.stderr
    assert server.protected_paths == []


def test_unix_matrix_smoke_deploy_profile_rejects_snapshot_place_payload():
    snapshot_payload = _live_places_payload()
    snapshot_payload["data"]["source"] = "public_mvp_snapshot"
    snapshot_payload["data"]["places"][0]["source"] = "public_mvp_snapshot"

    server, thread, base_url = _start_server(
        public_access=True, places_payload=snapshot_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "profile=deploy" in result.stdout
    assert "places_source_not_live_db" in result.stderr
    assert "/api/v1/places" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_missing_postgis_distance():
    places_payload = _live_places_payload()
    places_payload["data"]["places"][0].pop("distance_m")

    server, thread, base_url = _start_server(
        public_access=True, places_payload=places_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "place_missing_postgis_distance" in result.stderr


def test_unix_matrix_smoke_deploy_profile_rejects_place_outside_radius():
    places_payload = _live_places_payload()
    places_payload["data"]["places"][0]["distance_m"] = 1200

    server, thread, base_url = _start_server(
        public_access=True, places_payload=places_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "place_distance_outside_radius" in result.stderr


def test_unix_matrix_smoke_deploy_profile_rejects_unknown_dust_split():
    weather_payload = _live_weather_payload()
    weather_payload["data"]["dust"]["pm25_grade"] = "unknown"

    server, thread, base_url = _start_server(
        public_access=True, weather_payload=weather_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "weather_missing_dust_split" in result.stderr
    assert "/api/v1/weather" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_missing_dust_values():
    weather_payload = _live_weather_payload()
    weather_payload["data"]["dust"]["pm10"] = "-"

    server, thread, base_url = _start_server(
        public_access=True, weather_payload=weather_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "weather_missing_dust_values" in result.stderr
    assert "/api/v1/weather" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_weather_without_airkorea():
    weather_payload = _live_weather_payload()
    weather_payload["data"]["source"] = "kma_ultra_srt_ncst"

    server, thread, base_url = _start_server(
        public_access=True, weather_payload=weather_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "weather_missing_airkorea_source" in result.stderr
    assert "/api/v1/weather" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_missing_air_quality_station():
    weather_payload = _live_weather_payload()
    weather_payload["data"]["air_quality_location"] = ""

    server, thread, base_url = _start_server(
        public_access=True, weather_payload=weather_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "weather_missing_air_quality_location" in result.stderr
    assert "/api/v1/weather" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_internal_weather_location():
    weather_payload = _live_weather_payload()
    weather_payload["data"]["location"] = "기상청 격자"

    server, thread, base_url = _start_server(
        public_access=True, weather_payload=weather_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "weather_internal_location_label" in result.stderr
    assert "/api/v1/weather" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_placeholder_docent():
    docent_payload = _live_docent_payload()
    docent_payload["data"]["script"] = "placeholder"

    server, thread, base_url = _start_server(
        public_access=True, docent_payload=docent_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "docent_script_too_short" in result.stderr
    assert "/api/v1/docents/script" in server.protected_paths


def test_unix_matrix_smoke_deploy_profile_rejects_docent_without_grounding():
    docent_payload = _live_docent_payload()
    docent_payload["data"]["grounding_count"] = 0
    docent_payload["data"]["grounding_sources"] = []

    server, thread, base_url = _start_server(
        public_access=True, docent_payload=docent_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "docent_missing_grounding" in result.stderr


def test_unix_matrix_smoke_deploy_profile_rejects_docent_internal_codes():
    docent_payload = _live_docent_payload()
    docent_payload["data"]["script"] += " category culture_venue source tour_api"

    server, thread, base_url = _start_server(
        public_access=True, docent_payload=docent_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "docent_script_contains_internal_code" in result.stderr


def test_unix_matrix_smoke_deploy_profile_rejects_docent_internal_evidence():
    docent_payload = _live_docent_payload()
    docent_payload["data"]["script"] += " 종합 추천 점수는 86점입니다."

    server, thread, base_url = _start_server(
        public_access=True, docent_payload=docent_payload
    )
    try:
        result = _run_matrix_smoke(base_url, {}, profile="deploy")
    finally:
        server.shutdown()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "docent_script_contains_internal_evidence" in result.stderr


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
