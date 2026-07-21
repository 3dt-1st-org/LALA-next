"""AWS Secrets Manager 백엔드.

config.py의 _env_or_secret이 환경변수 → AWS Secrets Manager → Azure Key Vault
순으로 조회하도록 지원. Azure Key Vault는 레거시/폴백이고, AWS 운영 환경에서는
AWS Secrets Manager를 우선 사용한다.

boto3가 설치되어 있지 않거나 자격증명/권한이 없으면 조용히 빈 문자열을 반환
(설정이 없는 것과 동일 취급)하여 앱 부팅을 막지 않는다.
"""

from __future__ import annotations

import os
from functools import lru_cache

# secret 이름 접두사. 예: secret_id="logto-endpoint" → "lala-next/logto-endpoint".
# 이미 "/"가 포함된 secret_id는 접두사 없이 그대로 사용.
_SM_PREFIX = os.getenv("LALA_AWS_SM_PREFIX", "lala-next/")


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
    return f"{_SM_PREFIX}{secret_id}"


def get_aws_sm_secret(secret_id: str) -> str:
    """AWS Secrets Manager에서 secret 값을 조회.

    Args:
        secret_id: 논리 secret 이름 (예: "logto-endpoint"). 접두사가 없으면
            LALA_AWS_SM_PREFIX(기본 "lala-next/")를 붙인다.

    Returns:
        secret 문자열. boto3 미설치, 권한 부족, secret 미존재 시 빈 문자열.
    """
    full_id = _resolve_secret_id(secret_id)
    if not full_id:
        return ""
    client = _client()
    if client is None:
        return ""
    try:
        resp = client.get_secret_value(SecretId=full_id)
    except Exception:
        return ""
    value = resp.get("SecretString")
    if value is None:
        # Binary secret은 지원하지 않음 (앱 설정은 모두 문자열)
        return ""
    return value
