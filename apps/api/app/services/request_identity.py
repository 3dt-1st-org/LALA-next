from __future__ import annotations

import hashlib
import json
from typing import Any


def generation_identity(kind: str, payload: dict[str, Any]) -> dict[str, str]:
    digest = request_hash({"kind": kind, "payload": payload})
    return {
        "request_hash": digest,
        "cache_key": f"{kind}:{digest[:32]}",
    }


def request_hash(payload: dict[str, Any]) -> str:
    canonical = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
