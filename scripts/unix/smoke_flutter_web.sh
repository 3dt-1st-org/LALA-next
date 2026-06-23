#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

REQUIRE_FLUTTER="false"
REQUIRE_BROWSER="false"
FAIL_ON_CONSOLE_ERROR="false"
CHECK_LOCATION_DENIAL_FALLBACK="false"
WAIT_FOR_BUILD_SHA="false"
START_API="false"
PORT="8099"
API_PORT="18080"
HOST="127.0.0.1"
API_BASE_URL="http://127.0.0.1:8080"
API_BASE_URL_EXPLICIT="false"
WEB_URL=""
WEB_URL_EXPLICIT="false"
EXPECT_BUILD_SHA=""
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
    --check-location-denial-fallback)
      CHECK_LOCATION_DENIAL_FALLBACK="true"
      shift
      ;;
    --expect-build-sha)
      EXPECT_BUILD_SHA="${2:-}"
      shift 2
      ;;
    --wait-for-build-sha)
      WAIT_FOR_BUILD_SHA="true"
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
    --smoke-lat)
      SMOKE_LAT="${2:-}"
      shift 2
      ;;
    --smoke-lng)
      SMOKE_LNG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/smoke_flutter_web.sh [--require-flutter] [--require-browser] [--fail-on-console-error] [--check-location-denial-fallback] [--expect-build-sha SHA] [--wait-for-build-sha] [--start-api] [--api-base-url URL] [--web-url URL] [--api-port PORT] [--port PORT] [--smoke-lat LAT] [--smoke-lng LNG]"
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
CODEX_PWCLI="${CODEX_HOME:-$HOME/.codex}/skills/playwright/scripts/playwright_cli.sh"
PWCLI=""
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

mkdir -p "$OUTPUT_DIR"

if command -v npx >/dev/null 2>&1; then
  if [[ -x "$CODEX_PWCLI" ]]; then
    PWCLI="$CODEX_PWCLI"
  else
    PWCLI="$OUTPUT_DIR/playwright_cli_npx_wrapper.sh"
    cat >"$PWCLI" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

has_session_flag="false"
for arg in "$@"; do
  case "$arg" in
    --session|--session=*|-s|--session-id|--session-id=*)
      has_session_flag="true"
      break
      ;;
  esac
done

cmd=(npx --yes --package @playwright/cli playwright-cli)
if [[ "${has_session_flag}" != "true" && -n "${PLAYWRIGHT_CLI_SESSION:-}" ]]; then
  cmd+=(--session "${PLAYWRIGHT_CLI_SESSION}")
fi
cmd+=("$@")

exec "${cmd[@]}"
SH
    chmod +x "$PWCLI"
  fi
fi

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
  if [[ -n "$PWCLI" && -x "$PWCLI" ]]; then
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

if [[ -z "$PWCLI" || ! -x "$PWCLI" ]]; then
  if [[ "$REQUIRE_BROWSER" == "true" ]]; then
    echo "npx is required for Flutter web smoke." >&2
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
    --pwa-strategy=none
    --no-wasm-dry-run
    --dart-define
    "LALA_API_BASE_URL=$API_BASE_URL"
  )
  if [[ -n "${GITHUB_SHA:-}" ]]; then
    FLUTTER_BUILD_ARGS+=(--dart-define "LALA_BUILD_SHA=$GITHUB_SHA")
  fi
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

RUN_LOCATION_FLOW="false"
if [[ "$START_API" == "true" || "$API_BASE_URL_EXPLICIT" == "true" || "$WEB_URL_EXPLICIT" == "true" ]]; then
  RUN_LOCATION_FLOW="true"
fi
EXPECT_DOCENT_SCRIPT="false"
if [[ "$API_BASE_URL_EXPLICIT" == "true" || "$WEB_URL_EXPLICIT" == "true" ]]; then
  EXPECT_DOCENT_SCRIPT="true"
fi

if [[ "$RUN_LOCATION_FLOW" == "true" ]]; then
  "$PWCLI" -s="$PW_SESSION" open "about:blank" >/dev/null
else
  "$PWCLI" -s="$PW_SESSION" open "$TARGET_URL" >/dev/null
