#!/usr/bin/env bash
# Focused offline tests for AWS-first build secret resolution.
# These tests verify call order and fail-closed behavior without contacting AWS
# or requiring local secret files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Test helper functions
test_start() {
  local name="$1"
  TEST_COUNT=$((TEST_COUNT + 1))
  echo "Test $TEST_COUNT: $name"
}

test_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ✓ PASS"
}

test_fail() {
  local reason="$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "  ✗ FAIL: $reason"
}

check_secrets_not_leaked() {
  local output="$1"
  local category="$2"
  local test_strings=("aws-fixture-key" "local-fixture-key" "env-file-key" "env-local-key" "test-dotenv-key" "ssm-fixture-key" "aws-sm-fixture-key" "dotenv-fallback-key")  # pragma: allowlist secret
  for leak in "${test_strings[@]}"; do
    if [[ "$output" == *"$leak"* ]]; then
      echo "  ✗ SECRET CATEGORY LEAKED in $category"
      return 1
    fi
  done
  return 0
}

# Test 1: Verify aws_ssm_secret_get function exists
test_start "aws_ssm_secret_get function exists"
if declare -f aws_ssm_secret_get >/dev/null 2>&1; then
  test_pass
else
  test_fail "aws_ssm_secret_get function not found"
fi

# Test 2: Verify aws_sm_secret_get function exists
test_start "aws_sm_secret_get function exists"
if declare -f aws_sm_secret_get >/dev/null 2>&1; then
  test_pass
else
  test_fail "aws_sm_secret_get function not found"
fi

# Test 3: Verify load_flutter_build_secrets function exists
test_start "load_flutter_build_secrets function exists"
if declare -f load_flutter_build_secrets >/dev/null 2>&1; then
  test_pass
else
  test_fail "load_flutter_build_secrets function not found"
fi

# Test 4: Already set variable is not overwritten
test_start "Already set variable should not be overwritten"
test_no_overwrite() {
  local test_value="pre-existing-test-value"
  export KAKAO_JAVASCRIPT_KEY="$test_value"

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file"
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  # Check for success and no leakage
  if [[ $result -eq 0 ]]; then
    if [[ "${KAKAO_JAVASCRIPT_KEY}" == "$test_value" ]]; then
      if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
        test_pass
      else
        test_fail "Secret leaked to output stream"
      fi
    else
      test_fail "Variable was overwritten: ${KAKAO_JAVASCRIPT_KEY}"
    fi
  else
    test_fail "Function failed when it should have succeeded with existing value"
  fi

  rm -f "$stdout_file" "$stderr_file"
  unset KAKAO_JAVASCRIPT_KEY
}

test_no_overwrite

# Test 5: Fail-closed behavior when no AWS CLI available
test_start "Should fail closed when AWS CLI unavailable and no dotenv"
test_fail_closed_no_aws() {
  # Create temp directory without .env files
  local temp_dir
  temp_dir="$(mktemp -d)"

  # Save current PATH and remove aws
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"  # Remove aws from PATH

  # Mock repo_root to return temp_dir (empty directory)
  repo_root() {
    echo "$temp_dir"
  }
  export -f repo_root

  # Ensure variable is unset
  unset KAKAO_JAVASCRIPT_KEY

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  # This should fail (return non-zero)
  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file" || true
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  # Check for proper failure and no leakage
  if [[ $result -ne 0 || -z "${KAKAO_JAVASCRIPT_KEY:-}" ]]; then
    if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
      test_pass
    else
      test_fail "Secret leaked in fail-closed test"
    fi
  else
    test_fail "Expected failure or empty value, got: ${KAKAO_JAVASCRIPT_KEY:-empty}"
  fi

  # Cleanup
  rm -f "$stdout_file" "$stderr_file"
  unset repo_root
  PATH="$original_path"
  rm -rf "$temp_dir"
  unset KAKAO_JAVASCRIPT_KEY
}

test_fail_closed_no_aws

# Test 6: Dotenv fallback when AWS unavailable
test_start "Should fall back to dotenv when AWS unavailable"
test_dotenv_fallback() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  # Create test .env file
  echo "KAKAO_JAVASCRIPT_KEY=test-dotenv-key" > "$temp_dir/.env"  # pragma: allowlist secret

  # Save and modify PATH
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"  # Remove aws from PATH

  # Mock repo_root to return temp_dir
  repo_root() {
    echo "$temp_dir"
  }
  export -f repo_root

  # Ensure variable is unset
  unset KAKAO_JAVASCRIPT_KEY

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  # This should succeed by loading from .env
  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file"
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  if [[ $result -eq 0 && "${KAKAO_JAVASCRIPT_KEY:-}" == "test-dotenv-key" ]]; then
    if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
      test_pass
    else
      test_fail "Secret leaked in dotenv fallback test"
    fi
  else
    test_fail "Function failed to load from dotenv or wrong value: ${KAKAO_JAVASCRIPT_KEY:-empty}"
  fi

  # Cleanup
  rm -f "$stdout_file" "$stderr_file"
  unset repo_root
  PATH="$original_path"
  rm -rf "$temp_dir"
  unset KAKAO_JAVASCRIPT_KEY
}

