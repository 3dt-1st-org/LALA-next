#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

SUBSCRIPTION_ID="27db5ec6-d206-4028-b5e1-6004dca5eeef"
RESOURCE_GROUP="3dt-final-team1"
KEY_VAULT_NAME="lala-next-kv-27db5e"
OPENAI_ACCOUNT_NAME="lala-next-aoai-27db5e"
OPENAI_DEPLOYMENT_NAME="gpt-4o-mini"
SPEECH_ACCOUNT_NAME="lala-next-speech-27db5e"
ONMU_VAULT_NAME="onmu-dev-kv-27db5e"
PYTHON_ARG=""

EXPECTED_SECRET_NAMES=(
  "ios-api-key"
  "azure-openai-endpoint"
  "azure-openai-key"
  "azure-openai-deployment"
  "azure-openai-api-version"
  "azure-speech-key"
  "azure-speech-region"
  "azure-speech-endpoint"
)
OPTIONAL_SECRET_NAMES=(
  "api-bearer-token"
  "db-dsn"
  "cors-allow-origins"
  "oauth-issuer"
  "oauth-audience"
  "oauth-jwks-url"
  "oauth-client-id"
  "oauth-required-scopes"
  "kakao-rest-api-key"
  "kakao-javascript-key"
  "kakao-redirect-uri"
  "naver-client-id"
  "naver-client-secret"
  "kopis-api-key"
  "public-data-service-key"
  "gyeonggi-data-dream-api-key"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --key-vault-name) KEY_VAULT_NAME="${2:-}"; shift 2 ;;
    --openai-account-name) OPENAI_ACCOUNT_NAME="${2:-}"; shift 2 ;;
    --openai-deployment-name) OPENAI_DEPLOYMENT_NAME="${2:-}"; shift 2 ;;
    --speech-account-name) SPEECH_ACCOUNT_NAME="${2:-}"; shift 2 ;;
    --onmu-vault-name) ONMU_VAULT_NAME="${2:-}"; shift 2 ;;
    --python) PYTHON_ARG="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_azure_resources.sh [--subscription-id ID] [--resource-group NAME] [--python PATH]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

require_command az
PYTHON="$(select_python "$PYTHON_ARG")"

echo "Verifying LALA-next Azure resources in resource group '$RESOURCE_GROUP'."
echo "Secret values are never printed by this script."

ACCOUNT_ID="$(az account show --query id -o tsv)"
if [[ "$ACCOUNT_ID" != "$SUBSCRIPTION_ID" ]]; then
  echo "Current Azure CLI subscription is '$ACCOUNT_ID'; resource checks are scoped to '$SUBSCRIPTION_ID'."
fi

if [[ "$KEY_VAULT_NAME" == "$ONMU_VAULT_NAME" ]]; then
  echo "LALA-next Key Vault name must not match the ONMU vault name." >&2
  exit 1
fi

VAULT_INFO="$(az keyvault show \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$KEY_VAULT_NAME" \
  --query '{name:name,resourceGroup:resourceGroup,vaultUri:properties.vaultUri}' \
  -o json)"
JSON_PAYLOAD="$VAULT_INFO" "$PYTHON" - "$KEY_VAULT_NAME" "$RESOURCE_GROUP" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
if payload.get("name") != sys.argv[1]:
    raise SystemExit(f"Key Vault name expected {sys.argv[1]} but got {payload.get('name')}.")
if payload.get("resourceGroup") != sys.argv[2]:
    raise SystemExit(f"Key Vault resource group expected {sys.argv[2]} but got {payload.get('resourceGroup')}.")
PY
VAULT_URI="$(JSON_PAYLOAD="$VAULT_INFO" "$PYTHON" - <<'PY'
import json
import os

print(json.loads(os.environ["JSON_PAYLOAD"]).get("vaultUri", ""))
PY
)"
echo "Key Vault verified: $KEY_VAULT_NAME ($VAULT_URI)"

SECRET_NAMES="$(az keyvault secret list \
  --subscription "$SUBSCRIPTION_ID" \
  --vault-name "$KEY_VAULT_NAME" \
  --query '[].name' \
  -o json)"

MISSING=()
for secret_name in "${EXPECTED_SECRET_NAMES[@]}"; do
  if ! json_array_contains "$PYTHON" "$SECRET_NAMES" "$secret_name"; then
    MISSING+=("$secret_name")
  fi
