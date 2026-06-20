from __future__ import annotations

import json
import math
import re
from dataclasses import asdict, dataclass
from typing import Any, Iterable, Sequence

CORPORATE_PREFIX_RE = re.compile(r"^(?:주식회사|유한회사|농업회사법인|사회적협동조합)+")
BRACKETED_TEXT_RE = re.compile(r"\([^)]*\)|\[[^]]*\]")
KNOWN_BRANCH_SUFFIX_RE = re.compile(
    r"(?:수원역점|강남역점|홍대점|명동점|스타필드점|롯데몰점)$"
)
SEPARATED_BRANCH_SUFFIX_RE = re.compile(
    r"(?:\s+|[-_/])(?:본점|직영점|가맹점|분점|[가-힣A-Za-z0-9]{1,12}점)$"
)
TIGHT_BRANCH_SUFFIX_RE = re.compile(r"(?:본점|직영점|가맹점|분점)$")
NON_NAME_RE = re.compile(r"[^0-9A-Za-z가-힣]+")

BUSINESS_IDENTITY_TYPES = {
    "independent_local",
    "local_small_chain",
    "franchise_store",
    "national_franchise",
    "corporate_chain",
    "unknown",
}


@dataclass(frozen=True)
class PlaceBusinessCandidate:
    place_id: str
    name_ko: str
    category: str
    lat: float | None = None
    lng: float | None = None


@dataclass(frozen=True)
class FranchiseBrand:
    brand_name_ko: str
    normalized_brand_name: str = ""
    brand_id: str | None = None
    headquarters_name_ko: str | None = None
    business_category: str | None = None
    franchise_store_count: int | None = None
    chain_scale_score: float | None = None
    primary_source: str = "fair_trade_commission"

    def normalized(self) -> str:
        return self.normalized_brand_name or normalize_business_name(self.brand_name_ko)


@dataclass(frozen=True)
class FranchiseLocation:
    brand_name_ko: str
    normalized_brand_name: str = ""
    store_name_ko: str | None = None
    normalized_store_name: str | None = None
    brand_id: str | None = None
    lat: float | None = None
    lng: float | None = None
    primary_source: str = "fair_trade_commission"

    def normalized_brand(self) -> str:
        return self.normalized_brand_name or normalize_business_name(self.brand_name_ko)

    def normalized_store(self) -> str:
        return self.normalized_store_name or normalize_business_name(self.store_name_ko or "")


@dataclass(frozen=True)
class PlaceBusinessIdentity:
    place_id: str
    business_identity_type: str
    is_franchise: bool | None
    franchise_brand_name: str | None
    franchise_match_confidence: float | None
    chain_scale_score: float | None
    small_merchant_fit_score: float | None
    matched_source: str | None
    features: dict[str, Any]

    def to_public_dict(self) -> dict[str, Any]:
        return asdict(self)


def normalize_business_name(value: str | None) -> str:
    text = (value or "").strip()
    if not text:
        return ""
    text = BRACKETED_TEXT_RE.sub("", text)
    text = text.replace("㈜", "").replace("(주)", "").replace("주식회사", "")
    text = CORPORATE_PREFIX_RE.sub("", text).strip()
    previous = None
    while previous != text:
        previous = text
        text = KNOWN_BRANCH_SUFFIX_RE.sub("", text).strip()
        text = SEPARATED_BRANCH_SUFFIX_RE.sub("", text).strip()
        text = TIGHT_BRANCH_SUFFIX_RE.sub("", text).strip()
    text = NON_NAME_RE.sub("", text)
    return text.lower()


