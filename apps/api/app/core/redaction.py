from __future__ import annotations

import re
from collections.abc import Mapping


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


def redact_operational_resource_text(text: str, replacements: Mapping[str, str]) -> str:
    result = text
    for value, placeholder in sorted(replacements.items(), key=lambda item: len(item[0]), reverse=True):
        if value:
            result = result.replace(value, placeholder)
    return redact_secret_text(result)