fi
if [[ "$WEB_URL_EXPLICIT" == "true" ]]; then
  "$PWCLI" -s="$PW_SESSION" resize 390 844 >/dev/null
else
  "$PWCLI" -s="$PW_SESSION" resize 1280 900 >/dev/null
fi
if [[ "$RUN_LOCATION_FLOW" == "true" ]]; then
  "$PWCLI" -s="$PW_SESSION" run-code "async (page) => {
    await page.context().grantPermissions(['geolocation'], { origin: '$WEB_ORIGIN' });
    await page.context().setGeolocation({ latitude: $SMOKE_LAT, longitude: $SMOKE_LNG });
    await page.goto('$TARGET_URL', { waitUntil: 'domcontentloaded' });
  }" >/dev/null
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

if [[ -n "$EXPECT_BUILD_SHA" ]]; then
  if [[ "$WAIT_FOR_BUILD_SHA" == "true" ]]; then
    echo "Waiting for deployed Flutter web build SHA $EXPECT_BUILD_SHA ..."
  else
    echo "Checking Flutter web build SHA $EXPECT_BUILD_SHA ..."
  fi
  BUILD_STATE="$("$PWCLI" -s="$PW_SESSION" run-code "async (page) => {
    const expected = '$EXPECT_BUILD_SHA';
    const waitForBuild = $([[ "$WAIT_FOR_BUILD_SHA" == "true" ]] && echo "true" || echo "false");
    const maxAttempts = waitForBuild ? 60 : 1;
    const selector = 'flutter-view, flt-glass-pane, flt-scene-host';
    let lastState = {};
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      for (let index = 0; index < 80; index += 1) {
        if (await page.locator(selector).count()) {
          break;
        }
        await page.waitForTimeout(250);
      }
      for (let index = 0; index < 40; index += 1) {
        lastState = await page.evaluate(() => window.__lalaAppState || {});
        if (String(lastState.buildSha || '') === expected) {
          return {
            expected,
            matched: true,
            attempts: attempt,
            state: lastState,
            url: page.url()
          };
        }
        await page.waitForTimeout(250);
      }
      if (attempt < maxAttempts) {
        await page.waitForTimeout(10000);
        await page.reload({ waitUntil: 'domcontentloaded' });
      }
    }
    return {
      expected,
      matched: false,
      attempts: maxAttempts,
      state: lastState,
      url: page.url()
    };
  }")"
  printf '%s\n' "$BUILD_STATE" >"$OUTPUT_DIR/flutter-web-build-state.json"
  BUILD_STATE="$BUILD_STATE" "$PYTHON" - <<'PY'
import json
import os

raw = os.environ["BUILD_STATE"]
try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    marker = "### Result"
    marker_index = raw.find(marker)
    start = raw.find("{", marker_index if marker_index >= 0 else 0)
    if start < 0:
        raise SystemExit(
            "Flutter build SHA check produced no JSON result. Raw output starts: "
            + raw[:200].replace("\n", "\\n")
        )
    payload, _ = json.JSONDecoder().raw_decode(raw[start:])
state = payload.get("state") if isinstance(payload.get("state"), dict) else {}
if payload.get("matched") is not True:
    expected = str(payload.get("expected") or "")
    observed = str(state.get("buildSha") or "")
    attempts = payload.get("attempts")
    raise SystemExit(
        "Flutter web build SHA did not match the expected deployment. "
        f"expected={expected!r} observed={observed!r} attempts={attempts}"
    )
PY
fi

"$PWCLI" -s="$PW_SESSION" snapshot >"$OUTPUT_DIR/flutter-web-snapshot.txt"
"$PWCLI" -s="$PW_SESSION" screenshot >"$OUTPUT_DIR/flutter-web-screenshot.txt"
"$PWCLI" -s="$PW_SESSION" console >"$OUTPUT_DIR/flutter-web-console.txt"

