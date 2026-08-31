#!/usr/bin/env bash

# Public Flutter build configuration resolver. Source after _common.sh.
# Values are never printed and are only exposed to the child Flutter process as
# dart-defines. Server credentials and provider secrets are intentionally absent.

resolve_flutter_public_value() {
  local env_name="$1"
  local current="${!env_name:-}"
  if [[ -n "${current//[[:space:]]/}" ]]; then
    printf '%s' "$current"
    return 0
  fi

  if command -v aws >/dev/null 2>&1; then
    local secret_id value
    secret_id="${PREFIX}$(printf '%s' "$env_name" | tr '[:upper:]_' '[:lower:]-')"
    value="$(aws secretsmanager get-secret-value \
      --secret-id "$secret_id" \
      --region "$REGION" \
      --query SecretString \
      --output text \
      --no-cli-pager 2>/dev/null || true)"
    if [[ -n "${value//[[:space:]]/}" && "$value" != "None" ]]; then
      printf '%s' "$value"
      return 0
    fi
  fi

  local env_file value
  for env_file in "${FLUTTER_PUBLIC_ENV_FILES[@]}"; do
    [[ -f "$env_file" ]] || continue
    value="$(
      # Isolated subshell: unrelated dotenv values never enter the caller.
      set -a
      # shellcheck disable=SC1090
      source "$env_file"
      set +a
      printf '%s' "${!env_name:-}"
    )"
    if [[ -n "${value//[[:space:]]/}" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

resolve_flutter_public_build_config() {
  local platform="${1:-any}"
  local require_logto="${2:-false}"
  local env_name value
  local names=(
    NAVER_MAP_CLIENT_ID
    LOGTO_ENDPOINT LOGTO_API_AUDIENCE
    LOGTO_WEB_APP_ID LOGTO_NATIVE_APP_ID
    LOGTO_WEB_REDIRECT_URI LOGTO_NATIVE_REDIRECT_URI
    LOGTO_WEB_POST_LOGOUT_REDIRECT_URI LOGTO_NATIVE_POST_LOGOUT_REDIRECT_URI
    LOGTO_REDIRECT_URI LOGTO_POST_LOGOUT_REDIRECT_URI
  )

  for env_name in "${names[@]}"; do
    value="$(resolve_flutter_public_value "$env_name")"
    printf -v "$env_name" '%s' "$value"
  done

  if [[ -z "${NAVER_MAP_CLIENT_ID//[[:space:]]/}" ]]; then
    echo "NAVER_MAP_CLIENT_ID is required from approved public build configuration." >&2
    return 1
  fi

  local logto_present="false"
  for env_name in LOGTO_ENDPOINT LOGTO_API_AUDIENCE LOGTO_WEB_APP_ID LOGTO_NATIVE_APP_ID; do
    if [[ -n "${!env_name//[[:space:]]/}" ]]; then
      logto_present="true"
      break
    fi
  done

  if [[ "$require_logto" == "true" || "$logto_present" == "true" ]]; then
    local missing=()
    [[ -n "${LOGTO_ENDPOINT//[[:space:]]/}" ]] || missing+=(LOGTO_ENDPOINT)
    [[ -n "${LOGTO_API_AUDIENCE//[[:space:]]/}" ]] || missing+=(LOGTO_API_AUDIENCE)
    case "$platform" in
      web)
        [[ -n "${LOGTO_WEB_APP_ID//[[:space:]]/}" ]] || missing+=(LOGTO_WEB_APP_ID)
        ;;
      native)
        [[ -n "${LOGTO_NATIVE_APP_ID//[[:space:]]/}" ]] || missing+=(LOGTO_NATIVE_APP_ID)
        ;;
      any)
        if [[ -z "${LOGTO_WEB_APP_ID//[[:space:]]/}" && -z "${LOGTO_NATIVE_APP_ID//[[:space:]]/}" ]]; then
          missing+=(LOGTO_WEB_APP_ID_or_LOGTO_NATIVE_APP_ID)
        fi
        ;;
      *)
        echo "Unsupported Flutter build platform: $platform" >&2
        return 2
        ;;
    esac
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "Logto public build configuration is incomplete: ${missing[*]}" >&2
      return 1
    fi
    LOGTO_BUILD_ENABLED="true"
  else
    LOGTO_BUILD_ENABLED="false"
  fi
}

append_flutter_public_dart_defines() {
  FLUTTER_PUBLIC_DART_DEFINES=(
    "--dart-define=LALA_API_BASE_URL=$API_BASE_URL"
    "--dart-define=NAVER_MAP_CLIENT_ID=$NAVER_MAP_CLIENT_ID"
    "--dart-define=LALA_BUILD_SHA=$BUILD_SHA"
  )
  if [[ "$LOGTO_BUILD_ENABLED" != "true" ]]; then
    return 0
  fi

  FLUTTER_PUBLIC_DART_DEFINES+=(
    "--dart-define=LOGTO_ENDPOINT=$LOGTO_ENDPOINT"
    "--dart-define=LOGTO_API_AUDIENCE=$LOGTO_API_AUDIENCE"
  )
  [[ -z "$LOGTO_WEB_APP_ID" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_WEB_APP_ID=$LOGTO_WEB_APP_ID")
  [[ -z "$LOGTO_NATIVE_APP_ID" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_NATIVE_APP_ID=$LOGTO_NATIVE_APP_ID")
  [[ -z "$LOGTO_WEB_REDIRECT_URI" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_WEB_REDIRECT_URI=$LOGTO_WEB_REDIRECT_URI")
  [[ -z "$LOGTO_NATIVE_REDIRECT_URI" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_NATIVE_REDIRECT_URI=$LOGTO_NATIVE_REDIRECT_URI")
  [[ -z "$LOGTO_WEB_POST_LOGOUT_REDIRECT_URI" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_WEB_POST_LOGOUT_REDIRECT_URI=$LOGTO_WEB_POST_LOGOUT_REDIRECT_URI")
  [[ -z "$LOGTO_NATIVE_POST_LOGOUT_REDIRECT_URI" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_NATIVE_POST_LOGOUT_REDIRECT_URI=$LOGTO_NATIVE_POST_LOGOUT_REDIRECT_URI")
  [[ -z "$LOGTO_REDIRECT_URI" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_REDIRECT_URI=$LOGTO_REDIRECT_URI")
  [[ -z "$LOGTO_POST_LOGOUT_REDIRECT_URI" ]] || FLUTTER_PUBLIC_DART_DEFINES+=("--dart-define=LOGTO_POST_LOGOUT_REDIRECT_URI=$LOGTO_POST_LOGOUT_REDIRECT_URI")
}
