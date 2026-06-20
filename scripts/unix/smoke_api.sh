#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

BASE_URL="http://127.0.0.1:8080"
KEY_VAULT_URL_ARG=""
PAID_DEPENDENCY="false"
CORS_ORIGIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --key-vault-url) KEY_VAULT_URL_ARG="${2:-}"; shift 2 ;;
    --paid-dependency) PAID_DEPENDENCY="true"; shift ;;
    --cors-origin) CORS_ORIGIN="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/smoke_api.sh [--base-url URL] [--key-vault-url URL] [--cors-origin ORIGIN] [--paid-dependency]"
      echo "Set LALA_SMOKE_BEARER_TOKEN to smoke OAuth/JWT auth without changing server-side API_BEARER_TOKEN."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
PYTHON="$(select_python "")"
cd "$ROOT"

require_command curl

if [[ -n "$KEY_VAULT_URL_ARG" ]]; then
  export KEY_VAULT_URL="$KEY_VAULT_URL_ARG"
fi

load_env_file "$ROOT/.env"
load_lala_key_vault_secrets

smoke_get() {
  local path="$1"
  shift || true
  echo "GET $path" >&2
  curl -fsS "$@" "$BASE_URL$path" >/dev/null
}

smoke_readyz() {
  local payload
  echo "GET /readyz" >&2
  payload="$(curl -fsS "$BASE_URL/readyz")"
  READYZ_PAYLOAD_CACHE="$payload"
  READYZ_PAYLOAD="$payload" "$PYTHON" - <<'PY'
import json
import os

payload = json.loads(os.environ["READYZ_PAYLOAD"])
data = payload.get("data") or {}
status = data.get("status")
if status != "ok":
    raise SystemExit(f"/readyz reported non-ok status: {status or 'missing'}")
mode = data.get("mode") or {}
required = ("overall", "data", "ai", "speech", "worker")
missing = [name for name in required if not mode.get(name)]
if missing:
    raise SystemExit(f"/readyz is missing runtime mode fields: {', '.join(missing)}")
print(
    "runtime_mode="
    f"{mode['overall']} data={mode['data']} ai={mode['ai']} "
    f"speech={mode['speech']} worker={mode['worker']}"
)
checks = data.get("checks") or {}
missing_checks = [name for name in ("client_identity", "jwt_validation") if name not in checks]
if missing_checks:
    raise SystemExit(f"/readyz is missing identity checks: {', '.join(missing_checks)}")
print(
    "identity="
    f"{checks['client_identity']} jwt_validation={checks['jwt_validation']}"
)
PY
}

readyz_check() {
  local name="$1"
  READYZ_PAYLOAD="$READYZ_PAYLOAD_CACHE" "$PYTHON" - "$name" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["READYZ_PAYLOAD"])
checks = (payload.get("data") or {}).get("checks") or {}
print(checks.get(sys.argv[1]) or "")
PY
}

smoke_post_json() {
  local path="$1"
  local body="$2"
  shift 2
  echo "POST $path" >&2
  curl -fsS "$@" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$body" \
    "$BASE_URL$path"
}

smoke_post_audio() {
  local body="$1"
  shift
  local headers_file audio_file
  headers_file="$(mktemp)"
  audio_file="$(mktemp)"
  echo "POST /api/v1/docents/audio" >&2
  curl -fsS "$@" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$body" \
    -D "$headers_file" \
    -o "$audio_file" \
    "$BASE_URL/api/v1/docents/audio"
  if ! grep -i '^content-type: audio/mpeg' "$headers_file" >/dev/null; then
    rm -f "$headers_file" "$audio_file"
    echo "Audio smoke returned unexpected content type." >&2
    exit 1
  fi
  if [[ ! -s "$audio_file" ]]; then
    rm -f "$headers_file" "$audio_file"
    echo "Audio smoke returned an empty audio response." >&2
    exit 1
  fi
  rm -f "$headers_file" "$audio_file"
}

smoke_cors_preflight() {
  local origin="$1"
  local headers_file allow_origin
  headers_file="$(mktemp)"
  echo "OPTIONS /api/v1/places (CORS)" >&2
  if ! curl -fsS \
    -X OPTIONS \
    -H "Origin: $origin" \
    -H "Access-Control-Request-Method: GET" \
    -H "Access-Control-Request-Headers: Authorization, X-API-Key" \
    -D "$headers_file" \
    -o /dev/null \
    "$BASE_URL/api/v1/places"; then
    rm -f "$headers_file"
    echo "CORS preflight failed for configured origin." >&2
    exit 1
  fi
  allow_origin="$(tr -d '\r' < "$headers_file" | awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2; exit}')"
  rm -f "$headers_file"
  if [[ "$allow_origin" != "$origin" ]]; then
    echo "CORS preflight returned unexpected allow-origin." >&2
    exit 1
  fi
}

write_auth_config() {
  local header_name="$1"
  local header_value="$2"
  local config_file
  config_file="$(mktemp)"
  chmod 600 "$config_file"
  HEADER_NAME="$header_name" HEADER_VALUE="$header_value" "$PYTHON" - "$config_file" <<'PY'
import os
import sys
from pathlib import Path

name = os.environ["HEADER_NAME"]
value = os.environ["HEADER_VALUE"].replace("\\", "\\\\").replace('"', '\\"')
Path(sys.argv[1]).write_text(f'header = "{name}: {value}"\n', encoding="utf-8")
PY
  printf '%s\n' "$config_file"
}