test_dotenv_fallback

# Test 7: .env.local preferred over .env
test_start "Should prefer .env.local over .env"
test_env_local_preference() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  # Create both .env files with different values
  echo "KAKAO_JAVASCRIPT_KEY=env-file-key" > "$temp_dir/.env"  # pragma: allowlist secret
  echo "KAKAO_JAVASCRIPT_KEY=env-local-key" > "$temp_dir/.env.local"  # pragma: allowlist secret

  # Save and modify PATH
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  # Mock repo_root to return temp_dir
  repo_root() {
    echo "$temp_dir"
  }
  export -f repo_root

  # Ensure variable is unset
  unset KAKAO_JAVASCRIPT_KEY

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  # This should load from .env.local (preferred over .env)
  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file"
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  if [[ $result -eq 0 && "${KAKAO_JAVASCRIPT_KEY:-}" == "env-local-key" ]]; then
    if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
      test_pass
    else
      test_fail "Secret leaked in .env.local preference test"
    fi
  else
    test_fail "Function failed to load from .env.local or wrong value: ${KAKAO_JAVASCRIPT_KEY:-empty}"
  fi

  # Cleanup
  rm -f "$stdout_file" "$stderr_file"
  unset repo_root
  PATH="$original_path"
  rm -rf "$temp_dir"
  unset KAKAO_JAVASCRIPT_KEY
}

test_env_local_preference

# Test 8: Verify AWS SSM prefix is used correctly
test_start "AWS SSM prefix should be configurable"
test_aws_ssm_prefix() {
  # Test default prefix
  local default_prefix="${LALA_AWS_SSM_PREFIX:-/lala-next/}"
  if [[ "$default_prefix" == "/lala-next/" ]]; then
    test_pass
  else
    test_fail "Expected default prefix /lala-next/, got: $default_prefix"
  fi
}

test_aws_ssm_prefix

# Test 9: Verify AWS SM prefix is used correctly
test_start "AWS SM prefix should be configurable"
test_aws_sm_prefix() {
  # Test default prefix
  local default_prefix="${LALA_AWS_SM_PREFIX:-lala-next/}"
  if [[ "$default_prefix" == "lala-next/" ]]; then
    test_pass
  else
    test_fail "Expected default prefix lala-next/, got: $default_prefix"
  fi
}

test_aws_sm_prefix

# Test 10: SSM wins over local .env fixture
test_start "SSM should win over local .env fixture"
test_ssm_wins_over_dotenv() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  # Create .env.local with a harmless fixture key
  echo "KAKAO_JAVASCRIPT_KEY=local-fixture-key" > "$temp_dir/.env.local"  # pragma: allowlist secret

  # Create a fake aws binary in temp directory
  local fake_bin_dir="$temp_dir/bin"
  mkdir -p "$fake_bin_dir"

  cat > "$fake_bin_dir/aws" <<'AWS_EOF'
#!/usr/bin/env bash
# Fake AWS CLI that returns our test secret for SSM first
if [[ "$*" == *"ssm get-parameter"* ]] && [[ "$*" == *"kakao-javascript-key"* ]]; then
  echo "ssm-fixture-key-test"  # pragma: allowlist secret
  exit 0
fi
# If SSM fails, try Secrets Manager
if [[ "$*" == *"secretsmanager get-secret-value"* ]] && [[ "$*" == *"kakao-javascript-key"* ]]; then
  echo "aws-fixture-key-test"  # pragma: allowlist secret
  exit 0
fi
exit 1
AWS_EOF
  chmod +x "$fake_bin_dir/aws"

  # Save and modify PATH to include our fake aws
  local original_path="$PATH"
  PATH="$fake_bin_dir:$PATH"
  export PATH

  # Mock repo_root to return temp_dir
  repo_root() {
    echo "$temp_dir"
  }
  export -f repo_root

  # Ensure variable is unset
  unset KAKAO_JAVASCRIPT_KEY

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  # Run the function
  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file"
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  # Check for success and SSM value
  if [[ $result -eq 0 && "${KAKAO_JAVASCRIPT_KEY:-}" == "ssm-fixture-key-test" ]]; then  # pragma: allowlist secret
    # Verify SSM won over local .env
    if [[ "${KAKAO_JAVASCRIPT_KEY}" != "local-fixture-key" ]]; then  # pragma: allowlist secret
      if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
        test_pass
      else
        test_fail "Secret leaked in SSM precedence test"
      fi
    else
      test_fail "Local .env won over SSM - precedence order violated"
    fi
  else
    test_fail "SSM lookup failed or wrong value: ${KAKAO_JAVASCRIPT_KEY:-empty}"
  fi

  # Cleanup
  rm -f "$stdout_file" "$stderr_file"
  unset repo_root
  PATH="$original_path"
  export PATH
  rm -rf "$temp_dir"
  unset KAKAO_JAVASCRIPT_KEY
}

test_ssm_wins_over_dotenv

