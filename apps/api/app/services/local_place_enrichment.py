from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Sequence

from apps.api.app.services.public_mvp_snapshot import GYEONGGI_REGION_NAME_EN

PROMPT_VERSION = "local-romanization-v1"

_KNOWN_NAME_EN = {
    "2025 에듀의왕! 어울림축제": "2025 Edu Uiwang Harmony Festival",
    "의왕백운호수축제": "Uiwang Baegun Lake Festival",
    "시흥오이도박물관": "Siheung Oido Museum",
    "2025 이천펫축제": "2025 Icheon Pet Festival",
    "전국해양스포츠제전": "National Marine Sports Festival",
    "구리 코스모스 축제": "Guri Cosmos Festival",
    "구리문화원": "Guri Cultural Center",
    "군포문화원": "Gunpo Cultural Center",
    "광명에디슨뮤지엄": "Gwangmyeong Edison Museum",
    "광명동굴 빛 축제": "Gwangmyeong Cave Light Festival",
    "충현박물관": "Chunghyeon Museum",
    "광명업사이클아트센터": "Gwangmyeong Upcycle Art Center",
    "안산시행복예절관": "Ansan Etiquette Center",
    "개미허리아치교": "Ant Waist Arch Bridge",
    "부천시립심곡도서관": "Bucheon Simgok Library",
    "소사복숭아축제": "Sosa Peach Festival",
    "제10회 부천국제브레이킹대회(BIBC)": "10th Bucheon International Breaking Competition (BIBC)",
    "한국만화박물관": "Korea Manhwa Museum",
    "2025 제7회 BMF(블랙뮤직페스티벌)": "2025 7th BMF Black Music Festival",
    "동광극장": "Donggwang Theater",
    "연천수레울아트홀": "Yeoncheon Sureul Art Hall",
    "CICA 미술관": "CICA Art Museum",
    "서호미술관": "Seohomi Art Museum",
    "평택 원평나루 억새축제": "Pyeongtaek Wonpyeong Naru Silver Grass Festival",
    "무진장갈비": "Mujinjang Galbi",
    "가원미술관": "Gawon Art Museum",
    "안양춤축제": "Anyang Dance Festival",
    "튼튼 펫 페스타": "Tuntun Pet Festa",
    "양주국가유산 야행": "Yangju National Heritage Night Tour",
    "2025 양주관아지에서 만나는 특별한 주말": "2025 Special Weekend at Yangju Gwana Historic Site",
    "성남시 분당도서관": "Seongnam Bundang Library",
    "광주시문화재단 광주시문화예술의전당": "Gwangju Cultural Foundation Arts Center",
    "경희대학교 국제캠퍼스 노천극장": "Kyung Hee University Global Campus Outdoor Theater",
    "지혜의 숲": "Forest of Wisdom",
    "이경순 소리박물관": "Lee Kyung-soon Sound Museum",
    "포천시 청년축제": "Pocheon Youth Festival",
    "세종대왕 역사문화관": "King Sejong History and Culture Center",
    "이함캠퍼스": "Iham Campus",
    "고양가을꽃축제": "Goyang Autumn Flower Festival",
}

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


def build_local_enrichment(
    row: dict[str, Any],
    *,
    replace_existing: bool = False,
) -> LocalPlaceEnrichment:
    region_name_ko = _optional_text(row.get("region_name_ko"))
    region_name_en = _optional_text(row.get("region_name_en")) or _region_name_en(region_name_ko)
    name_en = None if replace_existing else _optional_text(row.get("name_en"))
    address_en = None if replace_existing else _optional_text(row.get("address_en"))
    return LocalPlaceEnrichment(
        place_id=str(row.get("place_id") or ""),
        name_en=name_en or romanize_place_name(row.get("name_ko")),
        address_en=address_en or romanize_address(row.get("address_ko")),
        region_name_en=region_name_en,
        confidence=0.62,
        reason="Local Hangul romanization fallback for static English display.",
    )


def romanize_place_name(value: object) -> str | None:
    text = _optional_text(value)
    if not text:
        return None
    known_name = _KNOWN_NAME_EN.get(text)
    if known_name:
        return known_name
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


def fetch_candidates(
    *,
    dsn: str,
    limit: int,
    connect_timeout: int,
    refresh_local: bool = False,
) -> list[dict[str, Any]]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    missing_sql = """
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
    refresh_sql = """
        SELECT
            places.place_id,
            places.name_ko,
            places.name_en,
            places.address_ko,
            places.address_en,
            places.region_name_ko,
            places.region_name_en
        FROM travel.places places
        WHERE EXISTS (
            SELECT 1
            FROM travel.place_enrichments enrichments
            WHERE enrichments.place_id = places.place_id
              AND enrichments.source_method = 'local_romanization'
        )
        ORDER BY places.updated_at DESC, places.place_id
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(refresh_sql if refresh_local else missing_sql, (limit,))
            return [dict(row) for row in cur.fetchall()]


def apply_local_enrichments(
    *,
    dsn: str,
    enrichments: Sequence[LocalPlaceEnrichment],
    connect_timeout: int,
    replace_existing: bool = False,
) -> int:
    import psycopg2

    if not enrichments:
        return 0
    merge_update_sql = """
        UPDATE travel.places
        SET
            name_en = COALESCE(NULLIF(trim(name_en), ''), %(name_en)s),
            address_en = COALESCE(NULLIF(trim(address_en), ''), %(address_en)s),
            region_name_en = COALESCE(NULLIF(trim(region_name_en), ''), %(region_name_en)s),
            updated_at = now()
        WHERE place_id = %(place_id)s
    """
    replace_update_sql = """
        UPDATE travel.places
        SET
            name_en = %(name_en)s,
            address_en = %(address_en)s,
            region_name_en = %(region_name_en)s,
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
                cur.execute(replace_update_sql if replace_existing else merge_update_sql, params)
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
