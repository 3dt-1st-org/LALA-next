from __future__ import annotations

import hashlib
import json
from collections.abc import Iterable, Sequence
from dataclasses import asdict, dataclass, replace
from datetime import UTC, datetime
from typing import Any

from apps.api.app.services.official_ingest_validation import (
    OfficialRejectionCounter,
    validate_official_coordinate,
)
from apps.api.app.services.official_media import official_image_url_or_none
from apps.api.app.services.official_source_errors import (
    raise_for_official_http_status,
    raise_for_official_result_code,
)
from apps.api.app.services.official_source_receipts import (
    reconcile_partial_run,
    record_official_source_receipt,
)
from apps.api.app.services.region_catalog import infer_region_name_from_address

TOUR_API_BASE_URL = "https://apis.data.go.kr/B551011/KorService2"
TOUR_API_OPERATION = "areaBasedList2"
TOUR_API_DETAIL_IMAGE_OPERATION = "detailImage2"
DEFAULT_AREA_CODE = "31"
DEFAULT_CONTENT_TYPE_IDS = ("12", "14", "15", "39")

CONTENT_TYPE_CATEGORY = {
    "12": "attraction",
    "14": "culture_venue",
    "15": "event",
    "39": "restaurant",
}


@dataclass(frozen=True)
class TourApiPlace:
    content_id: str
    content_type_id: str
    title: str
    category: str
    addr1: str | None
    addr2: str | None
    area_code: str | None
    sigungu_code: str | None
    lat: float
    lng: float
    first_image: str | None
    modified_time: str | None

    @property
    def place_id(self) -> str:
        return f"tour-api-{self.content_id}"

    @property
    def address_ko(self) -> str | None:
        return _join_address(self.addr1, self.addr2)

    @property
    def region_name_ko(self) -> str | None:
        return infer_region_name_ko(self.addr1)

    def to_place_row(self) -> dict[str, Any]:
        return {
            "place_id": self.place_id,
            "name_ko": self.title,
            "category": self.category,
            "address_ko": self.address_ko,
            "image_url": official_image_url_or_none(self.first_image),
            "region_name_ko": self.region_name_ko,
            "province_code": self.area_code,
            "city_code": self.sigungu_code,
            "lat": self.lat,
            "lng": self.lng,
            "primary_source": "tour_api",
            "source_record_id": self.content_id,
        }


@dataclass(frozen=True)
class TourApiFetchResult:
    places: tuple[TourApiPlace, ...]
    request_count: int
    image_request_count: int
    image_error_count: int
    raw_count: int
    area_code: str
    area_codes: tuple[str, ...]
    content_type_ids: tuple[str, ...]
    total_count: int | None = None
    partial_run: bool = False
    rejected_row_count: int = 0
    rejection_reason: str | None = None
    source_updated_at: str | None = None
    source_name: str = "tour_api"
    dataset_name: str = "한국관광공사_국문 관광정보 서비스_GW"
    operation: str = TOUR_API_OPERATION

    @property
    def collected_count(self) -> int:
        return self.raw_count

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "operation": self.operation,
            "area_code": self.area_code,
            "area_codes": list(self.area_codes),
            "content_type_ids": list(self.content_type_ids),
            "request_count": self.request_count,
            "image_request_count": self.image_request_count,
            "image_error_count": self.image_error_count,
            "raw_count": self.raw_count,
            "total_count": self.total_count,
            "collected_count": self.collected_count,
            "partial_run": self.partial_run,
            "rejected_row_count": self.rejected_row_count,
            "rejection_reason": self.rejection_reason,
            "source_updated_at": self.source_updated_at,
            "place_count": len(self.places),
            "preview": [item.to_place_row() for item in self.places[:5]],
        }


