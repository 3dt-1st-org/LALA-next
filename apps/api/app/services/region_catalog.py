from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class ProvinceMetadata:
    id: str
    label_ko: str
    label_en: str
    short_ko: str
    short_en: str
    tour_api_area_code: str
    kopis_signgucode: str


_PROVINCE_PATTERN = re.compile(
    r"ManualLocationProvince\(\s*"
    r"id: '([^']+)',\s*"
    r"labelKo: '([^']+)',\s*"
    r"labelEn: '([^']+)',\s*"
    r"shortKo: '([^']+)',\s*"
    r"shortEn: '([^']+)',",
    re.S,
)
_OPTION_PATTERN = re.compile(
    r"ManualLocationOption\(\s*"
    r"id: '([^']+)',\s*"
    r"provinceId: '([^']+)',\s*"
    r"provinceKo: '([^']+)',\s*"
    r"provinceEn: '([^']+)',\s*"
    r"labelKo: '([^']+)',\s*"
    r"labelEn: '([^']+)'",
    re.S,
)
_REGION_SUFFIXES = ("시", "군", "구")
_MANUAL_LOCATION_PATH = (
    Path(__file__).resolve().parents[4]
    / "apps"
    / "flutter_app"
    / "lib"
    / "manual_location_options.dart"
)
_TOUR_API_AREA_CODES = {
    "seoul": "1",
    "incheon": "2",
    "daejeon": "3",
    "daegu": "4",
    "gwangju": "5",
    "busan": "6",
    "ulsan": "7",
    "sejong": "8",
    "gyeonggi": "31",
    "gangwon": "32",
    "chungbuk": "33",
    "chungnam": "34",
    "gyeongbuk": "35",
    "gyeongnam": "36",
    "jeonbuk": "37",
    "jeonnam": "38",
    "jeju": "39",
}
_KOPIS_SIGNGUCODES = {
    "seoul": "11",
    "busan": "26",
    "daegu": "27",
    "incheon": "28",
    "gwangju": "29",
    "daejeon": "30",
    "ulsan": "31",
    "sejong": "36",
    "gyeonggi": "41",
    "chungbuk": "43",
    "chungnam": "44",
    "jeonbuk": "45",
    "jeonnam": "46",
    "gyeongbuk": "47",
    "gyeongnam": "48",
    "jeju": "50",
    "gangwon": "51",
}
_REGION_NAME_EN_OVERRIDES = {
    "강원특별자치도": {
        "철원군": "Cheorwon-gun",
    },
    "경기도": {
        "광주시": "Gwangju-si",
        "양주시": "Yangju-si",
        "포천시": "Pocheon-si",
        "화성시": "Hwaseong-si",
    },
    "충청남도": {
        "계룡시": "Gyeryong-si",
        "당진시": "Dangjin-si",
    },
    "충청북도": {
        "증평군": "Jeungpyeong-gun",
    },
}


@lru_cache(maxsize=1)
def _load_catalog() -> tuple[tuple[ProvinceMetadata, ...], dict[str, dict[str, str]]]:
    text = _MANUAL_LOCATION_PATH.read_text(encoding="utf-8")
    provinces = tuple(
        ProvinceMetadata(
            id=province_id,
            label_ko=label_ko,
            label_en=label_en,
            short_ko=short_ko,
            short_en=short_en,
            tour_api_area_code=_TOUR_API_AREA_CODES[province_id],
            kopis_signgucode=_KOPIS_SIGNGUCODES[province_id],
        )
        for province_id, label_ko, label_en, short_ko, short_en in _PROVINCE_PATTERN.findall(text)
    )
    regions_by_province: dict[str, dict[str, str]] = {}
    for _, _, province_ko, _, label_ko, label_en in _OPTION_PATTERN.findall(text):
        regions_by_province.setdefault(province_ko, {})[label_ko] = label_en
    for province_ko, overrides in _REGION_NAME_EN_OVERRIDES.items():
        regions_by_province.setdefault(province_ko, {}).update(overrides)
    return provinces, regions_by_province


