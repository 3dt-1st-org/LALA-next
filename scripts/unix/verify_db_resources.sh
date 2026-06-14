#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

SUBSCRIPTION_ID="27db5ec6-d206-4028-b5e1-6004dca5eeef"
RESOURCE_GROUP="3dt-final-team1"
KEY_VAULT_NAME="lala-next-kv-27db5e"
POSTGRES_SERVER_NAME=""
DATABASE_NAME="lala"
REQUIRE_DATABASE="false"
PYTHON_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --key-vault-name) KEY_VAULT_NAME="${2:-}"; shift 2 ;;
    --postgres-server-name) POSTGRES_SERVER_NAME="${2:-}"; shift 2 ;;
    --database-name) DATABASE_NAME="${2:-}"; shift 2 ;;
    --require-database) REQUIRE_DATABASE="true"; shift ;;
    --python) PYTHON_ARG="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_db_resources.sh [--postgres-server-name NAME] [--database-name NAME] [--require-database] [--python PATH]"
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

not_ready() {
  local message="$1"
  if [[ "$REQUIRE_DATABASE" == "true" ]]; then
    echo "$message" >&2
    exit 1
  fi
  echo "DB rollout not ready: $message"
}

echo "Verifying LALA-next PostgreSQL rollout readiness in resource group '$RESOURCE_GROUP'."
echo "Secret values are never printed by this script."

ACCOUNT_ID="$(az account show --query id -o tsv)"
if [[ "$ACCOUNT_ID" != "$SUBSCRIPTION_ID" ]]; then
  echo "Current Azure CLI subscription is '$ACCOUNT_ID'; resource checks are scoped to '$SUBSCRIPTION_ID'."
fi

VAULT_URI="$(az keyvault show \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$KEY_VAULT_NAME" \
  --query properties.vaultUri \
  -o tsv)"
echo "Key Vault verified: $KEY_VAULT_NAME ($VAULT_URI)"

SECRET_NAMES="$(az keyvault secret list \
  --subscription "$SUBSCRIPTION_ID" \
  --vault-name "$KEY_VAULT_NAME" \
  --query '[].name' \
  -o json)"
if json_array_contains "$PYTHON" "$SECRET_NAMES" "db-dsn"; then
  echo "Key Vault secret name verified: db-dsn"
else
  not_ready "Key Vault '$KEY_VAULT_NAME' is missing secret name 'db-dsn'."
fi

SERVERS="$(az postgres flexible-server list \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --query '[].{name:name,state:state,fullyQualifiedDomainName:fullyQualifiedDomainName}' \
  -o json)"
SERVER_SUMMARY="$(JSON_PAYLOAD="$SERVERS" "$PYTHON" - "$POSTGRES_SERVER_NAME" <<'PY'
import json
import os
import sys

servers = json.loads(os.environ["JSON_PAYLOAD"])
target = sys.argv[1]
if target:
    matches = [server for server in servers if server.get("name") == target]
    if not matches:
        print("missing", target, "", sep="\t")
    else:
        server = matches[0]
        print("ok", server.get("name", ""), server.get("state", ""), server.get("fullyQualifiedDomainName", ""), sep="\t")
elif len(servers) == 0:
    print("none", "", "", sep="\t")
elif len(servers) == 1:
    server = servers[0]
    print("ok", server.get("name", ""), server.get("state", ""), server.get("fullyQualifiedDomainName", ""), sep="\t")
else:
    print("multiple", ",".join(server.get("name", "") for server in servers), "", sep="\t")
PY
)"
IFS=$'\t' read -r SERVER_STATUS SERVER_NAME SERVER_STATE SERVER_FQDN <<< "$SERVER_SUMMARY"

case "$SERVER_STATUS" in
  none)
    not_ready "No PostgreSQL Flexible Server exists in resource group '$RESOURCE_GROUP'."
    echo "LALA-next PostgreSQL rollout readiness completed."
    exit 0
    ;;
  missing)
    not_ready "PostgreSQL server '$POSTGRES_SERVER_NAME' was not found."
    echo "LALA-next PostgreSQL rollout readiness completed."
    exit 0
    ;;
  multiple)
    not_ready "Multiple PostgreSQL servers found; pass --postgres-server-name. Found: $SERVER_NAME"
    echo "LALA-next PostgreSQL rollout readiness completed."
    exit 0
    ;;
esac

echo "PostgreSQL server verified: $SERVER_NAME state=$SERVER_STATE fqdn=$SERVER_FQDN"
if [[ "$SERVER_STATE" != "Ready" ]]; then
  not_ready "PostgreSQL server '$SERVER_NAME' is not Ready; state=$SERVER_STATE."
fi

DATABASES="$(az postgres flexible-server db list \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --query '[].name' \
  -o json)"
if json_array_contains "$PYTHON" "$DATABASES" "$DATABASE_NAME"; then
  echo "PostgreSQL database verified: $DATABASE_NAME"
else
  not_ready "Database '$DATABASE_NAME' was not found on server '$SERVER_NAME'."
fi

if EXTENSION_VALUE="$(az postgres flexible-server parameter show \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name azure.extensions \
  --query value \
  -o tsv 2>/dev/null)"; then
  echo "PostgreSQL azure.extensions allowlist: $EXTENSION_VALUE"
  EXTENSION_UPPER="$(printf '%s' "$EXTENSION_VALUE" | tr '[:lower:]' '[:upper:]')"
  for extension in POSTGIS VECTOR PGCRYPTO; do
    if [[ "$EXTENSION_UPPER" != *"$extension"* ]]; then
      not_ready "Server '$SERVER_NAME' azure.extensions does not include '$extension'."
    fi
  done
else
  not_ready "Could not verify azure.extensions on server '$SERVER_NAME'."
fi

if [[ "$REQUIRE_DATABASE" == "true" ]]; then
  echo "LALA-next PostgreSQL rollout readiness passed."
else
  echo "LALA-next PostgreSQL rollout readiness completed."
fi
