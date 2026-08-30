#!/usr/bin/env bash
# Test-only: verifies scripts/unix/flutter_with_build_env.sh resolves the Naver
# Dynamic Map client id in the intended order -- SSM Parameter Store, then AWS Secrets
# Manager, then a trusted local dotenv parsed in an isolated subshell -- without
# ever contacting AWS or reading a real dotenv. Every value below is a non-secret
# placeholder emitted by a stubbed `aws`; no real key, secret id, or device id is
# used or printed.
#
# Wired into scripts/unix/verify_repo.sh, so it runs in the unix-verification
# CI job. Run directly:
#
#   bash scripts/unix/tests/test_flutter_with_build_env.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SCRIPT="$ROOT/scripts/unix/flutter_with_build_env.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"

# Non-secret placeholders only. The "secret"-shaped one is tagged so the secret
# scanner treats it as an allowed placeholder, matching override_test.sh.
SSM_PLACEHOLDER="nonsecret-ssm-placeholder-000000"   # pragma: allowlist secret
SM_PLACEHOLDER="nonsecret-sm-placeholder-000000"     # pragma: allowlist secret
LOCAL_PLACEHOLDER="nonsecret-local-placeholder-0000" # pragma: allowlist secret
SSM_PARAM_NAME="operator/supplied-build-key-name"

# Stub `aws`: emits canned placeholders per subcommand, never contacts AWS.
cat > "$TMP/bin/aws" <<'AWSEOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ssm" && "${2:-}" == "get-parameter" ]]; then
  [[ -n "${AWS_STUB_SSM:-}" ]] && { printf '%s' "$AWS_STUB_SSM"; exit 0; }
  exit 1
elif [[ "${1:-}" == "secretsmanager" && "${2:-}" == "get-secret-value" ]]; then
  [[ -n "${AWS_STUB_SM:-}" ]] && { printf '%s' "$AWS_STUB_SM"; exit 0; }
  exit 1
fi
exit 1
AWSEOF
chmod +x "$TMP/bin/aws"

# Flutter stand-in: records the dart-define argv and the child environment so the
# test can assert which source won and that the dotenv did not leak.
cat > "$TMP/bin/stub" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$LALA_TEST_ARGS"
env >> "$LALA_TEST_ENV"
STUBEOF
chmod +x "$TMP/bin/stub"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_present() { # file needle -- needle must appear in file
  local file="$1" needle="$2"
  if ! grep -qF "$needle" "$file"; then
    echo "---- captured dart-define args ----" >&2
    cat "$file" >&2
    fail "expected needle not propagated to the build"
  fi
}
assert_absent() { # file needle -- needle must not appear in file
  local file="$1" needle="$2"
  if grep -qF "$needle" "$file"; then
    echo "---- captured file ----" >&2
    cat "$file" >&2
    fail "unexpected needle found"
  fi
}

# run_case <dotenv_path> <ssm_param> <ssm_val> <sm_val>
run_case() {
  local dotenv="$1" ssm_param="${2:-}" ssm_val="${3:-}" sm_val="${4:-}"
  ARGS="$TMP/args.$RANDOM"
  ENVF="$TMP/env.$RANDOM"
  : > "$ARGS"
  : > "$ENVF"
  LALA_TEST_ARGS="$ARGS" LALA_TEST_ENV="$ENVF" \
    AWS_STUB_SSM="$ssm_val" AWS_STUB_SM="$sm_val" \
    PATH="$TMP/bin:/usr/local/bin:/usr/bin:/bin" \
    env -u NAVER_MAP_CLIENT_ID -u NAVER_CLIENT_SECRET \
    bash "$SCRIPT" --source-env "$dotenv" --naver-map-client-id-ssm-param "$ssm_param" \
      -- "$TMP/bin/stub" >/dev/null
}

echo "Case A: SSM Parameter Store is tried first when a parameter name is supplied."
run_case "$TMP/no-such-env" "$SSM_PARAM_NAME" "$SSM_PLACEHOLDER" "$SM_PLACEHOLDER"
assert_present "$ARGS" "NAVER_MAP_CLIENT_ID=$SSM_PLACEHOLDER"
assert_absent  "$ARGS" "NAVER_MAP_CLIENT_ID=$SM_PLACEHOLDER"

echo "Case B: Secrets Manager is the approved fallback when no SSM name is set."
run_case "$TMP/no-such-env" "" "$SSM_PLACEHOLDER" "$SM_PLACEHOLDER"
assert_present "$ARGS" "NAVER_MAP_CLIENT_ID=$SM_PLACEHOLDER"

echo "Case C: local dotenv is the last resort and parsed in an isolated subshell."
printf 'NAVER_MAP_CLIENT_ID=%s\nNAVER_CLIENT_SECRET=must-not-leak\nSHOULD_NOT_LEAK=yes\n' "$LOCAL_PLACEHOLDER" > "$TMP/dotenv"
run_case "$TMP/dotenv" "" "" ""
assert_present "$ARGS" "NAVER_MAP_CLIENT_ID=$LOCAL_PLACEHOLDER"
assert_absent  "$ENVF" "SHOULD_NOT_LEAK="
assert_absent  "$ENVF" "NAVER_CLIENT_SECRET="
assert_absent  "$ARGS" "must-not-leak"

echo "PASS: build-helper resolution order is SSM -> Secrets Manager -> isolated dotenv."
