"""AWS Secrets Manager backend with an explicit fail-closed required path."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from typing import Literal

# secret 이름 접두사. 예: secret_id="logto-endpoint" → "lala-next/logto-endpoint".
# 이미 "/"가 포함된 secret_id는 접두사 없이 그대로 사용.
_SM_PREFIX = "lala-next/"


class AwsSecretLookupError(RuntimeError):
    """Safe lookup error; it deliberately contains no value or ARN."""


class AwsSecretOutcome(StrEnum):
    """Structured lookup outcome categories for AWS Secrets Manager.

    These categories represent the 4 safe outcomes specified in the P0 runtime
    secret contract. They deliberately exclude provider error text, secret values,
    DSNs, ARNs, account IDs, and resource identifiers.

    - found: Secret successfully retrieved
    - missing: Secret does not exist in AWS Secrets Manager (ResourceNotFound)
    - denied: Caller lacks permission to access the secret (AccessDenied)
    - unavailable: AWS client unavailable or transient failure
    - invalid: Secret exists but is not valid (empty, binary, malformed)
    """

    FOUND = "found"
    MISSING = "missing"
    DENIED = "denied"
    UNAVAILABLE = "unavailable"
    INVALID = "invalid"


@dataclass(frozen=True)
class AwsSecretLookupResult:
    """Structured AWS secret lookup result.

    This boundary class enforces secret safety by never exposing provider error
    messages, ARNs, account IDs, or resource identifiers. Only the outcome
    category and the logical secret name are included.
    """

    outcome: Literal["found", "missing", "denied", "unavailable", "invalid"]  # noqa: UP007
    logical_name: str  # The logical name requested (e.g., "db-dsn")
    value: str = ""  # Only populated when outcome is "found"

    def to_dict(self) -> dict[str, object]:
        """Convert to dictionary without exposing secret values."""
        return {
            "outcome": self.outcome,
            "logical_name": self.logical_name,
        }

    def __repr__(self) -> str:
        """Secret-safe representation that never includes the value field."""
        return (
            f"AwsSecretLookupResult(outcome={self.outcome!r}, logical_name={self.logical_name!r})"
        )

    def __str__(self) -> str:
        """Secret-safe string representation that never includes the value field."""
        return f"AwsSecretLookupResult(outcome={self.outcome}, logical_name={self.logical_name})"


@lru_cache(maxsize=1)
def _client():  # pragma: no cover - 외부 SDK 래핑
    try:
        import boto3
    except Exception:
        return None
    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1"
    try:
        return boto3.client("secretsmanager", region_name=region)
    except Exception:
        return None


def _resolve_secret_id(secret_id: str) -> str:
    if not secret_id:
        return ""
    if "/" in secret_id:
        return secret_id
    prefix = os.getenv("LALA_AWS_SM_PREFIX", _SM_PREFIX)
    return f"{prefix}{secret_id}"


def _classify_aws_exception(
    exception: Exception,
) -> Literal["missing", "denied", "unavailable", "invalid"]:  # noqa: UP007
    """Classify AWS exception into structured outcome without exposing provider text.

    This function safely categorizes failures into the 4 outcomes required by
    the P0 runtime secret contract. Provider-specific error messages are never
    exposed in the result.
    """
    exception_type_name = type(exception).__name__
    exception_str = str(exception).lower()

    # ResourceNotFoundException / ResourceNotFound: secret doesn't exist
    if "resourcenotfound" in exception_type_name.lower() or "not found" in exception_str:
        return "missing"

    # AccessDenied / UnrecognizedClientException: permission denied
    if (
        "accessdenied" in exception_type_name.lower()
        or "access denied" in exception_str
        or "unauthorized" in exception_str
        or "not authorized" in exception_str
        or "unrecognizedclient" in exception_type_name.lower()
        or "invalidclienttokenid" in exception_type_name.lower()
        or "expiredtoken" in exception_type_name.lower()
        or "invalid client" in exception_str
        or "expired token" in exception_str
    ):
        return "denied"

    # InvalidParameterException / InvalidRequest / MalformedResponse: invalid request or response
    if (
        "invalid" in exception_type_name.lower()
        or "invalid" in exception_str
        or "malformed" in exception_type_name.lower()
        or "malformed" in exception_str
        or "parse" in exception_str
    ):
        return "invalid"

    # All other exceptions are classified as unavailable (transient or unknown)
    return "unavailable"


def get_aws_sm_secret_structured(secret_id: str) -> AwsSecretLookupResult:
    """AWS Secrets Manager에서 secret 조회 결과를 구조화된 형태로 반환.

    Args:
        secret_id: 논리 secret 이름 (예: "logto-endpoint"). 접두사가 없으면
            LALA_AWS_SM_PREFIX(기본 "lala-next/")를 붙인다.

    Returns:
        AwsSecretLookupResult with outcome category and value if found.
        Never raises; errors are classified into outcome categories.
    """
    logical_name = secret_id
    full_id = _resolve_secret_id(secret_id)
    if not full_id:
        return AwsSecretLookupResult(outcome="invalid", logical_name=logical_name)

    client = _client()
    if client is None:
        return AwsSecretLookupResult(outcome="unavailable", logical_name=logical_name)

    try:
        resp = client.get_secret_value(SecretId=full_id)
    except Exception as exc:
        outcome = _classify_aws_exception(exc)
        return AwsSecretLookupResult(outcome=outcome, logical_name=logical_name)

    # Validate response structure before accessing fields
    if not isinstance(resp, Mapping):
        return AwsSecretLookupResult(outcome="invalid", logical_name=logical_name)

    secret_string = resp.get("SecretString")

    # Validate secret_string is a string before calling strip()
    if not isinstance(secret_string, str):
        return AwsSecretLookupResult(outcome="invalid", logical_name=logical_name)

    # Check for empty or whitespace-only secrets
    if not secret_string.strip():
        return AwsSecretLookupResult(outcome="invalid", logical_name=logical_name)

    return AwsSecretLookupResult(outcome="found", logical_name=logical_name, value=secret_string)


def get_aws_sm_secret(secret_id: str, *, required: bool = False) -> str:
    """AWS Secrets Manager에서 secret 값을 조회.

    Args:
        secret_id: 논리 secret 이름 (예: "logto-endpoint"). 접두사가 없으면
            LALA_AWS_SM_PREFIX(기본 "lala-next/")를 붙인다.

        required: 운영 런타임 계약에서 조회 실패를 오류로 승격할지 여부.
    """
    result = get_aws_sm_secret_structured(secret_id)

    if result.outcome == "found":
        return result.value

    if required:
        error_messages = {
            "missing": f"Secret '{result.logical_name}' not found.",
            "denied": f"Access denied to secret '{result.logical_name}'.",
            "unavailable": f"Secret '{result.logical_name}' unavailable.",
            "invalid": f"Secret '{result.logical_name}' is invalid.",
        }
        raise AwsSecretLookupError(error_messages[result.outcome]) from None

    return ""
