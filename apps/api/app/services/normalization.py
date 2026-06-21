from __future__ import annotations


def normalize_language(value: str | None, *, default: str = "ko") -> str:
    raw = (value or "").strip().lower()
    if raw in {"ko", "kor", "korean", "kr"}:
        return "ko"
    if raw in {"en", "eng", "english"}:
        return "en"
    return default


def display_language(value: str | None) -> str:
    return "Korean" if normalize_language(value) == "ko" else "English"


def normalize_docent_mode(value: str | None) -> str:
    raw = (value or "brief").strip().lower()
    if raw in {"brief", "detail", "standard", "deep"}:
        return raw
    return "brief"


def format_celsius_label(value: str | None) -> str | None:
    raw = (value or "").strip()
    if not raw:
        return None
    compact = raw.replace("℃", "°C").replace(" ", "")
    lower = compact.lower()
    if lower.endswith("°c"):
        return f"{compact[:-2]}°C"
    if lower.endswith("c"):
        return f"{compact[:-1].rstrip('°')}°C"
    return f"{raw}°C"
