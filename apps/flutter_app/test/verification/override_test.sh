#!/bin/bash
# Verification script for LALA_API_BASE_URL compile-time override behavior
# This script tests that String.fromEnvironment actually uses dart-define values

set -e

cd "$(dirname "$0")/../.." # Navigate to flutter app root

echo "Testing LALA_API_BASE_URL compile-time override mechanism..."

# Test 1: Default behavior (no dart-define)
echo "Test 1: Default behavior (no dart-define)"
flutter test test/core/config/app_config_test.dart \
  --dart-define TEST_DEFAULT_SHOULD_BE_PUBLIC=true

# Test 2: Override to localhost
echo "Test 2: Compile-time override to localhost"
flutter test test/core/config/app_config_test.dart \
  --dart-define LALA_API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define TEST_EXPECTED_API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define TEST_OVERRIDE_LOCALHOST=true

# Test 3: Override to custom endpoint
echo "Test 3: Compile-time override to custom endpoint"
flutter test test/core/config/app_config_test.dart \
  --dart-define LALA_API_BASE_URL=https://custom.api.example.com \
  --dart-define TEST_EXPECTED_API_BASE_URL=https://custom.api.example.com \
  --dart-define TEST_OVERRIDE_CUSTOM=true

echo "All compile-time override tests passed!"
echo "String.fromEnvironment correctly uses dart-define values when provided."