def fetch_tour_api_places(
    *,
    service_key: str,
    area_code: str = DEFAULT_AREA_CODE,
    content_type_ids: Sequence[str] = DEFAULT_CONTENT_TYPE_IDS,
    rows: int = 100,
    page_size: int = 20,
    timeout: int = 10,
    fetch_missing_images: bool = True,
) -> TourApiFetchResult:
    if not service_key:
        raise ValueError("PUBLIC_DATA_SERVICE_KEY is required.")
    if rows <= 0:
        raise ValueError("rows must be positive.")
    if page_size <= 0:
        raise ValueError("page_size must be positive.")

    import requests

    places: list[TourApiPlace] = []
    request_count = 0
    raw_count = 0
    total_count_sum = 0
    per_type_rows = max(1, rows // max(len(content_type_ids), 1))
    rejection_counter = OfficialRejectionCounter()

    for content_type_id in content_type_ids:
        remaining = per_type_rows
        page_no = 1
        # totalCount is the total matching rows for this (area, content_type)
        # query and repeats unchanged on every page; capture it once per type so
        # a complete multi-page pull is not double-counted as partial.
        type_total: int | None = None
        while remaining > 0:
            num_rows = min(page_size, remaining)
            response = requests.get(
                f"{TOUR_API_BASE_URL}/{TOUR_API_OPERATION}",
                params={
                    "serviceKey": service_key,
                    "MobileOS": "ETC",
                    "MobileApp": "LALA-next",
                    "_type": "json",
                    "numOfRows": num_rows,
                    "pageNo": page_no,
                    "areaCode": area_code,
                    "contentTypeId": content_type_id,
                    "arrange": "C",
                },
                timeout=timeout,
            )
            request_count += 1
            # Typed, fixed-reason error; the raw upstream URL (which carries
            # serviceKey=...) is never echoed in the exception message (F2).
            raise_for_official_http_status(source="tour_api", status_code=response.status_code)
            payload = response.json()
            items = _extract_items(payload)
            page_total = _body_total_count(payload)
            if page_total and (type_total is None or page_total > type_total):
                type_total = page_total
            raw_count += len(items)
            for item in items:
                place = parse_tour_api_place(item, counter=rejection_counter)
                if place is not None:
                    places.append(place)
            if len(items) < num_rows:
                break
            remaining -= num_rows
            page_no += 1
        if type_total:
            total_count_sum += type_total

    deduped_places = _dedupe_places(places)
    image_request_count = 0
    image_error_count = 0
    if fetch_missing_images:
        (
            deduped_places,
            image_request_count,
            image_error_count,
        ) = _fill_missing_official_images(
            requests_module=requests,
            service_key=service_key,
            places=deduped_places,
            timeout=timeout,
        )

    partial = reconcile_partial_run(total=total_count_sum or None, collected=raw_count)
    return TourApiFetchResult(
        places=tuple(deduped_places),
        request_count=request_count,
        image_request_count=image_request_count,
        image_error_count=image_error_count,
        raw_count=raw_count,
        area_code=area_code,
        area_codes=(area_code,),
        content_type_ids=tuple(content_type_ids),
        total_count=partial.total,
        partial_run=partial.partial_run,
        rejected_row_count=rejection_counter.total,
        rejection_reason=rejection_counter.summary_reason(),
        source_updated_at=_max_modified_time(deduped_places),
    )


def fetch_tour_api_places_for_area_codes(
    *,
    service_key: str,
    area_codes: Sequence[str],
    content_type_ids: Sequence[str] = DEFAULT_CONTENT_TYPE_IDS,
    rows: int = 100,
    page_size: int = 20,
    timeout: int = 10,
    fetch_missing_images: bool = True,
) -> TourApiFetchResult:
    unique_area_codes = tuple(
        dict.fromkeys(str(code).strip() for code in area_codes if str(code).strip())
    )
    if not unique_area_codes:
        raise ValueError("area_codes must not be empty.")

    places: list[TourApiPlace] = []
    request_count = 0
    image_request_count = 0
    image_error_count = 0
    raw_count = 0
    per_area_results: list[TourApiFetchResult] = []
    for area_code in unique_area_codes:
        result = fetch_tour_api_places(
            service_key=service_key,
            area_code=area_code,
            content_type_ids=content_type_ids,
            rows=rows,
            page_size=page_size,
            timeout=timeout,
            fetch_missing_images=fetch_missing_images,
        )
        per_area_results.append(result)
        places.extend(result.places)
        request_count += result.request_count
        image_request_count += result.image_request_count
        image_error_count += result.image_error_count
        raw_count += result.raw_count

    deduped_places = tuple(_dedupe_places(places))
    totals = [r.total_count for r in per_area_results if r.total_count is not None]
    total_count = sum(totals) if len(totals) == len(per_area_results) else None
    rejected_row_count = sum(r.rejected_row_count for r in per_area_results)
    partial = reconcile_partial_run(total=total_count, collected=raw_count)
    reasons: list[str] = []
    for area_result in per_area_results:
        if area_result.rejection_reason and area_result.rejection_reason not in reasons:
            reasons.append(area_result.rejection_reason)
    updated_stamps = [r.source_updated_at for r in per_area_results if r.source_updated_at]
    return TourApiFetchResult(
        places=deduped_places,
        request_count=request_count,
        image_request_count=image_request_count,
        image_error_count=image_error_count,
        raw_count=raw_count,
        area_code=unique_area_codes[0] if len(unique_area_codes) == 1 else "multi",
        area_codes=unique_area_codes,
        content_type_ids=tuple(content_type_ids),
        total_count=total_count,
        partial_run=partial.partial_run,
        rejected_row_count=rejected_row_count,
        rejection_reason="; ".join(reasons) or None,
        source_updated_at=max(updated_stamps) if updated_stamps else None,
    )


def parse_tour_api_place(
    item: dict[str, Any],
    *,
    counter: OfficialRejectionCounter | None = None,
) -> TourApiPlace | None:
    content_id = _optional_text(item.get("contentid"))
    content_type_id = _optional_text(item.get("contenttypeid"))
    title = _optional_text(item.get("title"))
    if not (content_id and content_type_id and title):
        if counter is not None:
            counter.add("missing_required_field")
        return None

    coords = validate_official_coordinate(item.get("mapy"), item.get("mapx"))
    if coords is None:
        if counter is not None:
            counter.add("invalid_coordinate")
        return None
    lat, lng = coords

    category = CONTENT_TYPE_CATEGORY.get(content_type_id)
    if not category:
        if counter is not None:
            counter.add("unmapped_category")
        return None

    return TourApiPlace(
        content_id=content_id,
        content_type_id=content_type_id,
        title=title,
        category=category,
        addr1=_optional_text(item.get("addr1")),
        addr2=_optional_text(item.get("addr2")),
        area_code=_optional_text(item.get("areacode")),
        sigungu_code=_optional_text(item.get("sigungucode")),
        lat=lat,
        lng=lng,
        first_image=official_image_url_or_none(item.get("firstimage")),
        modified_time=_optional_text(item.get("modifiedtime")),
    )


def _fill_missing_official_images(
    *,
    requests_module: Any,
    service_key: str,
    places: Sequence[TourApiPlace],
    timeout: int,
) -> tuple[list[TourApiPlace], int, int]:
    resolved: list[TourApiPlace] = []
    request_count = 0
    error_count = 0
    for place in places:
        if place.first_image:
            resolved.append(place)
            continue
        request_count += 1
        try:
            image_url = _fetch_detail_image_url(
                requests_module=requests_module,
                service_key=service_key,
                content_id=place.content_id,
                timeout=timeout,
            )
        except Exception:
            error_count += 1
            image_url = None
        resolved.append(replace(place, first_image=image_url) if image_url else place)
    return resolved, request_count, error_count


def _fetch_detail_image_url(
    *,
    requests_module: Any,
    service_key: str,
    content_id: str,
    timeout: int,
) -> str | None:
    response = requests_module.get(
        f"{TOUR_API_BASE_URL}/{TOUR_API_DETAIL_IMAGE_OPERATION}",
        params={
            "serviceKey": service_key,
            "MobileOS": "ETC",
            "MobileApp": "LALA-next",
            "_type": "json",
            "contentId": content_id,
            "imageYN": "Y",
            "subImageYN": "Y",
            "numOfRows": 10,
            "pageNo": 1,
        },
        timeout=timeout,
    )
    # Typed, fixed-reason error; the raw upstream URL (which carries
    # serviceKey=...) is never echoed in the exception message (F2). The caller
    # already treats any exception here as non-fatal (missing image, not a
    # place-ingest failure).
    raise_for_official_http_status(source="tour_api", status_code=response.status_code)
    items = _extract_items(response.json())
    return _first_detail_image_url(items)


def _first_detail_image_url(items: Sequence[dict[str, Any]]) -> str | None:
    for item in items:
        image_url = _optional_text(item.get("originimgurl")) or _optional_text(
            item.get("smallimageurl")
        )
        if image_url:
            return official_image_url_or_none(image_url)
    return None


def _places_fingerprint(places: tuple[TourApiPlace, ...]) -> str:
    """Content fingerprint over the actual parsed rows (sorted, deterministic).

    Uses every dataclass field (``asdict``, including ``modified_time``) rather
    than just the persisted subset, so this changes whenever row CONTENT
    changes even when counters (``raw_count``, ``total_count``, ...) stay
    identical -- an upstream correction is never silently treated as an
    unchanged replay (F1). ``source_updated_at`` on the aggregate result gave
    only partial protection (it depends on the upstream actually bumping
    ``modifiedtime``); hashing the rows directly does not.
    """
    sorted_rows = sorted(
        (asdict(item) for item in places),
        key=lambda row: row["content_id"],
    )
    return hashlib.sha256(
        json.dumps(sorted_rows, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()


def upsert_tour_api_places(
    *,
    dsn: str,
    result: TourApiFetchResult,
    connect_timeout: int,
) -> dict[str, Any]:
    import psycopg2

    file_sha256 = _places_fingerprint(result.places)

    upsert_sql = """
        INSERT INTO travel.places (
            place_id,
            name_ko,
            category,
            address_ko,
            image_url,
            region_name_ko,
            province_code,
            city_code,
            lat,
            lng,
            primary_source,
            source_record_id
        )
        VALUES (
            %(place_id)s,
            %(name_ko)s,
            %(category)s,
            %(address_ko)s,
            %(image_url)s,
            %(region_name_ko)s,
            %(province_code)s,
            %(city_code)s,
            %(lat)s,
            %(lng)s,
            %(primary_source)s,
            %(source_record_id)s
        )
        ON CONFLICT (place_id) DO UPDATE SET
            name_ko = EXCLUDED.name_ko,
            category = EXCLUDED.category,
            address_ko = EXCLUDED.address_ko,
            image_url = COALESCE(EXCLUDED.image_url, travel.places.image_url),
            region_name_ko = EXCLUDED.region_name_ko,
            province_code = EXCLUDED.province_code,
            city_code = EXCLUDED.city_code,
            lat = EXCLUDED.lat,
            lng = EXCLUDED.lng,
            primary_source = EXCLUDED.primary_source,
            source_record_id = EXCLUDED.source_record_id,
            updated_at = now()
    """
    inserted_or_updated = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        receipt = record_official_source_receipt(
            conn=conn,
            source_name=result.source_name,
            dataset_name=result.dataset_name,
            file_name=_source_file_name(result),
            file_sha256=file_sha256,
        )
        # The place upserts are idempotent (ON CONFLICT) and always run --
        # `replayed` is receipt/provenance metadata only, never a write gate,
        # so an upstream content-only correction is never silently dropped (F1).
        with conn.cursor() as cur:
            for place in result.places:
                cur.execute(upsert_sql, place.to_place_row())
                inserted_or_updated += cur.rowcount
        conn.commit()

    return {
        "ok": True,
        "source_file_id": receipt.source_file_id,
        "replayed": receipt.replayed,
        "upserted_rows": inserted_or_updated,
        "place_count": len(result.places),
        "total_count": result.total_count,
        "collected_count": result.collected_count,
        "partial_run": result.partial_run,
        "rejected_row_count": result.rejected_row_count,
        "rejection_reason": result.rejection_reason,
        "source_updated_at": result.source_updated_at,
    }


def infer_region_name_ko(address: str | None) -> str | None:
    return infer_region_name_from_address(address)


def _extract_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    header = (payload.get("response") or {}).get("header") or {}
    result_code = str(header.get("resultCode") or "")
    if result_code and result_code != "0000":
        # Convert to a typed, fixed-reason error; never echo the raw upstream
        # resultMsg, which can carry service-key-shaped text.
        raise_for_official_result_code(
            source="tour_api",
            result_code=result_code,
            result_message=header.get("resultMsg"),
        )

    body = (payload.get("response") or {}).get("body") or {}
    items = (body.get("items") or {}).get("item") if isinstance(body.get("items"), dict) else []
    if isinstance(items, dict):
        return [items]
    if isinstance(items, list):
        return [item for item in items if isinstance(item, dict)]
    return []


def _body_total_count(payload: dict[str, Any]) -> int:
    body = (payload.get("response") or {}).get("body") or {}
    try:
        return int(body.get("totalCount") or 0)
    except (TypeError, ValueError):
        return 0


def _max_modified_time(places: Sequence[TourApiPlace]) -> str | None:
    stamps = [place.modified_time for place in places if place.modified_time]
    # TourAPI modifiedtime is a fixed-width numeric timestamp, so lexical max
    # is also chronological -- the freshest upstream update across the page set.
    return max(stamps) if stamps else None


def _dedupe_places(places: Iterable[TourApiPlace]) -> list[TourApiPlace]:
    deduped: dict[str, TourApiPlace] = {}
    for place in places:
        deduped[place.place_id] = place
    return list(deduped.values())


def _source_file_name(result: TourApiFetchResult) -> str:
    content_types = "-".join(result.content_type_ids)
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return f"tour_api_{result.operation}_area{result.area_code}_{content_types}_{timestamp}.json"


def _join_address(addr1: str | None, addr2: str | None) -> str | None:
    values = [value for value in (_optional_text(addr1), _optional_text(addr2)) if value]
    return " ".join(values) if values else None


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