done
if (( ${#MISSING[@]} > 0 )); then
  echo "LALA-next Key Vault is missing expected secret names: ${MISSING[*]}" >&2
  exit 1
fi
echo "Key Vault secret names verified: ${#EXPECTED_SECRET_NAMES[@]} expected names present."

PRESENT_OPTIONAL=()
for secret_name in "${OPTIONAL_SECRET_NAMES[@]}"; do
  if json_array_contains "$PYTHON" "$SECRET_NAMES" "$secret_name"; then
    PRESENT_OPTIONAL+=("$secret_name")
  fi
done
if (( ${#PRESENT_OPTIONAL[@]} > 0 )); then
  echo "Optional Key Vault secret names present: ${PRESENT_OPTIONAL[*]}"
else
  echo "Optional Key Vault secret names are not present yet: ${OPTIONAL_SECRET_NAMES[*]}"
fi

OPENAI_INFO="$(az cognitiveservices account show \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$OPENAI_ACCOUNT_NAME" \
  --query '{name:name,kind:kind,endpoint:properties.endpoint}' \
  -o json)"
JSON_PAYLOAD="$OPENAI_INFO" "$PYTHON" - "$OPENAI_ACCOUNT_NAME" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
if payload.get("name") != sys.argv[1] or payload.get("kind") != "OpenAI":
    raise SystemExit("Azure OpenAI account verification failed.")
PY
OPENAI_ENDPOINT="$(JSON_PAYLOAD="$OPENAI_INFO" "$PYTHON" - <<'PY'
import json
import os

print(json.loads(os.environ["JSON_PAYLOAD"]).get("endpoint", ""))
PY
)"
echo "Azure OpenAI account verified: $OPENAI_ACCOUNT_NAME ($OPENAI_ENDPOINT)"

DEPLOYMENTS="$(az cognitiveservices account deployment list \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$OPENAI_ACCOUNT_NAME" \
  --query '[].{name:name,model:properties.model.name,version:properties.model.version,provisioningState:properties.provisioningState}' \
  -o json)"
DEPLOYMENT_SUMMARY="$(JSON_PAYLOAD="$DEPLOYMENTS" "$PYTHON" - "$OPENAI_DEPLOYMENT_NAME" <<'PY'
import json
import os
import sys

target = sys.argv[1]
for deployment in json.loads(os.environ["JSON_PAYLOAD"]):
    if deployment.get("name") == target:
        if deployment.get("provisioningState") != "Succeeded":
            raise SystemExit(f"Azure OpenAI deployment state expected Succeeded but got {deployment.get('provisioningState')}.")
        print(f"{deployment.get('name')} model={deployment.get('model')} version={deployment.get('version')}")
        break
else:
    raise SystemExit(f"Azure OpenAI deployment {target} was not found.")
PY
)"
echo "Azure OpenAI deployment verified: $DEPLOYMENT_SUMMARY"

SPEECH_INFO="$(az cognitiveservices account show \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SPEECH_ACCOUNT_NAME" \
  --query '{name:name,kind:kind,endpoint:properties.endpoint}' \
  -o json)"
JSON_PAYLOAD="$SPEECH_INFO" "$PYTHON" - "$SPEECH_ACCOUNT_NAME" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
if payload.get("name") != sys.argv[1] or payload.get("kind") != "SpeechServices":
    raise SystemExit("Azure Speech account verification failed.")
PY
SPEECH_ENDPOINT="$(JSON_PAYLOAD="$SPEECH_INFO" "$PYTHON" - <<'PY'
import json
import os

print(json.loads(os.environ["JSON_PAYLOAD"]).get("endpoint", ""))
PY
)"
echo "Azure Speech account verified: $SPEECH_ACCOUNT_NAME ($SPEECH_ENDPOINT)"

if ONMU_INFO="$(az keyvault show \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ONMU_VAULT_NAME" \
  --query '{name:name}' \
  -o json 2>/dev/null)"; then
  ONMU_NAME="$(JSON_PAYLOAD="$ONMU_INFO" "$PYTHON" - <<'PY'
import json
import os

print(json.loads(os.environ["JSON_PAYLOAD"]).get("name", ""))
PY
)"
  echo "ONMU vault also exists in this resource group, but is not used by LALA-next: $ONMU_NAME"
else
  echo "ONMU vault comparison skipped."
fi

echo "LALA-next Azure resource verification completed."