if [[ "$RUN_LOCATION_FLOW" == "true" ]]; then
  echo "Driving Flutter web location flow with test geolocation..."
  "$PWCLI" -s="$PW_SESSION" run-code "async (page) => {
    const capturedResponses = [];
    await page.addInitScript(() => {
      window.__lalaSmokeApiResponses = [];
    });
    page.on('response', async (response) => {
      const url = response.url();
      if (!url.includes('/api/v1/')) {
        return;
      }
      let payload = null;
      try {
        payload = await response.json();
      } catch (_) {
        return;
      }
      const entry = {
        url,
        status: response.status(),
        payload,
      };
      capturedResponses.push(entry);
    });
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
    await page.evaluate((items) => {
      window.__lalaSmokeApiResponses = items;
    }, capturedResponses);
    return {
      url: page.url(),
      viewport: page.viewportSize() || { width: 1280, height: 900 },
      capturedResponseCount: capturedResponses.length
    };
  }" >"$OUTPUT_DIR/flutter-web-location-flow.txt"

  API_RESPONSE_STATE="$("$PWCLI" -s="$PW_SESSION" eval '() => window.__lalaSmokeApiResponses || []' --raw)"
  printf '%s\n' "$API_RESPONSE_STATE" >"$OUTPUT_DIR/flutter-web-api-responses.json"

  REQUEST_LOG="$OUTPUT_DIR/flutter-web-requests.txt"
  for _ in {1..120}; do
    "$PWCLI" -s="$PW_SESSION" requests >"$REQUEST_LOG"
    if REQUEST_LOG="$REQUEST_LOG" EXPECT_DOCENT_SCRIPT="$EXPECT_DOCENT_SCRIPT" SMOKE_LAT="$SMOKE_LAT" SMOKE_LNG="$SMOKE_LNG" "$PYTHON" - <<'PY'
import os
from pathlib import Path

log = Path(os.environ["REQUEST_LOG"]).read_text(encoding="utf-8", errors="replace")

def compact_coord(value: str) -> str:
    return f"{float(value):.6f}".rstrip("0").rstrip(".")

smoke_lat = compact_coord(os.environ["SMOKE_LAT"])
smoke_lng = compact_coord(os.environ["SMOKE_LNG"])
required_paths = [
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
    "/api/v1/plans/daily",
]
if os.environ.get("EXPECT_DOCENT_SCRIPT") == "true":
    # The deployed UI may defer the first docent request until after the map and
    # sheets settle. The response validator below still verifies docent quality
    # from the same live place/weather context.
    pass
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
        and f"lat={smoke_lat}" in line
        and f"lng={smoke_lng}" in line
        for line in lines
    )
]
if missing_location:
    raise SystemExit(1)
if smoke_lat != "37.2636" and "lat=37.2636" in log:
    raise SystemExit(1)
if smoke_lng != "127.0286" and "lng=127.0286" in log:
    raise SystemExit(1)
PY
    then
      break
    fi
    sleep 0.5
  done
  REQUEST_LOG="$REQUEST_LOG" EXPECT_DOCENT_SCRIPT="$EXPECT_DOCENT_SCRIPT" SMOKE_LAT="$SMOKE_LAT" SMOKE_LNG="$SMOKE_LNG" "$PYTHON" - <<'PY'
import os
from pathlib import Path

log = Path(os.environ["REQUEST_LOG"]).read_text(encoding="utf-8", errors="replace")

def compact_coord(value: str) -> str:
    return f"{float(value):.6f}".rstrip("0").rstrip(".")

smoke_lat = compact_coord(os.environ["SMOKE_LAT"])
smoke_lng = compact_coord(os.environ["SMOKE_LNG"])
required_paths = [
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
    "/api/v1/plans/daily",
]
if os.environ.get("EXPECT_DOCENT_SCRIPT") == "true":
    # Docent quality is verified below from the same live place/weather context.
    pass
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
        and f"lat={smoke_lat}" in line
        and f"lng={smoke_lng}" in line
        for line in lines
    )
]
if missing_location:
    raise SystemExit(
        "Flutter location flow did not use the granted test geolocation for: "
        + ", ".join(missing_location)
    )
if smoke_lat != "37.2636" and "lat=37.2636" in log:
    raise SystemExit("Flutter location flow still used the default location latitude.")
if smoke_lng != "127.0286" and "lng=127.0286" in log:
    raise SystemExit("Flutter location flow still used the default location longitude.")
