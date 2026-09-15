from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse

from apps.api.app.core.responses import ensure_request_id, error_envelope


class RequestBodyLimitMiddleware:
    """Bound actual bytes before routing/JSON parsing, including chunked bodies."""

    def __init__(self, app, max_bytes: int = 262144) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request = Request(scope)
        declared = request.headers.get("content-length")
        if declared is not None:
            try:
                oversized = int(declared) > self.max_bytes or int(declared) < 0
            except ValueError:
                oversized = True
            if oversized:
                await self._reject(scope, receive, send)
                return
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > self.max_bytes:
                await self._reject(scope, receive, send)
                return
            body.extend(chunk)
            if not message.get("more_body", False):
                break
        delivered = False

        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, replay, send)

    async def _reject(self, scope, receive, send) -> None:
        request = Request(scope)
        response = JSONResponse(
            status_code=413,
            content=error_envelope(
                request=request,
                code="REQUEST_TOO_LARGE",
                message="Request body exceeds the size limit.",
                retryable=False,
            ),
            headers={"X-Request-ID": ensure_request_id(request)},
        )
        await response(scope, receive, send)
