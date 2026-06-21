#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

REQUIRE_FLUTTER="false"
REQUIRE_BROWSER="false"
FAIL_ON_CONSOLE_ERROR="false"
START_API="false"
PORT="8099"
API_PORT="18080"
HOST="127.0.0.1"
API_BASE_URL="http://127.0.0.1:8080"
API_BASE_URL_EXPLICIT="false"
WEB_URL=""
WEB_URL_EXPLICIT="false"
SMOKE_LAT="37.5665"
SMOKE_LNG="126.9780"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-flutter)
      REQUIRE_FLUTTER="true"
      shift
      ;;
    --require-browser)
      REQUIRE_BROWSER="true"
      shift
      ;;
    --fail-on-console-error)
      FAIL_ON_CONSOLE_ERROR="true"
      shift
      ;;
    --start-api)
      START_API="true"
      shift
      ;;
    --api-base-url)
      API_BASE_URL="${2:-}"
      API_BASE_URL_EXPLICIT="true"
      shift 2
      ;;
    --web-url)
      WEB_URL="${2:-}"
      WEB_URL_EXPLICIT="true"
      shift 2
      ;;
    --api-port)
      API_PORT="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/smoke_flutter_web.sh [--require-flutter] [--require-browser] [--fail-on-console-error] [--start-api] [--api-base-url URL] [--web-url URL] [--api-port PORT] [--port PORT]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
APP_DIR="$ROOT/apps/flutter_app"
BUILD_DIR="$APP_DIR/build/web"
OUTPUT_DIR="$ROOT/output/playwright"
PWCLI="${CODEX_HOME:-$HOME/.codex}/skills/playwright/scripts/playwright_cli.sh"
PYTHON="$(select_python "")"
SERVER_PID=""
API_PID=""
PW_SESSION="lala-flutter-web-smoke-$$"
WEB_ORIGIN="http://$HOST:$PORT"
TARGET_URL="$WEB_ORIGIN/"
API_LOG="/tmp/lala-next-flutter-web-api-smoke-$PORT-$API_PORT.log"
WEB_LOG="/tmp/lala-next-flutter-web-smoke-$PORT.log"
SMOKE_API_KEY="lala-web-smoke-key"

load_env_file "$ROOT/.env"
load_lala_key_vault_secrets

if [[ "$WEB_URL_EXPLICIT" == "true" ]]; then
  if [[ -z "$WEB_URL" ]]; then
    echo "--web-url requires a URL." >&2
    exit 2
  fi
  if [[ "$START_API" == "true" || "$API_BASE_URL_EXPLICIT" == "true" ]]; then
    echo "--web-url opens an already-built site; do not combine it with --start-api or --api-base-url." >&2
    exit 2
  fi
  WEB_ORIGIN="$("$PYTHON" - "$WEB_URL" <<'PY'
import sys
from urllib.parse import urlparse

url = urlparse(sys.argv[1])
if not url.scheme or not url.netloc:
    raise SystemExit("--web-url must be an absolute URL")
print(f"{url.scheme}://{url.netloc}")
PY
)"
  TARGET_URL="$WEB_URL"
fi

