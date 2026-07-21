from __future__ import annotations

import re
from uuid import uuid4

from fastapi import Request

REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
JSON_SCALAR_TYPES = (str, int, float, bool, type(None))


def ensure_request_id(request: Request) -> str:
    request_id = getattr(request.state, "request_id", None)
    if request_id:
        return request_id
    request_id = _safe_request_id(request.headers.get("X-Request-ID")) or str(uuid4())
    request.state.request_id = request_id
    return request_id


def _safe_request_id(value: str | None) -> str:
    if not value:
        return ""
    value = value.strip()
    if REQUEST_ID_PATTERN.fullmatch(value):
        return value
    return ""


def safe_validation_details(details) -> list:
    return [_strip_validation_input(detail) for detail in details]


def _strip_validation_input(value):
    if isinstance(value, dict):
        return {
            str(key): _strip_validation_input(item) for key, item in value.items() if key != "input"
        }
    if isinstance(value, list):
        return [_strip_validation_input(item) for item in value]
    if isinstance(value, JSON_SCALAR_TYPES):
        return value
    return str(value)


def success_envelope(
    *,
    request: Request,
    data,
    meta: dict | None = None,
) -> dict:
    merged_meta = {"request_id": ensure_request_id(request)}
    if meta:
        merged_meta.update(meta)
    return {
        "ok": True,
        "data": data,
        "meta": merged_meta,
        "error": None,
    }


def error_envelope(
    *,
    request: Request,
    code: str,
    message: str,
    retryable: bool,
    details=None,
) -> dict:
    error = {
        "code": code,
        "message": message,
        "retryable": retryable,
    }
    if details is not None:
        error["details"] = details
    return {
        "ok": False,
        "data": None,
        "meta": {"request_id": ensure_request_id(request)},
        "error": error,
    }
