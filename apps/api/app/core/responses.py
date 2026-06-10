from __future__ import annotations

from uuid import uuid4

from fastapi import Request


def ensure_request_id(request: Request) -> str:
    request_id = getattr(request.state, "request_id", None)
    if request_id:
        return request_id
    request_id = request.headers.get("X-Request-ID") or str(uuid4())
    request.state.request_id = request_id
    return request_id


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

