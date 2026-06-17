from __future__ import annotations

import json
from copy import deepcopy
from functools import lru_cache
from importlib.resources import files
from math import sqrt
from typing import Any

SNAPSHOT_PACKAGE = "apps.api.app.data"
SNAPSHOT_FILE = "public_mvp_places.json"
SOURCE_NAME = "public_mvp_snapshot"


def snapshot_status() -> str:
    return "configured" if _load_snapshot().get("places") else "missing"


def fetch_places(
    *,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    language: str,
) -> list[dict[str, Any]]:
    rows = _load_snapshot().get("places") or []
    places: list[dict[str, Any]] = []
    for row in rows:
        if category != "all" and row.get("category") != category:
            continue
        distance_m = _distance_m(lat=lat, lng=lng, place=row)
        if distance_m > radius_m:
            continue
        places.append(_place_payload(row, distance_m=distance_m, language=language))

    places.sort(
        key=lambda place: (
            -float((place.get("score") or {}).get("final_score") or 0),
            int(place.get("distance_m") or 0),
            str(place.get("name_ko") or place.get("name") or ""),
        )
    )
    return places[:20]


@lru_cache(maxsize=1)
def _load_snapshot() -> dict[str, Any]:
    try:
        payload = files(SNAPSHOT_PACKAGE).joinpath(SNAPSHOT_FILE).read_text(encoding="utf-8")
    except Exception:
        return {"places": []}
    try:
        decoded = json.loads(payload)
    except json.JSONDecodeError:
        return {"places": []}
    if not isinstance(decoded, dict):
        return {"places": []}
    return decoded


def _place_payload(row: dict[str, Any], *, distance_m: float, language: str) -> dict[str, Any]:
    name = row.get("name_en") if language == "en" and row.get("name_en") else row.get("name_ko")
    address = (
        row.get("address_en")
        if language == "en" and row.get("address_en")
        else row.get("address_ko")
    )
    return {
        "place_id": row.get("place_id"),
        "name": name,
        "name_ko": row.get("name_ko"),
        "name_en": row.get("name_en"),
        "category": row.get("category"),
        "lat": float(row.get("lat") or 0),
        "lng": float(row.get("lng") or 0),
        "address": address,
        "image_url": row.get("image_url"),
        "region_ko": row.get("region_ko"),
        "region_en": row.get("region_en"),
        "distance_m": int(round(distance_m)),
        "source": SOURCE_NAME,
        "upstream_source": row.get("upstream_source") or "snapshot",
        "score": deepcopy(row.get("score")),
    }


def _distance_m(*, lat: float, lng: float, place: dict[str, Any]) -> float:
    place_lat = float(place.get("lat") or 0)
    place_lng = float(place.get("lng") or 0)
    return sqrt(((place_lat - lat) * 111000) ** 2 + ((place_lng - lng) * 88000) ** 2)
