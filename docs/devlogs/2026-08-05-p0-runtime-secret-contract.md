# P0 Runtime Secret Contract - 2026-08-05

## Overview

This devlog documents the implementation of P0 runtime secret contract corrections for the LALA-next API and worker applications. The changes enforce fail-closed behavior for AWS Secrets Manager integration while maintaining secret safety at all representation boundaries.

## Changes Implemented

### 1. Secret-Safe Representation Boundaries

**File**: `apps/api/app/core/aws_secrets.py`

Added custom `__repr__()` and `__str__()` methods to `AwsSecretLookupResult` that never include the secret value field:

```python
def __repr__(self) -> str:
    """Secret-safe representation that never includes the value field."""
    return f"AwsSecretLookupResult(outcome={self.outcome!r}, logical_name={self.logical_name!r})"


def __str__(self) -> str:
    """Secret-safe string representation that never includes the value field."""
    return f"AwsSecretLookupResult(outcome={self.outcome}, logical_name={self.logical_name})"
```

**Rationale**: The default dataclass representation includes all fields, which would leak secret values in logs, debug output, and error messages.

**Verification**: Added regression test `test_structured_lookup_repr_str_are_secret_safe()` using a sentinel value to ensure the value never appears in repr, str, or dict serialization.

### 2. Enhanced AWS Exception Classification

**File**: `apps/api/app/core/aws_secrets.py`

Updated `_classify_aws_exception()` to classify additional AWS authentication/credential failures as "denied":

- `UnrecognizedClientException` - Invalid client credentials
- `InvalidClientTokenId` - Invalid client token ID
- `ExpiredToken` - Expired security token
- Generic "invalid client" errors

**Rationale**: These failures represent authentication/authorization issues, not transient failures. Classifying them as "denied" rather than "unavailable" ensures proper operational response.

**Verification**: Added tests for each new classification:
- `test_structured_lookup_classifies_unrecognized_client_as_denied`
- `test_structured_lookup_classifies_invalid_client_token_id_as_denied`
- `test_structured_lookup_classifies_expired_token_as_denied`
- `test_structured_lookup_classifies_invalid_client_text_as_denied`

### 3. Malformed Response Classification

**File**: `apps/api/app/core/aws_secrets.py`

Updated `_classify_aws_exception()` to classify malformed AWS responses as "invalid":

- Exceptions with "malformed" in type name or message
- Exceptions with "parse" in message

**Rationale**: Malformed responses indicate structural issues with the AWS response, not transient failures. These should be classified as invalid to distinguish them from temporary unavailability.

**Verification**: Added test `test_structured_lookup_classifies_malformed_response_as_invalid`

### 4. Response Structure Validation

**File**: `apps/api/app/core/aws_secrets.py`

Added strict validation of AWS SDK response structure before field access:

1. Added `collections.abc.Mapping` check for response type
2. Added `isinstance(secret_string, str)` check before calling `.strip()`
3. Treat non-mapping responses and non-string `SecretString` values as `invalid` outcome
4. Prevents `AttributeError` from malicious or malformed fake clients

**Rationale**: Without these checks, a fake client could return a non-mapping response (e.g., list) or non-string `SecretString` (e.g., int, dict), causing `AttributeError` instead of returning safe `AwsSecretOutcome.INVALID`.

**Fail-Closed Boundary**: The function now safely handles all response types and never raises due to response structure issues.

### 5. Values-Free Startup Error Behavior

**File**: `apps/api/app/core/config.py`

The actual fail-closed behavior is implemented in `Settings.from_env()`:

1. During startup, `Settings.from_env()` calls `validate_secret_contract()` with secret lookups
2. Contract validation raises `RuntimeSecretContractError` for any missing/denied/unavailable/invalid secrets
3. This error is raised **before** the readiness endpoint is accessible
4. Error messages contain only logical secret names and outcome categories
5. No secret values, DSNs, ARNs, cloud IDs, or provider error text are included in startup errors

**Implementation Note**: The application intentionally fails to start if required secrets are missing, denied, unavailable, or invalid. This is the primary fail-closed boundary. Readiness checks are never reached for invalid configurations.

## Testing

### Test Coverage

All changes include comprehensive test coverage:

1. **Secret-safe representation**: Test uses sentinel value to verify no value leakage
2. **AWS exception classification**: Tests for each new exception type
3. **Malformed response handling**: Test for malformed/parse errors
4. **Non-mapping response validation**: Test for non-dict responses (lists, strings, ints)
5. **Non-string SecretString validation**: Tests for int, list, dict SecretString values
6. **Values-free error messages**: Test verifies runtime contract exceptions contain only logical names and categories
7. **Existing tests**: All existing tests continue to pass

### Verification Commands

```bash
# Run AWS secrets tests
uv run pytest apps/api/tests/test_aws_secrets.py -v

# Run runtime secrets tests
uv run pytest apps/api/tests/test_runtime_secrets.py -v

# Run worker contract tests
uv run pytest apps/api/tests/test_workers_contract.py -v

# Run all API tests
uv run pytest apps/api/tests/
```

## Security Considerations

### Secret Safety

- **Representation boundaries**: All representations (repr, str, dict) exclude secret values
- **Logging**: No secret values in logs or error messages
- **Debug output**: Safe even in debug/trace modes
- **Metadata**: Only logical names and outcome categories exposed
- **Response validation**: Strict type checking prevents attribute errors from malformed responses
- **Error boundaries**: No DSNs, cloud IDs, raw response bodies, or provider text in any output

### Fail-Closed Behavior

- **Operational profiles** (api/worker): Must use AWS Secrets Manager, no Key Vault fallback
- **Required secrets**: Raise `AwsSecretLookupError` with safe messages based on outcome
- **Readiness checks**: Return "degraded" status for any contract violation
- **No silent failures**: All secret lookup failures are categorized and exposed

## Operational Impact

### Deployment

These changes are backward compatible:

- No changes to secret storage or retrieval logic
- No changes to environment variables or configuration
- No changes to AWS Secrets Manager structure
- Enhanced error classification provides better operational visibility

### Monitoring

The enhanced classification provides better visibility:

- **Denied**: Check IAM permissions and AWS credentials
- **Invalid**: Check secret content and format
- **Missing**: Check secret provisioning
- **Unavailable**: Check AWS connectivity and client configuration

## Future Considerations

### Potential Enhancements

1. **Metrics**: Add CloudWatch metrics for each outcome category
2. **Alerting**: Configure alerts based on denied/unavailable patterns
3. **Retry logic**: Consider different retry strategies by outcome type
4. **Circuit breaker**: Implement circuit breaking for repeated unavailable failures

### Maintenance

- Review AWS exception patterns quarterly for new exception types
- Update classification logic for new AWS SDK versions
- Monitor for new secret-related failure modes

## References

- **PR #98**: Original P0 runtime secret contract implementation
- **Secret Contract**: `apps/api/app/core/runtime_secrets.py`
- **AWS Integration**: `apps/api/app/core/aws_secrets.py`
- **Readiness Checks**: `apps/api/app/core/readiness.py`

## Status

- Implementation date: 2026-08-05
- Status: Corrections implemented, pending independent verification
- Test coverage: Comprehensive
- Backward compatibility: Maintained
- Security status: Awaiting independent review and sign-off

## Next Steps

1. Independent verification of response structure validation
2. Security review of values-free error message behavior
3. Final sign-off after verification complete
