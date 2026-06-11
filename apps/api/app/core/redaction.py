from __future__ import annotations

import re


def redact_secret_text(text: str, explicit_values: tuple[str, ...] = ()) -> str:
    result = text
    for value in explicit_values:
        if value:
            result = result.replace(value, "[redacted]")
    result = re.sub(
        r"(postgres(?:ql)?://)([^:\s/@]+):([^@\s]+)@",
        r"\1***:***@",
        result,
        flags=re.IGNORECASE,
    )
    result = re.sub(r"(password=)([^ \t\r\n;]+)", r"\1***", result, flags=re.IGNORECASE)
    return result
