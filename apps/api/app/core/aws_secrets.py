"""AWS Secrets Manager backend with an explicit fail-closed required path."""

from __future__ import annotations

import os
from functools import lru_cache

# secret 이름 접두사. 예: secret_id="logto-endpoint" → "lala-next/logto-endpoint".
# 이미 "/"가 포함된 secret_id는 접두사 없이 그대로 사용.
_SM_PREFIX = "lala-next/"


class AwsSecretLookupError(RuntimeError):
    """Safe lookup error; it deliberately contains no value or ARN."""


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


def get_aws_sm_secret(secret_id: str, *, required: bool = False) -> str:
    """AWS Secrets Manager에서 secret 값을 조회.

    Args:
        secret_id: 논리 secret 이름 (예: "logto-endpoint"). 접두사가 없으면
            LALA_AWS_SM_PREFIX(기본 "lala-next/")를 붙인다.

        required: 운영 런타임 계약에서 조회 실패를 오류로 승격할지 여부.
    """
    full_id = _resolve_secret_id(secret_id)
    if not full_id:
        return ""
    client = _client()
    if client is None:
        if required:
            raise AwsSecretLookupError("AWS Secrets Manager client unavailable.") from None
        return ""
    try:
        resp = client.get_secret_value(SecretId=full_id)
    except Exception:
        if required:
            raise AwsSecretLookupError("AWS Secrets Manager lookup failed.") from None
        return ""
    value = resp.get("SecretString")
    if value is None:
        # Binary secret은 지원하지 않음 (앱 설정은 모두 문자열)
        if required:
            raise AwsSecretLookupError("AWS Secrets Manager returned no string secret.") from None
        return ""
    return value