PROVINCES, REGION_NAME_EN_BY_PROVINCE = _load_catalog()
PROVINCE_BY_KO = {province.label_ko: province for province in PROVINCES}
PROVINCE_NAME_EN = {province.label_ko: province.label_en for province in PROVINCES}
PROVINCE_BY_KOPIS_SIGNGUCODE = {province.kopis_signgucode: province for province in PROVINCES}
REGION_NAME_EN = {
    region_ko: region_en
    for region_map in REGION_NAME_EN_BY_PROVINCE.values()
    for region_ko, region_en in region_map.items()
}


def _compact(value: str) -> str:
    return re.sub(r"\s+", "", value).strip()


def _region_aliases(region_name_ko: str) -> tuple[str, ...]:
    aliases = {region_name_ko, _compact(region_name_ko)}
    if region_name_ko.endswith(_REGION_SUFFIXES) and len(region_name_ko) > 2:
        trimmed = region_name_ko[:-1]
        if len(trimmed) >= 2:
            aliases.add(trimmed)
            aliases.add(_compact(trimmed))
    return tuple(alias for alias in aliases if alias)


PROVINCE_ALIAS_TO_KO: dict[str, str] = {}
for province in PROVINCES:
    for alias in (
        province.label_ko,
        province.short_ko,
        _compact(province.label_ko),
        _compact(province.short_ko),
    ):
        PROVINCE_ALIAS_TO_KO[alias] = province.label_ko
    if province.label_ko.endswith(("특별시", "광역시", "특별자치시")):
        PROVINCE_ALIAS_TO_KO[f"{province.short_ko}시"] = province.label_ko


REGION_ALIAS_TO_KO_BY_PROVINCE: dict[str, dict[str, str]] = {}
for province_ko, region_map in REGION_NAME_EN_BY_PROVINCE.items():
    aliases: dict[str, str] = {}
    for region_name_ko in region_map:
        for alias in _region_aliases(region_name_ko):
            aliases.setdefault(alias, region_name_ko)
    REGION_ALIAS_TO_KO_BY_PROVINCE[province_ko] = aliases


_global_alias_candidates: dict[str, set[str]] = {}
for region_map in REGION_NAME_EN_BY_PROVINCE.values():
    for region_name_ko in region_map:
        for alias in _region_aliases(region_name_ko):
            _global_alias_candidates.setdefault(alias, set()).add(region_name_ko)

UNIQUE_REGION_ALIAS_TO_KO = {
    alias: next(iter(region_names))
    for alias, region_names in _global_alias_candidates.items()
    if len(region_names) == 1
}


def normalize_province_name_ko(value: object) -> str | None:
    text = _optional_text(value)
    if not text:
        return None
    return PROVINCE_ALIAS_TO_KO.get(_compact(text)) or PROVINCE_ALIAS_TO_KO.get(text) or text


def normalize_kopis_signgucode(value: object) -> str | None:
    text = _optional_text(value)
    if not text:
        return None
    if text in PROVINCE_BY_KOPIS_SIGNGUCODE:
        return text
    province_ko = normalize_province_name_ko(text)
    if not province_ko:
        return text
    province = PROVINCE_BY_KO.get(province_ko)
    if province:
        return province.kopis_signgucode
    return text


def province_name_en(value: object) -> str | None:
    province_ko = normalize_province_name_ko(value)
    if not province_ko:
        return None
    return PROVINCE_NAME_EN.get(province_ko)


def normalize_region_name_ko(
    value: object, *, province_name_ko: object | None = None
) -> str | None:
    text = _optional_text(value)
    if not text:
        return None
    province_ko = normalize_province_name_ko(province_name_ko)
    compact_text = _compact(text)
    if province_ko:
        province_aliases = REGION_ALIAS_TO_KO_BY_PROVINCE.get(province_ko, {})
        if compact_text in province_aliases:
            return province_aliases[compact_text]
        if text in province_aliases:
            return province_aliases[text]
    if text in REGION_NAME_EN:
        return text
    if compact_text in UNIQUE_REGION_ALIAS_TO_KO:
        return UNIQUE_REGION_ALIAS_TO_KO[compact_text]
    return text