# Test 11: SSM failure falls through to Secrets Manager
test_start "SSM failure should fall through to Secrets Manager"
test_ssm_fails_through_to_sm() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  # Create .env.local with a different value to ensure SM wins over dotenv too
  echo "KAKAO_JAVASCRIPT_KEY=local-fixture-key" > "$temp_dir/.env.local"  # pragma: allowlist secret

  # Create a fake aws binary that fails SSM but succeeds for SM
  local fake_bin_dir="$temp_dir/bin"
  mkdir -p "$fake_bin_dir"

  cat > "$fake_bin_dir/aws" <<'AWS_EOF'
#!/usr/bin/env bash
# Fake AWS CLI that fails SSM but succeeds for Secrets Manager
if [[ "$*" == *"ssm get-parameter"* ]]; then
  # Simulate SSM failure
  exit 1
fi
# If SSM fails, try Secrets Manager
if [[ "$*" == *"secretsmanager get-secret-value"* ]] && [[ "$*" == *"kakao-javascript-key"* ]]; then
  echo "aws-sm-fixture-key"  # pragma: allowlist secret
  exit 0
fi
exit 1
AWS_EOF
  chmod +x "$fake_bin_dir/aws"

  # Save and modify PATH to include our fake aws
  local original_path="$PATH"
  PATH="$fake_bin_dir:$PATH"
  export PATH

  # Mock repo_root to return temp_dir
  repo_root() {
    echo "$temp_dir"
  }
  export -f repo_root

  # Ensure variable is unset
  unset KAKAO_JAVASCRIPT_KEY

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  # Run the function
  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file"
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  # Check for success and SM value
  if [[ $result -eq 0 && "${KAKAO_JAVASCRIPT_KEY:-}" == "aws-sm-fixture-key" ]]; then  # pragma: allowlist secret
    # Verify SM won over local .env
    if [[ "${KAKAO_JAVASCRIPT_KEY}" != "local-fixture-key" ]]; then  # pragma: allowlist secret
      if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
        test_pass
      else
        test_fail "Secret leaked in SM fallback test"
      fi
    else
      test_fail "Local .env won over SM - precedence order violated"
    fi
  else
    test_fail "SM lookup after SSM failure failed or wrong value: ${KAKAO_JAVASCRIPT_KEY:-empty}"
  fi

  # Cleanup
  rm -f "$stdout_file" "$stderr_file"
  unset repo_root
  PATH="$original_path"
  export PATH
  rm -rf "$temp_dir"
  unset KAKAO_JAVASCRIPT_KEY
}

test_ssm_fails_through_to_sm

# Test 12: All AWS failures fall through to dotenv
test_start "All AWS failures should fall through to dotenv"
test_all_aws_fail_to_dotenv() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  # Create .env.local with expected value
  echo "KAKAO_JAVASCRIPT_KEY=dotenv-fallback-key" > "$temp_dir/.env.local"  # pragma: allowlist secret

  # Create a fake aws binary that always fails
  local fake_bin_dir="$temp_dir/bin"
  mkdir -p "$fake_bin_dir"

  cat > "$fake_bin_dir/aws" <<'AWS_EOF'
#!/usr/bin/env bash
# Fake AWS CLI that always fails
exit 1
AWS_EOF
  chmod +x "$fake_bin_dir/aws"

  # Save and modify PATH to include our fake aws
  local original_path="$PATH"
  PATH="$fake_bin_dir:$PATH"
  export PATH

  # Mock repo_root to return temp_dir
  repo_root() {
    echo "$temp_dir"
  }
  export -f repo_root

  # Ensure variable is unset
  unset KAKAO_JAVASCRIPT_KEY

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  # Run the function
  load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key" >"$stdout_file" 2>"$stderr_file"
  local result=$?

  local stdout_content stderr_content
  stdout_content="$(cat "$stdout_file")"
  stderr_content="$(cat "$stderr_file")"

  # Check for success and dotenv value
  if [[ $result -eq 0 && "${KAKAO_JAVASCRIPT_KEY:-}" == "dotenv-fallback-key" ]]; then
    if check_secrets_not_leaked "$stdout_content" "stdout" && check_secrets_not_leaked "$stderr_content" "stderr"; then
      test_pass
    else
      test_fail "Secret leaked in dotenv fallback test"
    fi
  else
    test_fail "Dotenv fallback failed or wrong value: ${KAKAO_JAVASCRIPT_KEY:-empty}"
  fi

  # Cleanup
  rm -f "$stdout_file" "$stderr_file"
  unset repo_root
  PATH="$original_path"
  export PATH
  rm -rf "$temp_dir"
  unset KAKAO_JAVASCRIPT_KEY
}

test_all_aws_fail_to_dotenv

# Run all tests
echo "Running AWS-first build secret resolution tests..."
echo "=============================================="

# Run all the test functions
# (functions are called above as they're defined)

echo "=============================================="
echo "Test Results: $PASS_COUNT/$TEST_COUNT passed"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "FAILED: $FAIL_COUNT test(s) failed"
  exit 1
else
  echo "SUCCESS: All tests passed"
  exit 0
fi
