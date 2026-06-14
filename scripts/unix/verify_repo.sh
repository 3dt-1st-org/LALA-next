#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

SKIP_INSTALL="false"
PYTHON_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install)
      SKIP_INSTALL="true"
      shift
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_repo.sh [--skip-install] [--python PATH]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
cd "$ROOT"

if [[ "$SKIP_INSTALL" != "true" ]]; then
  require_command uv
  echo "Syncing LALA-next API package with uv dev dependencies..."
  uv sync --extra dev
fi

PYTHON="$(select_python "$PYTHON_ARG")"

echo "Running FastAPI tests and safety contracts..."
"$PYTHON" -m pytest apps/api/tests

echo "Running worker dry-run smoke..."
"$ROOT/scripts/unix/smoke_workers.sh" --python "$PYTHON"

echo "Planning worker/batch live rollout gates..."
"$ROOT/scripts/unix/plan_worker_rollout.sh" --python "$PYTHON"

echo "Exporting OpenAPI schema in-process..."
"$ROOT/scripts/unix/export_openapi.sh" --in-process --python "$PYTHON"

echo "Checking Flutter reference client contract..."
"$PYTHON" -m apps.api.app.tools.check_flutter_client_contract

echo "Checking Flutter reference client Dart package when Dart is available..."
"$ROOT/scripts/unix/verify_flutter_client.sh"

echo "Checking Flutter app shell when Flutter is available..."
"$ROOT/scripts/unix/verify_flutter_app.sh"

echo "Running local OAuth/JWT smoke..."
"$ROOT/scripts/unix/smoke_oauth_jwt.sh" --python "$PYTHON"

echo "Planning approved DB rollout sequence..."
"$ROOT/scripts/unix/plan_db_rollout.sh" --python "$PYTHON"

echo "Planning observability alerts and dashboards..."
"$ROOT/scripts/unix/plan_observability.sh" --python "$PYTHON"

echo "Planning OAuth/Entra identity rollout..."
"$ROOT/scripts/unix/plan_identity_rollout.sh" --python "$PYTHON"

echo "Planning safe ONMU Key Vault reuse..."
"$ROOT/scripts/unix/plan_key_vault_reuse.sh" --python "$PYTHON"

echo "Planning local-value place score batch..."
"$ROOT/scripts/unix/plan_place_score_batch.sh" --python "$PYTHON"

echo "Planning legacy Flask replacement or retirement..."
"$ROOT/scripts/unix/plan_legacy_retirement.sh" --python "$PYTHON"

echo "Planning local-only dev seed/reset SQL..."
"$ROOT/scripts/unix/plan_dev_reset.sh" --python "$PYTHON"

echo "Checking Unix shell script syntax..."
while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT/scripts/unix" -name '*.sh' -type f | sort)

echo "Repository verification completed."
echo "Live Azure checks are intentionally excluded. Use smoke_api.sh --paid-dependency against a live-enabled API process when needed."