if any(token in log.lower() for token in ("mock://", "placeholder://", "dummy://")):
    raise SystemExit("Flutter location flow request log contained mock-like URLs.")
PY

  RESPONSE_LOG="$OUTPUT_DIR/flutter-web-api-responses.json" REQUEST_LOG="$REQUEST_LOG" EXPECT_DOCENT_SCRIPT="$EXPECT_DOCENT_SCRIPT" "$PYTHON" - <<'PY'
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

response_path = Path(os.environ["RESPONSE_LOG"])
responses = json.loads(response_path.read_text(encoding="utf-8"))
if not isinstance(responses, list):
    raise SystemExit("Flutter API response capture was not a list.")
request_log = Path(os.environ["REQUEST_LOG"]).read_text(
    encoding="utf-8", errors="replace"
)

def entries_for(path):
    return [
        item
        for item in responses
        if isinstance(item, dict)
        and path in str(item.get("url") or "")
        and int(item.get("status") or 0) == 200
        and isinstance(item.get("payload"), dict)
    ]

def urls_for(path):
    urls = []
    for line in request_log.splitlines():
        if path not in line or "=> [200]" not in line:
            continue
        match = re.search(r"\[(?:GET|POST)\]\s+(https?://\S+)\s+=>\s+\[200\]", line)
        if match:
            urls.append(match.group(1))
    return urls

def request_json(method, url, body=None):
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    last_error = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.loads(response.read().decode("utf-8"))
                return response.status, payload
        except urllib.error.HTTPError as exc:
            try:
                payload = json.loads(exc.read().decode("utf-8"))
            except Exception:
                payload = {"ok": False, "error": {"message": str(exc)}}
            return exc.code, payload
        except (TimeoutError, urllib.error.URLError) as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
    raise TimeoutError(f"{method} {url} did not complete after retries: {last_error}")

def fetch_latest_get(path):
    for url in reversed(urls_for(path)):
        status, payload = request_json("GET", url)
        if status == 200 and isinstance(payload, dict):
            entry = {"url": url, "status": status, "payload": payload, "capture": "direct-refetch"}
            responses.append(entry)
            return entry
    return None

def data_for(path):
    matches = entries_for(path)
    if not matches and path != "/api/v1/docents/script":
        fetched = fetch_latest_get(path)
        if fetched:
            matches = [fetched]
    if not matches:
        raise SystemExit(f"Flutter location flow did not capture JSON for {path}.")
    payload = matches[-1]["payload"]
    if payload.get("ok") is not True:
        raise SystemExit(f"Flutter location flow captured non-ok JSON for {path}.")
    data = payload.get("data")
    if not isinstance(data, dict):
        raise SystemExit(f"Flutter location flow captured no data object for {path}.")
    return data

def source_code(value):
    return str(value or "").strip().lower()

def text(value):
    return str(value or "").strip()

def add_text(payload, key, value):
    value = text(value)
    if value:
        payload[key] = value

def add_int(payload, key, value):
    if isinstance(value, bool):
        return
    if isinstance(value, int):
        payload[key] = value
        return
    if isinstance(value, float) and value.is_integer():
        payload[key] = int(value)
        return
    value = text(value)
    if not value:
        return
    try:
        payload[key] = int(float(value))
    except ValueError:
        return

def add_score(payload, key, value):
    if isinstance(value, bool):
        return
    try:
        score = float(value)
    except (TypeError, ValueError):
        return
    if 0 <= score <= 1:
        payload[key] = score

def docent_category(value):
    value = text(value)
    if value in {"attraction", "restaurant", "event", "culture_venue"}:
        return value
    return "attraction"

