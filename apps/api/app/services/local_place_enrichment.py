from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Sequence

from apps.api.app.services.public_mvp_snapshot import GYEONGGI_REGION_NAME_EN

PROMPT_VERSION = "local-romanization-v1"

_NAME_SUFFIXES = (
    ("과학축제", "Science Festival"),
    ("문화축제", "Culture Festival"),
    ("예술축제", "Arts Festival"),
    ("빛 축제", "Light Festival"),
    ("축제", "Festival"),
    ("박물관", "Museum"),
    ("미술관", "Art Museum"),
    ("도서관", "Library"),
    ("문화원", "Cultural Center"),
    ("아트센터", "Art Center"),
    ("공원", "Park"),
    ("수목원", "Arboretum"),
    ("계곡", "Valley"),
    ("호수", "Lake"),
    ("향교", "Hyanggyo"),
    ("사찰", "Temple"),
    ("사", "Temple"),
    ("궁", "Palace"),
    ("성", "Fortress"),
)

_ADDRESS_TOKEN_MAP = {
    "경기도": "Gyeonggi-do",
    **GYEONGGI_REGION_NAME_EN,
}


@dataclass(frozen=True)
class LocalPlaceEnrichment:
    place_id: str
    name_en: str | None
    address_en: str | None
    region_name_en: str | None
    confidence: float
    reason: str

    def has_values(self) -> bool:
        return any((self.name_en, self.address_en, self.region_name_en))


def build_local_enrichment(row: dict[str, Any]) -> LocalPlaceEnrichment:
    region_name_ko = _optional_text(row.get("region_name_ko"))
    region_name_en = _optional_text(row.get("region_name_en")) or _region_name_en(region_name_ko)
    return LocalPlaceEnrichment(
        place_id=str(row.get("place_id") or ""),
        name_en=_optional_text(row.get("name_en")) or romanize_place_name(row.get("name_ko")),
        address_en=_optional_text(row.get("address_en")) or romanize_address(row.get("address_ko")),
        region_name_en=region_name_en,
        confidence=0.62,
        reason="Local Hangul romanization fallback for static English display.",
    )


def romanize_place_name(value: object) -> str | None:
    text = _optional_text(value)
    if not text:
        return None
    romanized = _romanize(text)
    if not romanized:
        return None
    suffix_en = _matched_suffix_en(text)
    if suffix_en and suffix_en.lower() not in romanized.lower():
        return f"{romanized} {suffix_en}"
    return romanized


def romanize_address(value: object) -> str | None:
    text = _optional_text(value)
    if not text:
        return None
    parts = []
    for token in text.split():
        parts.append(_ADDRESS_TOKEN_MAP.get(token) or _romanize(token) or token)
    return " ".join(parts).strip() or None


def fetch_candidates(*, dsn: str, limit: int, connect_timeout: int) -> list[dict[str, Any]]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT
            place_id,
            name_ko,
            name_en,
            address_ko,
            address_en,
            region_name_ko,
            region_name_en
        FROM travel.places
        WHERE
            name_ko IS NOT NULL
            AND (
                name_en IS NULL OR length(trim(name_en)) = 0
                OR (address_ko IS NOT NULL AND length(trim(coalesce(address_en, ''))) = 0)
                OR (region_name_ko IS NOT NULL AND length(trim(coalesce(region_name_en, ''))) = 0)
            )
        ORDER BY updated_at DESC, place_id
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (limit,))
            return [dict(row) for row in cur.fetchall()]


def apply_local_enrichments(
    *,
    dsn: str,
    enrichments: Sequence[LocalPlaceEnrichment],
    connect_timeout: int,
) -> int:
    import psycopg2

    if not enrichments:
        return 0
    update_sql = """
        UPDATE travel.places
        SET
            name_en = COALESCE(NULLIF(trim(name_en), ''), %(name_en)s),
            address_en = COALESCE(NULLIF(trim(address_en), ''), %(address_en)s),
            region_name_en = COALESCE(NULLIF(trim(region_name_en), ''), %(region_name_en)s),
            updated_at = now()
        WHERE place_id = %(place_id)s
    """
    insert_sql = """
        INSERT INTO travel.place_enrichments (
            place_id,
            enrichment_type,
            name_en,
            address_en,
            region_name_en,
            attributes,
            confidence,
            source_method,
            model_name,
            prompt_version
        )
        VALUES (
            %(place_id)s,
            'english_text',
            %(name_en)s,
            %(address_en)s,
            %(region_name_en)s,
            %(attributes)s::jsonb,
            %(confidence)s,
            'local_romanization',
            NULL,
            %(prompt_version)s
        )
    """
    updated = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for item in enrichments:
                if not item.has_values():
                    continue
                params = {
                    "place_id": item.place_id,
                    "name_en": item.name_en,
                    "address_en": item.address_en,
                    "region_name_en": item.region_name_en,
                    "attributes": json.dumps({"reason": item.reason}, ensure_ascii=False),
                    "confidence": item.confidence,
                    "prompt_version": PROMPT_VERSION,
                }
                cur.execute(update_sql, params)
                updated += cur.rowcount
                cur.execute(insert_sql, params)
        conn.commit()
    return updated


def _matched_suffix_en(text: str) -> str:
    compact = text.strip()
    for suffix_ko, suffix_en in _NAME_SUFFIXES:
        if compact.endswith(suffix_ko):
            return suffix_en
    return ""


def _region_name_en(region_name_ko: str | None) -> str | None:
    if not region_name_ko:
        return None
    return GYEONGGI_REGION_NAME_EN.get(region_name_ko) or _romanize(region_name_ko)


def _romanize(value: str) -> str | None:
    try:
        from hangul_romanize import Transliter
        from hangul_romanize.rule import academic
    except Exception:
        return None
    romanized = Transliter(academic).translit(value).strip()
    return romanized.title() or None


def _optional_text(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
