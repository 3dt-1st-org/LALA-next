#!/usr/bin/env bash

set -euo pipefail

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  cd "$script_dir/../.." && pwd -P
}

select_python() {
  local requested="${1:-}"
  local root
  root="$(repo_root)"

  if [[ -n "$requested" ]]; then
    printf '%s\n' "$requested"
    return 0
  fi

  if [[ -x "$root/.venv/bin/python" ]]; then
    printf '%s\n' "$root/.venv/bin/python"
    return 0
  fi

  if [[ -x "$root/.venv/Scripts/python.exe" ]]; then
    printf '%s\n' "$root/.venv/Scripts/python.exe"
    return 0
  fi

  if command -v python3.11 >/dev/null 2>&1; then
    command -v python3.11
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi

  echo "Python is required. Install Python 3.11+ or pass --python." >&2
  return 1
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "$name is required." >&2
    return 1
  fi
}

trim() {
  local value="$*"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  local raw line name value
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="$(trim "$raw")"
    [[ -n "$line" ]] || continue
    [[ "$line" != \#* ]] || continue
    [[ "$line" == *=* ]] || continue

    name="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -z "${!name:-}" ]] || continue

    if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' && ${#value} -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$name=$value"
  done < "$env_file"
}

vault_name_from_lala_url() {
  local vault_url="${1:-}"
  [[ -n "$vault_url" ]] || {
    printf '%s\n' ""
    return 0
  }
  case "$vault_url" in
    https://*) ;;
    *)
      echo "Unsupported Key Vault URL for LALA-next: $vault_url" >&2
      return 1
      ;;
  esac

  local host path_part vault_name
  path_part="${vault_url#https://}"
  host="${path_part%%/*}"
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  case "$host" in
    *.vault.azure.net) ;;
    *)
      echo "Unsupported Key Vault URL for LALA-next: $vault_url" >&2
      return 1
      ;;
  esac

  vault_name="${host%.vault.azure.net}"
  if [[ -z "$vault_name" || "$vault_name" == *onmu* ]]; then
    echo "Unsupported Key Vault URL for LALA-next: $vault_url" >&2
    return 1
  fi
  if ! key_vault_host_allowed_by_env "$host"; then
    echo "Key Vault host is not in LALA_ALLOWED_KEY_VAULT_HOSTS: $host" >&2
    return 1
  fi
  printf '%s\n' "$vault_name"
}

key_vault_host_allowed_by_env() {
  local host="$1"
  local allowed="${LALA_ALLOWED_KEY_VAULT_HOSTS:-}"
  [[ -n "$allowed" ]] || return 0

  local entry normalized
  IFS=',' read -r -a entries <<< "$allowed"
  for entry in "${entries[@]}"; do
    normalized="$(trim "$entry")"
    normalized="${normalized#https://}"
    normalized="${normalized%%/*}"
    normalized="$(printf '%s' "$normalized" | tr '[:upper:]' '[:lower:]')"
    if [[ "$normalized" == "$host" ]]; then
      return 0
    fi
  done
  return 1
}

set_secret_env_if_missing() {
  local vault_name="$1"
  local env_name="$2"
  local secret_name="$3"

  [[ -n "$vault_name" ]] || return 0
  [[ -z "${!env_name:-}" ]] || return 0
  command -v az >/dev/null 2>&1 || return 0

  local value=""
  value="$(az keyvault secret show \
    --vault-name "$vault_name" \
    --name "$secret_name" \
    --query value \
    -o tsv 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    export "$env_name=$value"
  fi
}

env_status() {
  local env_name="$1"
  if [[ -n "${!env_name:-}" ]]; then
    printf '%s\n' "configured"
  else
    printf '%s\n' "missing"
  fi
}

load_lala_key_vault_secrets() {
  local vault_url="${KEY_VAULT_URL:-}"
  local vault_name
  vault_name="$(vault_name_from_lala_url "$vault_url")"
  [[ -n "$vault_name" ]] || return 0

  set_secret_env_if_missing "$vault_name" "IOS_API_KEY" "ios-api-key"
  set_secret_env_if_missing "$vault_name" "API_BEARER_TOKEN" "api-bearer-token"
  set_secret_env_if_missing "$vault_name" "OAUTH_ISSUER" "oauth-issuer"
  set_secret_env_if_missing "$vault_name" "OAUTH_AUDIENCE" "oauth-audience"
  set_secret_env_if_missing "$vault_name" "OAUTH_JWKS_URL" "oauth-jwks-url"
  set_secret_env_if_missing "$vault_name" "OAUTH_CLIENT_ID" "oauth-client-id"
  set_secret_env_if_missing "$vault_name" "OAUTH_REQUIRED_SCOPES" "oauth-required-scopes"
  set_secret_env_if_missing "$vault_name" "KAKAO_REST_API_KEY" "kakao-rest-api-key"
  set_secret_env_if_missing "$vault_name" "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key"
  set_secret_env_if_missing "$vault_name" "KAKAO_REDIRECT_URI" "kakao-redirect-uri"
  set_secret_env_if_missing "$vault_name" "NAVER_CLIENT_ID" "naver-client-id"
  set_secret_env_if_missing "$vault_name" "NAVER_CLIENT_SECRET" "naver-client-secret"
  set_secret_env_if_missing "$vault_name" "KOPIS_API_KEY" "kopis-api-key"
  set_secret_env_if_missing "$vault_name" "PUBLIC_DATA_SERVICE_KEY" "public-data-service-key"
  set_secret_env_if_missing "$vault_name" "GYEONGGI_DATA_DREAM_API_KEY" "gyeonggi-data-dream-api-key"
  set_secret_env_if_missing "$vault_name" "AZURE_OPENAI_ENDPOINT" "azure-openai-endpoint"
  set_secret_env_if_missing "$vault_name" "AZURE_OPENAI_KEY" "azure-openai-key"
  set_secret_env_if_missing "$vault_name" "AZURE_OPENAI_DEPLOYMENT" "azure-openai-deployment"
  set_secret_env_if_missing "$vault_name" "AZURE_OPENAI_EMBEDDING_DEPLOYMENT" "azure-openai-embedding-deployment"
  set_secret_env_if_missing "$vault_name" "AZURE_OPENAI_API_VERSION" "azure-openai-api-version"
  set_secret_env_if_missing "$vault_name" "AZURE_OPENAI_EMBEDDING_API_VERSION" "azure-openai-embedding-api-version"
  set_secret_env_if_missing "$vault_name" "AZURE_SPEECH_KEY" "azure-speech-key"
  set_secret_env_if_missing "$vault_name" "AZURE_SPEECH_REGION" "azure-speech-region"
  set_secret_env_if_missing "$vault_name" "AZURE_SPEECH_ENDPOINT" "azure-speech-endpoint"
  set_secret_env_if_missing "$vault_name" "CORS_ALLOW_ORIGINS" "cors-allow-origins"
}

json_array_contains() {
  local python="$1"
  local json_payload="$2"
  local needle="$3"

  JSON_PAYLOAD="$json_payload" "$python" - "$needle" <<'PY'
import json
import os
import sys

try:
    values = json.loads(os.environ["JSON_PAYLOAD"])
except Exception:
    values = []
raise SystemExit(0 if sys.argv[1] in values else 1)
PY
}