smoke_get "/healthz"
smoke_readyz
smoke_get "/metrics"
smoke_get "/openapi.json"
if [[ -n "$CORS_ORIGIN" ]]; then
  smoke_cors_preflight "$CORS_ORIGIN"
fi

CLIENT_BEARER_TOKEN="${LALA_SMOKE_BEARER_TOKEN:-${API_BEARER_TOKEN:-}}"
CLIENT_API_KEY="${LALA_SMOKE_API_KEY:-${IOS_API_KEY:-}}"
SERVER_API_KEY_STATUS="$(readyz_check api_key)"
SERVER_BEARER_STATUS="$(readyz_check bearer_token)"
SERVER_CLIENT_AUTH_STATUS="$(readyz_check client_auth)"
SERVER_CLIENT_IDENTITY_STATUS="$(readyz_check client_identity)"

AUTH_CONFIG_FILE=""
AUTH_KIND=""
if [[ "$SERVER_CLIENT_AUTH_STATUS" == "public-contest" || "$SERVER_CLIENT_IDENTITY_STATUS" == "public-contest" ]]; then
  AUTH_KIND="public-contest"
elif [[ "$SERVER_BEARER_STATUS" == "configured" && -n "$CLIENT_BEARER_TOKEN" ]]; then
  AUTH_CONFIG_FILE="$(write_auth_config "Authorization" "Bearer $CLIENT_BEARER_TOKEN")"
  AUTH_KIND="bearer"
elif [[ "$SERVER_API_KEY_STATUS" == "configured" && -n "$CLIENT_API_KEY" ]]; then
  AUTH_CONFIG_FILE="$(write_auth_config "X-API-Key" "$CLIENT_API_KEY")"
  AUTH_KIND="api-key"
fi

if [[ -z "$AUTH_KIND" ]]; then
  if [[ "$PAID_DEPENDENCY" == "true" ]]; then
    echo "Matching client auth is required for paid dependency smoke. Set LALA_SMOKE_BEARER_TOKEN, LALA_SMOKE_API_KEY, IOS_API_KEY, API_BEARER_TOKEN, or KEY_VAULT_URL with credentials that match /readyz." >&2
    exit 1
  fi
  echo "Matching client auth is not available; authenticated /api/v1 smoke checks skipped."
  exit 0
fi

CURL_AUTH_ARGS=()
if [[ -n "$AUTH_CONFIG_FILE" ]]; then
  CURL_AUTH_ARGS=(-K "$AUTH_CONFIG_FILE")
  trap 'rm -f "$AUTH_CONFIG_FILE"' EXIT
fi

smoke_get "/api/v1/places?lat=37.2636&lng=127.0286&radius_m=1000" "${CURL_AUTH_ARGS[@]}"
smoke_get "/api/v1/weather?lat=37.2636&lng=127.0286" "${CURL_AUTH_ARGS[@]}"
smoke_get "/api/v1/plans/intervention?lat=37.2636&lng=127.0286&radius_m=1000" "${CURL_AUTH_ARGS[@]}"

PLAN_BODY='{"lat":37.2636,"lng":127.0286,"radius_m":1000,"language":"ko"}'
smoke_post_json "/api/v1/plans/daily" "$PLAN_BODY" "${CURL_AUTH_ARGS[@]}" >/dev/null

SCRIPT_BODY='{"place_id":"tour-api-3066000","place_name":"중랑아트센터","category":"culture_venue","language":"ko","mode":"brief"}'
smoke_post_json "/api/v1/docents/script" "$SCRIPT_BODY" "${CURL_AUTH_ARGS[@]}" >/dev/null

AUDIO_BODY='{"script":"LALA smoke audio","language":"ko"}'
smoke_post_audio "$AUDIO_BODY" "${CURL_AUTH_ARGS[@]}"

if [[ "$PAID_DEPENDENCY" == "true" ]]; then
  echo "Paid dependency smoke requested. Start the API with --enable-live-ai and --enable-live-speech before running this check."
  PAID_BODY='{"place_id":"paid-smoke-suwon","category":"attraction","language":"ko","mode":"brief"}'
  SCRIPT_RESULT="$(smoke_post_json "/api/v1/docents/script" "$PAID_BODY" "${CURL_AUTH_ARGS[@]}")"
  SCRIPT_TEXT="$(JSON_PAYLOAD="$SCRIPT_RESULT" "$PYTHON" - <<'PY'
import json
import os

payload = json.loads(os.environ["JSON_PAYLOAD"])
data = payload.get("data") or {}
if data.get("source") != "azure_openai":
    raise SystemExit(f"Expected Azure OpenAI script source, got {data.get('source')}.")
script = data.get("script") or ""
if not script:
    raise SystemExit("Azure OpenAI script smoke returned an empty script.")
print(script)
PY
)"
  AUDIO_BODY="$(SCRIPT_TEXT="$SCRIPT_TEXT" "$PYTHON" - <<'PY'
import json
import os

print(json.dumps({"script": os.environ["SCRIPT_TEXT"], "language": "ko"}, ensure_ascii=False))
PY
)"
  smoke_post_audio "$AUDIO_BODY" "${CURL_AUTH_ARGS[@]}"
  echo "Audio smoke returned audio/mpeg bytes."
fi

echo "LALA-next API smoke completed."
