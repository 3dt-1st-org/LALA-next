#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

HOST_NAME="0.0.0.0"
PORT="8080"
PYTHON_ARG=""
KEY_VAULT_URL_ARG=""
ENABLE_LIVE_AI="false"
ENABLE_LIVE_SPEECH="false"
ACCESS_LOG_PATH_ARG=""
GRACEFUL_TIMEOUT="20"
RUNTIME_PROFILE="${LALA_RUNTIME_PROFILE:-api}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-name) HOST_NAME="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --python) PYTHON_ARG="${2:-}"; shift 2 ;;
    --key-vault-url) KEY_VAULT_URL_ARG="${2:-}"; shift 2 ;;
    --runtime-profile) RUNTIME_PROFILE="${2:-}"; shift 2 ;;
    --access-log-path) ACCESS_LOG_PATH_ARG="${2:-}"; shift 2 ;;
    --graceful-timeout) GRACEFUL_TIMEOUT="${2:-}"; shift 2 ;;
    --enable-live-ai) ENABLE_LIVE_AI="true"; shift ;;
    --enable-live-speech) ENABLE_LIVE_SPEECH="true"; shift ;;
    -h|--help)
      echo "Usage: scripts/unix/start_api.sh [--runtime-profile local|ci|api|worker] [--host-name HOST] [--port PORT] [--key-vault-url URL] [--access-log-path PATH] [--graceful-timeout SEC] [--enable-live-ai] [--enable-live-speech] [--python PATH]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
PYTHON="$(select_python "$PYTHON_ARG")"
cd "$ROOT"
case "$RUNTIME_PROFILE" in
  local|ci|api|worker) ;;
  *) echo "Unsupported runtime profile: $RUNTIME_PROFILE" >&2; exit 2 ;;
esac
export LALA_RUNTIME_PROFILE="$RUNTIME_PROFILE"

if [[ "$RUNTIME_PROFILE" == "local" ]]; then
  if [[ -n "$KEY_VAULT_URL_ARG" ]]; then
    export KEY_VAULT_URL="$KEY_VAULT_URL_ARG"
  fi
  load_env_file "$ROOT/.env"
  load_lala_key_vault_secrets
  if [[ -n "${KEY_VAULT_URL:-}" ]]; then
    echo "Key Vault secret preload: api_key=$(env_status IOS_API_KEY), bearer_token=$(env_status API_BEARER_TOKEN), oauth_issuer=$(env_status OAUTH_ISSUER), oauth_client_id=$(env_status OAUTH_CLIENT_ID), openai_key=$(env_status OPENAI_API_KEY), speech_key=$(env_status AZURE_SPEECH_KEY), cors_origins=$(env_status CORS_ALLOW_ORIGINS)"
  fi
elif [[ -n "$KEY_VAULT_URL_ARG" ]]; then
  echo "--key-vault-url is allowed only with --runtime-profile local; operational profiles use AWS IAM." >&2
  exit 2
fi
if [[ -n "$ACCESS_LOG_PATH_ARG" ]]; then
  export LALA_ACCESS_LOG_PATH="$ACCESS_LOG_PATH_ARG"
fi

if [[ "$ENABLE_LIVE_AI" == "true" ]]; then
  export LALA_ENABLE_LIVE_AI=true
fi
if [[ "$ENABLE_LIVE_SPEECH" == "true" ]]; then
  export LALA_ENABLE_LIVE_SPEECH=true
fi

echo "Starting LALA-next API on $HOST_NAME:$PORT"
echo "Runtime profile: $RUNTIME_PROFILE"
echo "Health endpoint: http://127.0.0.1:$PORT/healthz"
echo "Python executable: $PYTHON"
echo "JSONL access log: $(env_status LALA_ACCESS_LOG_PATH)"
echo "Graceful shutdown timeout: $GRACEFUL_TIMEOUT seconds"
if [[ "$ENABLE_LIVE_AI" == "true" ]]; then
  echo "Live OpenAI generation: enabled"
fi
if [[ "$ENABLE_LIVE_SPEECH" == "true" ]]; then
  echo "Live Azure Speech synthesis: enabled"
fi

exec "$PYTHON" -m uvicorn apps.api.app.main:app --host "$HOST_NAME" --port "$PORT" --no-access-log --timeout-graceful-shutdown "$GRACEFUL_TIMEOUT"