def classify_place_business(
    place: PlaceBusinessCandidate,
    *,
    brands: Sequence[FranchiseBrand],
    locations: Sequence[FranchiseLocation] = (),
    coordinate_threshold_m: float = 100.0,
) -> PlaceBusinessIdentity:
    normalized_place = normalize_business_name(place.name_ko)
    best_location = _best_location_match(
        place=place,
        normalized_place=normalized_place,
        locations=locations,
        coordinate_threshold_m=coordinate_threshold_m,
    )
    if best_location:
        location, confidence, distance_m, match_type = best_location
        brand = _find_brand(location.normalized_brand(), brands)
        return _identity_from_match(
            place=place,
            brand_name=location.brand_name_ko,
            normalized_brand=location.normalized_brand(),
            confidence=confidence,
            chain_scale_score=_chain_scale_score(brand),
            store_count=brand.franchise_store_count if brand else None,
            matched_source=location.primary_source,
            match_type=match_type,
            distance_m=distance_m,
        )

    best_brand = _best_brand_match(normalized_place, brands)
    if best_brand:
        brand, confidence, match_type = best_brand
        return _identity_from_match(
            place=place,
            brand_name=brand.brand_name_ko,
            normalized_brand=brand.normalized(),
            confidence=confidence,
            chain_scale_score=_chain_scale_score(brand),
            store_count=brand.franchise_store_count,
            matched_source=brand.primary_source,
            match_type=match_type,
            distance_m=None,
        )

    if place.category == "restaurant" and (brands or locations):
        return _identity_from_independent_local(
            place=place,
            normalized_place=normalized_place,
            brands=brands,
            locations=locations,
        )

    return _identity_from_unknown(place=place, normalized_place=normalized_place)


def compute_place_business_identities(
    places: Sequence[PlaceBusinessCandidate],
    *,
    brands: Sequence[FranchiseBrand],
    locations: Sequence[FranchiseLocation] = (),
) -> list[PlaceBusinessIdentity]:
    return [
        classify_place_business(place, brands=brands, locations=locations)
        for place in places
    ]


