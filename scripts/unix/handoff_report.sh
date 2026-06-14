#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
GITHUB_REPO="3dt-1st-org/LALA-next"
BRANCH="main"
SKIP_TESTS="false"
SKIP_AZURE="false"
OPENAPI_BASELINE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --skip-tests)
      SKIP_TESTS="true"
      shift
      ;;
    --skip-azure)
      SKIP_AZURE="true"
      shift
      ;;
    --openapi-baseline)
      OPENAPI_BASELINE="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/handoff_report.sh [--skip-tests] [--skip-azure] [--openapi-baseline PATH] [--github-repo OWNER/REPO] [--branch BRANCH] [--python PATH]"
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

if [[ -z "$OPENAPI_BASELINE" && -f "$ROOT/local-artifacts/openapi/lala-next-openapi.json" ]]; then
  OPENAPI_BASELINE="$ROOT/local-artifacts/openapi/lala-next-openapi.json"
fi

section() {
  printf '\n## %s\n' "$1"
}

section "Repository"
echo "repo_root=$ROOT"
git status --short --branch
echo "head=$(git log --oneline -1)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -n "$UPSTREAM" ]]; then
  echo "upstream=$UPSTREAM"
fi
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
  echo "working_tree=clean"
else
  echo "working_tree=local_changes_present"
fi

section "Latest CI"
if command -v gh >/dev/null 2>&1; then
  if CI_JSON="$(gh run list \
      --repo "$GITHUB_REPO" \
      --branch "$BRANCH" \
      --limit 1 \
      --json databaseId,status,conclusion,headSha,url,createdAt 2>/dev/null)"; then
    CI_JSON="$CI_JSON" "$PYTHON" - <<'PY'
import json
import os

runs = json.loads(os.environ["CI_JSON"])
if not runs:
    print("ci=not_found")
else:
    run = runs[0]
    print(f"ci_run={run.get('databaseId')}")
    print(f"ci_status={run.get('status')}")
    print(f"ci_conclusion={run.get('conclusion')}")
    print(f"ci_head={run.get('headSha')}")
    print(f"ci_created_at={run.get('createdAt')}")
    print(f"ci_url={run.get('url')}")
PY
  else
    echo "ci=skipped_gh_unavailable_or_unauthenticated"
  fi
else
  echo "ci=skipped_gh_not_installed"
fi

section "Local Verification"
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "local_verification=skipped"
else
  "$ROOT/scripts/unix/verify_repo.sh" --skip-install --python "$PYTHON"
fi

section "OpenAPI Compatibility"
if [[ -n "$OPENAPI_BASELINE" ]]; then
  "$PYTHON" -m apps.api.app.tools.check_openapi_compat "$OPENAPI_BASELINE"
else
  echo "openapi_compatibility=skipped_no_baseline_snapshot"
fi

section "Azure And DB Readiness"
if [[ "$SKIP_AZURE" == "true" ]]; then
  echo "azure_verification=skipped"
elif command -v az >/dev/null 2>&1; then
  "$ROOT/scripts/unix/verify_azure_resources.sh" --python "$PYTHON"
  "$ROOT/scripts/unix/verify_db_resources.sh" --python "$PYTHON"
else
  echo "azure_verification=skipped_az_not_installed"
fi

section "Risk Gates"
echo "live_db_apply=blocked_until_db_dsn_secret_postgresql_target_and_explicit_approval"
echo "worker_mutation=blocked_until_db_queue_runtime_retry_idempotency_poison_and_observability_are_approved"
echo "paid_azure_smoke=opt_in_only"
echo "secrets=do_not_commit_env_or_print_secret_values"