def region_name_en(value: object, *, province_name_ko: object | None = None) -> str | None:
    region_ko = normalize_region_name_ko(value, province_name_ko=province_name_ko)
    if region_ko and region_ko in REGION_NAME_EN:
        return REGION_NAME_EN[region_ko]
    return province_name_en(region_ko)


def infer_province_name_from_address(address: object) -> str | None:
    text = _optional_text(address)
    if not text:
        return None
    parts = text.split()
    if not parts:
        return None
    return normalize_province_name_ko(parts[0])


def infer_region_name_from_address(address: object) -> str | None:
    text = _optional_text(address)
    if not text:
        return None
    parts = text.split()
    if not parts:
        return None
    province_ko = normalize_province_name_ko(parts[0])
    if province_ko:
        if len(parts) >= 2:
            return normalize_region_name_ko(parts[1], province_name_ko=province_ko) or parts[1]
        return province_ko
    return normalize_region_name_ko(parts[0]) or parts[0]


def infer_region_name_from_text(text: object, province_name_ko: object) -> str | None:
    compact_text = _compact(_optional_text(text) or "")
    province_ko = normalize_province_name_ko(province_name_ko)
    if not compact_text or not province_ko:
        return None
    aliases = REGION_ALIAS_TO_KO_BY_PROVINCE.get(province_ko, {})
    for alias in sorted(aliases, key=len, reverse=True):
        if alias in compact_text:
            return aliases[alias]
    return None


def region_name_en_map(
    *,
    province_names: Sequence[str] | None = None,
    include_provinces: bool = False,
) -> dict[str, str]:
    if province_names is None:
        province_ko_names = [province.label_ko for province in PROVINCES]
    else:
        province_ko_names = [
            province_ko
            for province_name in province_names
            if (province_ko := normalize_province_name_ko(province_name)) is not None
        ]
    mapping: dict[str, str] = {}
    for province_ko in province_ko_names:
        mapping.update(REGION_NAME_EN_BY_PROVINCE.get(province_ko, {}))
        if include_provinces:
            province = PROVINCE_BY_KO[province_ko]
            mapping[province.label_ko] = province.label_en
            mapping[province.short_ko] = province.label_en
    return mapping


def address_token_en_map(*, province_names: Sequence[str] | None = None) -> dict[str, str]:
    mapping = region_name_en_map(province_names=province_names, include_provinces=True)
    for alias, province_ko in PROVINCE_ALIAS_TO_KO.items():
        province_en = PROVINCE_NAME_EN.get(province_ko)
        if province_en:
            mapping[alias] = province_en
    return mapping


def tour_api_area_codes(*, province_names: Sequence[str] | None = None) -> tuple[str, ...]:
    if province_names is None:
        provinces = PROVINCES
    else:
        province_ko_names = {
            province_ko
            for province_name in province_names
            if (province_ko := normalize_province_name_ko(province_name)) is not None
        }
        provinces = tuple(
            province for province in PROVINCES if province.label_ko in province_ko_names
        )
    return tuple(province.tour_api_area_code for province in provinces)


def kcisa_sido_names(*, province_names: Sequence[str] | None = None) -> tuple[str, ...]:
    if province_names is None:
        provinces = PROVINCES
    else:
        province_ko_names = {
            province_ko
            for province_name in province_names
            if (province_ko := normalize_province_name_ko(province_name)) is not None
        }
        provinces = tuple(
            province for province in PROVINCES if province.label_ko in province_ko_names
        )
    return tuple(province.short_ko for province in provinces)


def kopis_signgucodes(*, province_names: Sequence[str] | None = None) -> tuple[str, ...]:
    if province_names is None:
        provinces = PROVINCES
    else:
        province_ko_names = {
            province_ko
            for province_name in province_names
            if (province_ko := normalize_province_name_ko(province_name)) is not None
        }
        provinces = tuple(
            province for province in PROVINCES if province.label_ko in province_ko_names
        )
    return tuple(province.kopis_signgucode for province in provinces)


def _optional_text(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