cleanup() {
  if [[ -x "$PWCLI" ]]; then
    "$PWCLI" -s="$PW_SESSION" close >/dev/null 2>&1 || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$API_PID" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! command -v flutter >/dev/null 2>&1 && [[ "$WEB_URL_EXPLICIT" != "true" ]]; then
  if [[ "$REQUIRE_FLUTTER" == "true" ]]; then
    echo "Flutter SDK is required for Flutter web smoke." >&2
    exit 2
  fi
  echo "Flutter SDK is not available; skipping Flutter web smoke."
  exit 0
fi

if ! command -v npx >/dev/null 2>&1 || [[ ! -x "$PWCLI" ]]; then
  if [[ "$REQUIRE_BROWSER" == "true" ]]; then
    echo "npx and the Playwright CLI wrapper are required for Flutter web smoke." >&2
    exit 2
  fi
  echo "Playwright CLI is not available; skipping Flutter web smoke."
  exit 0
fi

if [[ "$WEB_URL_EXPLICIT" != "true" ]] && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use. Pass --port with a free port." >&2
  exit 2
fi
if [[ "$START_API" == "true" ]] && lsof -nP -iTCP:"$API_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "API port $API_PORT is already in use. Pass --api-port with a free port." >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

if [[ "$START_API" == "true" ]]; then
  if [[ "$API_BASE_URL_EXPLICIT" != "true" ]]; then
    API_BASE_URL="http://$HOST:$API_PORT"
  fi
  echo "Starting local API on $API_BASE_URL for Flutter browser smoke..."
  (
    cd "$ROOT"
    env \
      KEY_VAULT_URL="" \
      DB_DSN="" \
      IOS_API_KEY="$SMOKE_API_KEY" \
      API_BEARER_TOKEN="" \
      LALA_ENABLE_LIVE_AI="false" \
      LALA_ENABLE_LIVE_SPEECH="false" \
      CORS_ALLOW_ORIGINS="$WEB_ORIGIN" \
      LOG_LEVEL="INFO" \
      "$PYTHON" -m uvicorn apps.api.app.main:app \
        --host "$HOST" \
        --port "$API_PORT" \
        --no-access-log
  ) >"$API_LOG" 2>&1 &
  API_PID="$!"

  for _ in {1..80}; do
    if curl -fsS "$API_BASE_URL/healthz" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
  if ! curl -fsS "$API_BASE_URL/healthz" >/dev/null 2>&1; then
    echo "Local API did not become healthy. See $API_LOG" >&2
    tail -80 "$API_LOG" >&2 || true
    exit 1
  fi
fi

if [[ "$WEB_URL_EXPLICIT" == "true" ]]; then
  echo "Opening deployed Flutter web site at $TARGET_URL ..."
else
  echo "Building Flutter web release bundle for browser smoke..."
  FLUTTER_BUILD_ARGS=(
    build
    web
    --release
    --no-wasm-dry-run
    --dart-define
    "LALA_API_BASE_URL=$API_BASE_URL"
  )
  if [[ "$START_API" == "true" ]]; then
    FLUTTER_BUILD_ARGS+=(--dart-define "LALA_IOS_API_KEY=$SMOKE_API_KEY")
  fi
  if [[ -n "${KAKAO_JAVASCRIPT_KEY:-}" ]]; then
    FLUTTER_BUILD_ARGS+=(--dart-define "KAKAO_JAVASCRIPT_KEY=$KAKAO_JAVASCRIPT_KEY")
  fi
  (cd "$APP_DIR" && flutter "${FLUTTER_BUILD_ARGS[@]}")

  echo "Serving Flutter web bundle on $WEB_ORIGIN ..."
  (cd "$BUILD_DIR" && "$PYTHON" -m http.server "$PORT" --bind "$HOST" >"$WEB_LOG" 2>&1) &
  SERVER_PID="$!"

  for _ in {1..40}; do
    if curl -fsS "$WEB_ORIGIN/" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
  curl -fsS "$WEB_ORIGIN/" >/dev/null
fi

"$PWCLI" -s="$PW_SESSION" open "$TARGET_URL" >/dev/null
if [[ "$WEB_URL_EXPLICIT" == "true" ]]; then
  "$PWCLI" -s="$PW_SESSION" resize 390 844 >/dev/null
else
  "$PWCLI" -s="$PW_SESSION" resize 1280 900 >/dev/null
fi

RUNTIME_STATE="$("$PWCLI" -s="$PW_SESSION" eval 'async () => {
  const selector = "flutter-view, flt-glass-pane, flt-scene-host";
  for (let index = 0; index < 80; index += 1) {
    if (document.querySelector(selector)) {
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return {
    title: document.title,
    hasFlutterEntrypoint: Boolean(document.querySelector(selector)),
    bodyLength: document.body ? document.body.innerHTML.length : 0,
    readyState: document.readyState
  };
}' --raw)"
printf '%s\n' "$RUNTIME_STATE" >"$OUTPUT_DIR/flutter-web-runtime.json"

RUNTIME_STATE="$RUNTIME_STATE" "$PYTHON" - <<'PY'
import json
import os
import sys

try:
    state = json.loads(os.environ["RUNTIME_STATE"])
except Exception as exc:
    raw = os.environ.get("RUNTIME_STATE", "")
    raise SystemExit(
        f"Could not parse Flutter runtime state: {exc}; raw={raw[:200]!r}"
    ) from exc

if state.get("title") != "LALA":
    raise SystemExit(f"Unexpected Flutter web title: {state.get('title')!r}")
if not state.get("hasFlutterEntrypoint"):
    raise SystemExit("Flutter web entrypoint was not present in the rendered DOM.")
if int(state.get("bodyLength") or 0) < 100:
    raise SystemExit("Flutter web document body looked unexpectedly small.")
PY

"$PWCLI" -s="$PW_SESSION" snapshot >"$OUTPUT_DIR/flutter-web-snapshot.txt"
"$PWCLI" -s="$PW_SESSION" screenshot >"$OUTPUT_DIR/flutter-web-screenshot.txt"
"$PWCLI" -s="$PW_SESSION" console >"$OUTPUT_DIR/flutter-web-console.txt"

RUN_LOCATION_FLOW="false"
if [[ "$START_API" == "true" || "$API_BASE_URL_EXPLICIT" == "true" || "$WEB_URL_EXPLICIT" == "true" ]]; then
  RUN_LOCATION_FLOW="true"
fi
EXPECT_DOCENT_SCRIPT="false"
if [[ "$API_BASE_URL_EXPLICIT" == "true" || "$WEB_URL_EXPLICIT" == "true" ]]; then
  EXPECT_DOCENT_SCRIPT="true"
fi

if [[ "$RUN_LOCATION_FLOW" == "true" ]]; then
  echo "Driving Flutter web location flow with test geolocation..."
  "$PWCLI" -s="$PW_SESSION" run-code "async (page) => {
    await page.context().grantPermissions(['geolocation'], { origin: '$WEB_ORIGIN' });
    await page.context().setGeolocation({ latitude: $SMOKE_LAT, longitude: $SMOKE_LNG });
    await page.reload({ waitUntil: 'domcontentloaded' });
    const selector = 'flutter-view, flt-glass-pane, flt-scene-host';
    for (let index = 0; index < 80; index += 1) {
      if (await page.locator(selector).count()) {
        break;
      }
      await page.waitForTimeout(250);
    }
    await page.waitForTimeout(15000);
    return { url: page.url(), viewport: page.viewportSize() || { width: 1280, height: 900 } };
  }" >"$OUTPUT_DIR/flutter-web-location-flow.txt"

  REQUEST_LOG="$OUTPUT_DIR/flutter-web-requests.txt"
  for _ in {1..60}; do
    "$PWCLI" -s="$PW_SESSION" requests >"$REQUEST_LOG"
    if REQUEST_LOG="$REQUEST_LOG" EXPECT_DOCENT_SCRIPT="$EXPECT_DOCENT_SCRIPT" "$PYTHON" - <<'PY'
import os
from pathlib import Path

log = Path(os.environ["REQUEST_LOG"]).read_text(encoding="utf-8", errors="replace")
required_paths = [
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
    "/api/v1/plans/daily",
]
if os.environ.get("EXPECT_DOCENT_SCRIPT") == "true":
    required_paths.append("/api/v1/docents/script")
lines = log.splitlines()
missing = [
    path
    for path in required_paths
    if not any(path in line and "=> [200]" in line for line in lines)
]
if missing:
    raise SystemExit(1)
location_paths = [
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
]
missing_location = [
    path
    for path in location_paths
    if not any(
        path in line
        and "=> [200]" in line
        and "lat=37.5665" in line
        and "lng=126.978" in line
        for line in lines
    )
]
if missing_location:
    raise SystemExit(1)
if "lat=37.2636" in log or "lng=127.0286" in log:
    raise SystemExit(1)
PY
    then
      break
    fi
    sleep 0.5
  done
  REQUEST_LOG="$REQUEST_LOG" EXPECT_DOCENT_SCRIPT="$EXPECT_DOCENT_SCRIPT" "$PYTHON" - <<'PY'
import os
from pathlib import Path

log = Path(os.environ["REQUEST_LOG"]).read_text(encoding="utf-8", errors="replace")
required_paths = [
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
    "/api/v1/plans/daily",
]
if os.environ.get("EXPECT_DOCENT_SCRIPT") == "true":
    required_paths.append("/api/v1/docents/script")
lines = log.splitlines()
missing = [
    path
    for path in required_paths
    if not any(path in line and "=> [200]" in line for line in lines)
]
if missing:
    raise SystemExit(
        "Flutter location flow did not observe successful expected API requests: "
        + ", ".join(missing)
    )
location_paths = [
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
]
missing_location = [
    path
    for path in location_paths
    if not any(
        path in line
        and "=> [200]" in line
        and "lat=37.5665" in line
        and "lng=126.978" in line
        for line in lines
    )
]
if missing_location:
    raise SystemExit(
        "Flutter location flow did not use the granted test geolocation for: "
        + ", ".join(missing_location)
    )
if "lat=37.2636" in log or "lng=127.0286" in log:
    raise SystemExit("Flutter location flow still used the default location.")
if any(token in log.lower() for token in ("mock://", "placeholder://", "dummy://")):
    raise SystemExit("Flutter location flow request log contained mock-like URLs.")
PY
  "$PWCLI" -s="$PW_SESSION" console >"$OUTPUT_DIR/flutter-web-console.txt"
fi

if [[ "$FAIL_ON_CONSOLE_ERROR" == "true" ]] && grep -Eiq "^(\[error\]|error|pageerror|exception)" "$OUTPUT_DIR/flutter-web-console.txt"; then
  echo "Flutter web console reported an error. See $OUTPUT_DIR/flutter-web-console.txt" >&2
  exit 1
fi

if [[ "$START_API" == "true" ]]; then
  REQUIRED_API_PATHS=(
    "/healthz"
    "/readyz"
    "/api/v1/places"
    "/api/v1/weather"
    "/api/v1/plans/intervention"
    "/api/v1/plans/daily"
  )
  for _ in {1..80}; do
    missing_path=""
    for required_path in "${REQUIRED_API_PATHS[@]}"; do
      if ! grep -F "path=$required_path " "$API_LOG" >/dev/null 2>&1; then
        missing_path="$required_path"
        break
      fi
    done
    if [[ -z "$missing_path" ]]; then
      break
    fi
    sleep 0.25
  done
  API_LOG="$API_LOG" "$PYTHON" - <<'PY'
import os
from pathlib import Path

log = Path(os.environ["API_LOG"]).read_text(encoding="utf-8", errors="replace")
required_paths = [
    "/healthz",
    "/readyz",
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
    "/api/v1/plans/daily",
]
missing = [path for path in required_paths if f"path={path} " not in log]
if missing:
    raise SystemExit(
        "Local API did not observe expected Flutter route hits: "
        + ", ".join(missing)
    )
PY
fi

echo "Flutter web browser smoke completed."
if [[ "$RUN_LOCATION_FLOW" == "true" ]]; then
  echo "Artifacts: $OUTPUT_DIR/flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt, flutter-web-requests.txt"
else
  echo "Artifacts: $OUTPUT_DIR/flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt"
fi
if [[ "$START_API" == "true" ]]; then
  echo "Local API log: $API_LOG"
fi