def docent_body(place, weather):
    score = place.get("score") if isinstance(place.get("score"), dict) else {}
    components = (
        score.get("components") if isinstance(score.get("components"), dict) else {}
    )
    dust = weather.get("dust") if isinstance(weather.get("dust"), dict) else {}
    payload = {
        "place_id": text(place.get("place_id")) or text(place.get("id")),
        "category": docent_category(place.get("category")),
        "language": "ko",
        "mode": "brief",
    }
    add_text(payload, "place_name", place.get("name"))
    add_text(payload, "address", place.get("address"))
    add_text(payload, "region_ko", place.get("region_ko"))
    add_text(payload, "region_en", place.get("region_en"))
    add_text(payload, "source", place.get("source"))
    add_text(payload, "upstream_source", place.get("upstream_source"))
    add_int(payload, "distance_m", place.get("distance_m"))
    add_score(payload, "final_score", score.get("final_score"))
    add_score(payload, "local_spending_score", components.get("local_spending_score"))
    add_score(
        payload,
        "small_merchant_fit_score",
        components.get("small_merchant_fit_score"),
    )
    add_score(
        payload,
        "demand_dispersion_score",
        components.get("demand_dispersion_score"),
    )
    add_score(payload, "weather_fit_score", components.get("weather_fit_score"))
    add_score(
        payload,
        "culture_relevance_score",
        components.get("culture_relevance_score"),
    )
    add_text(payload, "weather_temp", weather.get("temp"))
    add_text(payload, "weather_icon", weather.get("icon"))
    add_text(payload, "weather_outdoor_status", weather.get("outdoor_status"))
    add_text(payload, "dust_grade", dust.get("grade_ko") or dust.get("grade"))
    add_text(payload, "dust_pm10", dust.get("pm10"))
    add_text(payload, "dust_pm25", dust.get("pm25"))
    add_text(payload, "dust_pm10_grade", dust.get("pm10_grade_ko") or dust.get("pm10_grade"))
    add_text(payload, "dust_pm25_grade", dust.get("pm25_grade_ko") or dust.get("pm25_grade"))
    return payload

def api_base_from_requests():
    urls = urls_for("/api/v1/places") or urls_for("/api/v1/weather")
    if not urls:
        raise SystemExit("Flutter location flow had no API URL to derive a base from.")
    parsed = urllib.parse.urlparse(urls[-1])
    return f"{parsed.scheme}://{parsed.netloc}"

def live_docent_data(place, weather):
    matches = entries_for("/api/v1/docents/script")
    if matches:
        payload = matches[-1]["payload"]
    else:
        url = f"{api_base_from_requests()}/api/v1/docents/script"
        status, payload = request_json("POST", url, body=docent_body(place, weather))
        responses.append(
            {
                "url": url,
                "status": status,
                "payload": payload,
                "capture": "direct-live-context",
            }
        )
        if status != 200:
            raise SystemExit(f"Flutter live-context docent request returned {status}.")
    if payload.get("ok") is not True:
        raise SystemExit("Flutter docent script response was non-ok.")
    data = payload.get("data")
    if not isinstance(data, dict):
        raise SystemExit("Flutter docent script response missed a data object.")
    return data

fallback_sources = {
    "public_mvp_snapshot",
    "demo_fallback",
    "demo_seed",
    "dev_seed",
    "fallback",
    "local_fixture",
    "skeleton",
    "unavailable",
}

places = data_for("/api/v1/places")
if places.get("source") != "db":
    raise SystemExit("Flutter places response was not DB-backed.")
if places.get("location_engine") != "postgis":
    raise SystemExit("Flutter places response did not use PostGIS.")
place_items = places.get("places")
if not isinstance(place_items, list) or not place_items:
    raise SystemExit("Flutter places response was empty.")
for place in place_items:
    if not isinstance(place, dict):
        continue
    if source_code(place.get("source")) in fallback_sources:
        raise SystemExit("Flutter places response contained fallback place rows.")
    if source_code(place.get("upstream_source")) in {"dev_seed", "local_fixture"}:
        raise SystemExit("Flutter places response contained fixture upstream rows.")

weather = data_for("/api/v1/weather")
if "airkorea" not in source_code(weather.get("source")):
    raise SystemExit("Flutter weather response did not include AirKorea source.")
if not str(weather.get("air_quality_location") or "").strip():
    raise SystemExit("Flutter weather response missed an air quality station label.")
dust = weather.get("dust")
if not isinstance(dust, dict):
    raise SystemExit("Flutter weather response missed dust data.")