def fetch_business_identity_inputs(
    *,
    dsn: str,
    category: str,
    limit: int,
    connect_timeout: int,
) -> tuple[list[PlaceBusinessCandidate], list[FranchiseBrand], list[FranchiseLocation]]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    place_sql = """
        SELECT place_id, name_ko, category, lat, lng
        FROM travel.places
        WHERE (%s = 'all' OR category = %s)
        ORDER BY updated_at DESC, place_id
        LIMIT %s
    """
    brand_sql = """
        SELECT
            brand_id,
            brand_name_ko,
            normalized_brand_name,
            headquarters_name_ko,
            business_category,
            franchise_store_count,
            chain_scale_score,
            primary_source
        FROM economy.franchise_brands
        ORDER BY updated_at DESC, brand_name_ko
    """
    location_sql = """
        SELECT
            brand_id,
            brand_name_ko,
            normalized_brand_name,
            store_name_ko,
            normalized_store_name,
            lat,
            lng,
            primary_source
        FROM economy.franchise_locations
        ORDER BY updated_at DESC, brand_name_ko
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(place_sql, (category, category, limit))
            places = [
                PlaceBusinessCandidate(
                    place_id=str(row["place_id"]),
                    name_ko=str(row["name_ko"]),
                    category=str(row["category"]),
                    lat=_optional_float(row.get("lat")),
                    lng=_optional_float(row.get("lng")),
                )
                for row in cur.fetchall()
            ]
            cur.execute(brand_sql)
            brands = [
                FranchiseBrand(
                    brand_id=_optional_text(row.get("brand_id")),
                    brand_name_ko=str(row["brand_name_ko"]),
                    normalized_brand_name=str(row.get("normalized_brand_name") or ""),
                    headquarters_name_ko=_optional_text(row.get("headquarters_name_ko")),
                    business_category=_optional_text(row.get("business_category")),
                    franchise_store_count=_optional_int(row.get("franchise_store_count")),
                    chain_scale_score=_optional_float(row.get("chain_scale_score")),
                    primary_source=str(row.get("primary_source") or "fair_trade_commission"),
                )
                for row in cur.fetchall()
            ]
            cur.execute(location_sql)
            locations = [
                FranchiseLocation(
                    brand_id=_optional_text(row.get("brand_id")),
                    brand_name_ko=str(row["brand_name_ko"]),
                    normalized_brand_name=str(row.get("normalized_brand_name") or ""),
                    store_name_ko=_optional_text(row.get("store_name_ko")),
                    normalized_store_name=_optional_text(row.get("normalized_store_name")),
                    lat=_optional_float(row.get("lat")),
                    lng=_optional_float(row.get("lng")),
                    primary_source=str(row.get("primary_source") or "fair_trade_commission"),
                )
                for row in cur.fetchall()
            ]
    return places, brands, locations


def upsert_place_business_identities(
    *,
    dsn: str,
    identities: Sequence[PlaceBusinessIdentity],
    connect_timeout: int,
) -> int:
    import psycopg2
    from psycopg2.extras import Json

    if not identities:
        return 0
    sql = """
        INSERT INTO analytics.place_business_identity (
            place_id,
            business_identity_type,
            is_franchise,
            franchise_brand_name,
            franchise_match_confidence,
            chain_scale_score,
            small_merchant_fit_score,
            matched_source,
            matched_at,
            features
        )
        VALUES (
            %(place_id)s,
            %(business_identity_type)s,
            %(is_franchise)s,
            %(franchise_brand_name)s,
            %(franchise_match_confidence)s,
            %(chain_scale_score)s,
            %(small_merchant_fit_score)s,
            %(matched_source)s,
            now(),
            %(features)s
        )
        ON CONFLICT (place_id) DO UPDATE SET
            business_identity_type = EXCLUDED.business_identity_type,
            is_franchise = EXCLUDED.is_franchise,
            franchise_brand_name = EXCLUDED.franchise_brand_name,
            franchise_match_confidence = EXCLUDED.franchise_match_confidence,
            chain_scale_score = EXCLUDED.chain_scale_score,
            small_merchant_fit_score = EXCLUDED.small_merchant_fit_score,
            matched_source = EXCLUDED.matched_source,
            matched_at = EXCLUDED.matched_at,
            features = EXCLUDED.features
    """
    count = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for identity in identities:
                params = asdict(identity)
                params["features"] = Json(identity.features, dumps=_json_dumps)
                cur.execute(sql, params)
                count += cur.rowcount
        conn.commit()
    return count


def _identity_from_match(
    *,
    place: PlaceBusinessCandidate,
    brand_name: str,
    normalized_brand: str,
    confidence: float,
    chain_scale_score: float | None,
    store_count: int | None,
    matched_source: str,
    match_type: str,
    distance_m: float | None,
) -> PlaceBusinessIdentity:
    identity_type = _identity_type_for_chain(chain_scale_score, store_count)
    return PlaceBusinessIdentity(
        place_id=place.place_id,
        business_identity_type=identity_type,
        is_franchise=True,
        franchise_brand_name=brand_name,
        franchise_match_confidence=_round4(confidence),
        chain_scale_score=_round4(chain_scale_score) if chain_scale_score is not None else None,
        small_merchant_fit_score=_small_merchant_score(identity_type, confidence),
        matched_source=matched_source,
        features={
            "normalized_brand_name": normalized_brand,
            "normalized_place_name": normalize_business_name(place.name_ko),
            "match_type": match_type,
            "distance_m": _round4(distance_m) if distance_m is not None else None,
            "franchise_store_count": store_count,
            "classification_reason": "franchise_reference_match",
        },
    )


def _identity_from_independent_local(
    *,
    place: PlaceBusinessCandidate,
    normalized_place: str,
    brands: Sequence[FranchiseBrand],
    locations: Sequence[FranchiseLocation],
) -> PlaceBusinessIdentity:
    return PlaceBusinessIdentity(
        place_id=place.place_id,
        business_identity_type="independent_local",
        is_franchise=False,
        franchise_brand_name=None,
        franchise_match_confidence=None,
        chain_scale_score=None,
        small_merchant_fit_score=_small_merchant_score("independent_local", 1.0),
        matched_source=None,
        features={
            "normalized_place_name": normalized_place,
            "classification_reason": "no_franchise_match_with_loaded_references",
            "reference_brand_count": len(brands),
            "reference_location_count": len(locations),
        },
    )


def _identity_from_unknown(
    *,
    place: PlaceBusinessCandidate,
    normalized_place: str,
) -> PlaceBusinessIdentity:
    return PlaceBusinessIdentity(
        place_id=place.place_id,
        business_identity_type="unknown",
        is_franchise=None,
        franchise_brand_name=None,
        franchise_match_confidence=None,
        chain_scale_score=None,
        small_merchant_fit_score=0.55 if place.category == "restaurant" else None,
        matched_source=None,
        features={
            "normalized_place_name": normalized_place,
            "classification_reason": "no_confident_franchise_match",
        },
    )


def _best_brand_match(
    normalized_place: str,
    brands: Sequence[FranchiseBrand],
) -> tuple[FranchiseBrand, float, str] | None:
    best: tuple[FranchiseBrand, float, str] | None = None
    for brand in brands:
        if brand.franchise_store_count is not None and brand.franchise_store_count <= 0:
            continue
        normalized_brand = brand.normalized()
        if not normalized_brand:
            continue
        confidence = 0.0
        match_type = ""
        if normalized_place == normalized_brand:
            confidence = 0.92
            match_type = "brand_exact"
        elif normalized_place.startswith(normalized_brand) and len(normalized_brand) >= 3:
            confidence = 0.82
            match_type = "brand_prefix"
        elif normalized_brand in normalized_place and len(normalized_brand) >= 4:
            confidence = 0.72
            match_type = "brand_contains"
        if confidence and (best is None or confidence > best[1]):
            best = (brand, confidence, match_type)
    return best


def _best_location_match(
    *,
    place: PlaceBusinessCandidate,
    normalized_place: str,
    locations: Sequence[FranchiseLocation],
    coordinate_threshold_m: float,
) -> tuple[FranchiseLocation, float, float | None, str] | None:
    best: tuple[FranchiseLocation, float, float | None, str] | None = None
    for location in locations:
        normalized_brand = location.normalized_brand()
        normalized_store = location.normalized_store()
        name_match = _location_name_match_type(
            normalized_place=normalized_place,
            normalized_brand=normalized_brand,
            normalized_store=normalized_store,
        )
        if name_match is None:
            continue
        match_type, base_confidence = name_match
        distance_m = _distance_m(place.lat, place.lng, location.lat, location.lng)
        if distance_m is not None and distance_m > coordinate_threshold_m:
            continue
        confidence = 0.95 if distance_m is not None else base_confidence
        resolved_match_type = "location_coordinate" if distance_m is not None else match_type
        if best is None or confidence > best[1] or (
            confidence == best[1]
            and (distance_m if distance_m is not None else 999999.0)
            < (best[2] if best[2] is not None else 999999.0)
        ):
            best = (location, confidence, distance_m, resolved_match_type)
    return best


def _location_name_match_type(
    *,
    normalized_place: str,
    normalized_brand: str,
    normalized_store: str,
) -> tuple[str, float] | None:
    if normalized_store and normalized_store == normalized_place:
        return "location_store_exact", 0.90
    if not normalized_brand:
        return None
    if normalized_place == normalized_brand:
        return "location_brand_exact", 0.86
    if normalized_place.startswith(normalized_brand):
        return "location_brand_prefix", 0.84
    if normalized_brand in normalized_place:
        return "location_brand_contains", 0.80
    return None


def _find_brand(normalized_brand: str, brands: Sequence[FranchiseBrand]) -> FranchiseBrand | None:
    for brand in brands:
        if brand.normalized() == normalized_brand:
            return brand
    return None


def _identity_type_for_chain(chain_scale_score: float | None, store_count: int | None) -> str:
    if chain_scale_score is not None:
        if chain_scale_score >= 0.82:
            return "national_franchise"
        if chain_scale_score >= 0.55:
            return "franchise_store"
        return "local_small_chain"
    if store_count is not None:
        if store_count >= 300:
            return "national_franchise"
        if store_count >= 50:
            return "franchise_store"
        return "local_small_chain"
    return "franchise_store"


def _small_merchant_score(identity_type: str, confidence: float) -> float:
    base = {
        "independent_local": 0.92,
        "local_small_chain": 0.76,
        "franchise_store": 0.55,
        "national_franchise": 0.34,
        "corporate_chain": 0.25,
        "unknown": 0.55,
    }.get(identity_type, 0.55)
    if confidence < 0.75:
        base = (base + 0.55) / 2
    return _round4(base)


def _chain_scale_score(brand: FranchiseBrand | None) -> float | None:
    if brand is None:
        return None
    if brand.chain_scale_score is not None:
        return min(max(brand.chain_scale_score, 0.0), 1.0)
    if brand.franchise_store_count is None:
        return None
    return min(1.0, max(0.0, math.log10(max(1, brand.franchise_store_count)) / 3.0))


def _distance_m(
    lat1: float | None,
    lng1: float | None,
    lat2: float | None,
    lng2: float | None,
) -> float | None:
    if None in (lat1, lng1, lat2, lng2):
        return None
    return math.sqrt(((lat1 - lat2) * 111000) ** 2 + ((lng1 - lng2) * 88000) ** 2)


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _round4(value: float | None) -> float:
    if value is None:
        return 0.0
    return round(float(value), 4)


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
