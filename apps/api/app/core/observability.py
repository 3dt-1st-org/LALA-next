from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

LOGGER_NAME = "lala_next.api"
LOG_FORMAT = "%(asctime)s %(levelname)s %(name)s %(message)s"


def configure_logging(level_name: str) -> logging.Logger:
    level = getattr(logging, (level_name or "INFO").upper(), logging.INFO)
    logger = logging.getLogger(LOGGER_NAME)
    logger.setLevel(level)
    logger.propagate = True
    if not logging.getLogger().handlers:
        logging.basicConfig(level=level, format=LOG_FORMAT)
    return logger


def request_log_extra(
    *,
    request_id: str,
    method: str,
    path: str,
    status_code: int,
    duration_ms: float,
    client_host: str,
) -> dict:
    return {
        "request_id": request_id,
        "method": method,
        "path": path,
        "status_code": status_code,
        "duration_ms": duration_ms,
        "client_host": client_host,
    }


def append_access_log(path: str, record: dict[str, Any], logger: logging.Logger) -> None:
    if not path:
        return

    try:
        log_path = Path(path)
        if log_path.parent and str(log_path.parent) != ".":
            log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(
                json.dumps(
                    record,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
            )
            handle.write("\n")
    except OSError as exc:
        logger.warning(
            "access_log_write_failed path=%s error=%s",
            path,
            exc.__class__.__name__,
        )