pm10 = str(dust.get("pm10") or "").strip()
pm25 = str(dust.get("pm25") or "").strip()
if not pm10 or not pm25 or pm10 in {"-", "--"} or pm25 in {"-", "--"}:
    raise SystemExit("Flutter weather response missed PM10/PM2.5 values.")

if os.environ.get("EXPECT_DOCENT_SCRIPT") == "true":
    first_place = next((place for place in place_items if isinstance(place, dict)), {})
    docent = live_docent_data(first_place, weather)
    if source_code(docent.get("source")) in fallback_sources:
        raise SystemExit("Flutter docent response came from fallback source.")
    script = str(docent.get("script") or "")
    lowered = script.lower()
    if any(token in lowered for token in ("mock", "demo", "placeholder", "skeleton")):
        raise SystemExit("Flutter docent script contained placeholder wording.")
    docent_place_id = text(docent.get("place_id"))
    docent_place = first_place
    if docent_place_id:
        for place in place_items:
            if not isinstance(place, dict):
                continue
            if docent_place_id in {
                text(place.get("place_id")),
                text(place.get("id")),
            }:
                docent_place = place
                break
    place_name = text(docent_place.get("name"))
    if place_name and place_name not in script:
        raise SystemExit("Flutter docent script did not include the live place name.")
    grounding_count = docent.get("grounding_count")
    if not isinstance(grounding_count, int) or grounding_count < 1:
        raise SystemExit("Flutter docent response missed live grounding context.")
    grounding_sources = docent.get("grounding_sources")
    if not isinstance(grounding_sources, list) or not grounding_sources:
        raise SystemExit("Flutter docent response missed grounding source labels.")
    internal_terms = (
        "종합 추천 점수",
        "최종 추천 점수",
        "장소 지식 인덱스",
        "°C°C",
        "culture_venue",
        "tour_api",
        "dev_seed",
        "local_fixture",
        "public_mvp_snapshot",
        "snapshot",
    )
    if any(term in script for term in internal_terms) or "스냅샷" in script:
        raise SystemExit("Flutter docent script exposed internal evidence labels.")
    if re.search(
        r"(추천 점수|내국인 소비|관광 수요 분산|날씨 적합도|리뷰 품질|문화 연계)"
        r"(?:는|은|:)?\s*\d",
        script,
    ):
        raise SystemExit("Flutter docent script exposed raw score values.")
    if not any(term in script for term in ("내국인 소비", "로컬 소비", "지역 소비")):
        raise SystemExit("Flutter docent script missed local spending context.")
    if not any(term in script for term in ("소상공인", "상권", "골목", "로컬 카페", "카페", "식당")):
        raise SystemExit("Flutter docent script missed small merchant route context.")
    if not any(term in script for term in ("공식", "한국관광공사", "문화정보원", "공연예술통합전산망", "운영 DB")):
        raise SystemExit("Flutter docent script missed official data grounding.")
    if not any(term in script for term in ("방문 전후", "동선", "이어", "함께 연결")):
        raise SystemExit("Flutter docent script missed route action context.")
    if not re.search(rf"PM10\s*{re.escape(pm10)}(?!\d)", script):
        raise SystemExit("Flutter docent script did not include the captured PM10 value.")
    if not re.search(rf"PM2\.5\s*{re.escape(pm25)}(?!\d)", script):
        raise SystemExit("Flutter docent script did not include the captured PM2.5 value.")

response_path.write_text(
    json.dumps(responses, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

  MARKER_STATE="$("$PWCLI" -s="$PW_SESSION" eval 'async () => {
    function currentState() {
      const container = document.getElementById("lala-kakao-background-map");
      const pinCount = document.querySelectorAll(".lala-marker-pin").length;
      const clusterCount = document.querySelectorAll(".lala-marker-cluster").length;
      const stats = window.__lalaLastMapMarkerStats || {};
      return { container, pinCount, clusterCount, stats };
    }
    let state = currentState();
    for (let index = 0; index < 80; index += 1) {
      const statPins = Number(state.stats.pins || 0);
      if (Math.max(state.pinCount, statPins) > 0) {
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
      state = currentState();
    }
    const sampleMarkers = Array.from(document.querySelectorAll(".lala-marker"))
      .slice(0, 8)
      .map((marker) => ({
        id: marker.getAttribute("data-lala-place-id") || marker.dataset.lalaPlaceId || "",
        category: marker.getAttribute("data-lala-category") || marker.dataset.lalaCategory || "",
        clusterCount: marker.getAttribute("data-lala-cluster-count") || marker.dataset.lalaClusterCount || "",
        title: marker.getAttribute("title") || ""
      }));
    return {
      pinCount: state.pinCount,
      clusterCount: state.clusterCount,
      stats: state.stats,
      mapLevel: state.container ? state.container.getAttribute("data-lala-map-level") : null,
      containerPins: state.container ? state.container.getAttribute("data-lala-marker-pins") : null,
      containerClusters: state.container ? state.container.getAttribute("data-lala-marker-clusters") : null,
      sampleMarkers
    };
  }' --raw)"
  printf '%s\n' "$MARKER_STATE" >"$OUTPUT_DIR/flutter-web-marker-state.json"
  MARKER_STATE="$MARKER_STATE" "$PYTHON" - <<'PY'
import json
import os

try:
    state = json.loads(os.environ["MARKER_STATE"])
except Exception as exc:
    raw = os.environ.get("MARKER_STATE", "")
    raise SystemExit(
        f"Could not parse Flutter marker state: {exc}; raw={raw[:200]!r}"
    ) from exc

stats = state.get("stats") if isinstance(state.get("stats"), dict) else {}
pin_count = int(state.get("pinCount") or 0)
cluster_count = int(state.get("clusterCount") or 0)
stat_pins = int(stats.get("pins") or 0)
stat_clusters = int(stats.get("clusters") or 0)
stat_total = int(stats.get("total") or 0)
map_level = int(stats.get("level") or state.get("mapLevel") or 0)
if max(pin_count, stat_pins) <= 0:
    raise SystemExit("Flutter location flow rendered no real map pins.")
if stat_total <= 0:
    raise SystemExit("Flutter location flow did not pass live places into the map.")
if max(cluster_count, stat_clusters) > 0 and max(pin_count, stat_pins) <= 0:
    raise SystemExit("Flutter location flow rendered only clusters without place pins.")
if map_level and map_level <= 8 and max(cluster_count, stat_clusters) > 0:
    raise SystemExit(
        "Flutter initial location map clustered places before the user zoomed out."
    )
if not state.get("sampleMarkers"):
    raise SystemExit("Flutter location flow marker sample was empty.")
PY

  if [[ "$CHECK_LOCATION_DENIAL_FALLBACK" == "true" ]]; then
    echo "Driving Flutter web denied-location fallback flow..."
    "$PWCLI" -s="$PW_SESSION" run-code "async (page) => {
      const capturedResponses = [];
      await page.context().clearPermissions();
      await page.addInitScript(() => {
        const denied = { code: 1, message: 'Location denied by LALA smoke test' };
        const geolocation = {
          getCurrentPosition(success, error) {
            setTimeout(() => {
              if (typeof error === 'function') {
                error(denied);
              }
            }, 0);
          },
          watchPosition(success, error) {
            setTimeout(() => {
              if (typeof error === 'function') {
                error(denied);
              }
            }, 0);
            return 1;
          },
          clearWatch() {}
        };
        try {
          Object.defineProperty(window.navigator, 'geolocation', {
            configurable: true,
            value: geolocation
          });
        } catch (_) {
          Object.defineProperty(Navigator.prototype, 'geolocation', {
            configurable: true,
            value: geolocation
          });
        }
      });
      page.on('response', async (response) => {
        const url = response.url();
        if (!url.includes('/api/v1/')) {
          return;
        }
        let payload = null;
        try {
          payload = await response.json();
        } catch (_) {
          return;
        }
        capturedResponses.push({
          url,
          status: response.status(),
          payload,
        });
      });
      const target = '$TARGET_URL';
      const separator = target.includes('?') ? '&' : '?';
      await page.goto(
        target + separator + 'location-denied-smoke=$PORT-$API_PORT',
        { waitUntil: 'domcontentloaded' }
      );
      const selector = 'flutter-view, flt-glass-pane, flt-scene-host';
      for (let index = 0; index < 80; index += 1) {
        if (await page.locator(selector).count()) {
          break;
        }
        await page.waitForTimeout(250);
      }
      const hasDefaultPublicDataResponses = () => {
        const requiredPaths = [
          '/api/v1/places',
          '/api/v1/weather',
          '/api/v1/plans/intervention',
        ];
        return requiredPaths.every((path) => capturedResponses.some((item) => {
          const url = String(item.url || '');
          return Number(item.status || 0) === 200
            && url.includes(path)
            && url.includes('lat=37.2636')
            && url.includes('lng=127.0286');
        }));
      };
      let state = {};
      for (let index = 0; index < 160; index += 1) {
        state = await page.evaluate(() => window.__lalaAppState || {});
        if (
          state.locationManualSelectAvailable
          && Number(state.apiPlacesCount || 0) > 0
          && hasDefaultPublicDataResponses()
        ) {
          break;
        }
        await page.waitForTimeout(250);
      }
      return {
        url: page.url(),
        state,
        capturedResponses,
      };
    }" >"$OUTPUT_DIR/flutter-web-location-denied-flow.json"

    DENIED_FLOW="$OUTPUT_DIR/flutter-web-location-denied-flow.json" "$PYTHON" - <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import parse_qs, urlparse

raw = Path(os.environ["DENIED_FLOW"]).read_text(encoding="utf-8")
try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    marker = "### Result"
    marker_index = raw.find(marker)
    start = raw.find("{", marker_index if marker_index >= 0 else 0)
    if start < 0:
        raise SystemExit(
            "Denied-location smoke produced no JSON result. Raw output starts: "
            + raw[:200].replace("\n", "\\n")
        )
    payload, _ = json.JSONDecoder().raw_decode(raw[start:])
state = payload.get("state") if isinstance(payload.get("state"), dict) else {}
responses = payload.get("capturedResponses")
if not isinstance(responses, list):
    raise SystemExit("Denied-location smoke did not capture API responses.")

if state.get("locationRequestInFlight"):
    raise SystemExit("Denied-location smoke was still waiting for location permission.")
if not state.get("locationFallbackNoticeVisible"):
    raise SystemExit("Denied-location smoke did not expose the location fallback notice.")
if not state.get("locationManualSelectAvailable"):
    raise SystemExit("Denied-location smoke did not expose manual location selection.")
if int(state.get("manualLocationOptionCount") or 0) < 200:
    raise SystemExit("Denied-location smoke did not expose nationwide manual locations.")
if int(state.get("apiPlacesCount") or 0) <= 0:
    raise SystemExit("Denied-location smoke did not continue with public map data.")
visible_error = str(state.get("visibleError") or "")
if "요청을 처리하지 못했습니다" in visible_error:
    raise SystemExit("Denied-location smoke exposed the generic request failure message.")

def compact(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")

default_lat = compact(37.2636)
default_lng = compact(127.0286)
required_paths = {
    "/api/v1/places",
    "/api/v1/weather",
    "/api/v1/plans/intervention",
}
seen = set()
for response in responses:
    if not isinstance(response, dict) or int(response.get("status") or 0) != 200:
        continue
    url = str(response.get("url") or "")
    parsed = urlparse(url)
    if parsed.path not in required_paths:
        continue
    query = parse_qs(parsed.query)
    lat = query.get("lat", [""])[0]
    lng = query.get("lng", [""])[0]
    try:
        normalized_lat = compact(float(lat))
        normalized_lng = compact(float(lng))
    except ValueError:
        continue
    if normalized_lat == default_lat and normalized_lng == default_lng:
        seen.add(parsed.path)

missing = sorted(required_paths - seen)
if missing:
    raise SystemExit(
        "Denied-location smoke did not continue with default public-data coordinates for: "
        + ", ".join(missing)
    )
PY
  fi
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
  echo "Artifacts: $OUTPUT_DIR/flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt, flutter-web-requests.txt, flutter-web-api-responses.json, flutter-web-marker-state.json"
else
  echo "Artifacts: $OUTPUT_DIR/flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt"
fi
if [[ "$START_API" == "true" ]]; then
  echo "Local API log: $API_LOG"
fi
