from __future__ import annotations

import hashlib
import html
import json
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime
from typing import Any, Iterable
from xml.etree import ElementTree

CULTURE_INFO_BASE_URL = "https://apis.data.go.kr/B553457/cultureinfo"
DEFAULT_OPERATION = "area2"
DEFAULT_SIDO = "경기"
DEFAULT_SIGUNGU = "수원시"
DEFAULT_SOURCE_NAME = "kcisa"
DEFAULT_DATASET_NAME = "한국문화정보원_한눈에보는문화정보조회서비스"


@dataclass(frozen=True)
class CultureInfoEvent:
    seq: str
    title_ko: str
    event_type: str | None
    venue_name_ko: str | None
    area: str | None
    sigungu: str | None
    starts_on: date | None
    ends_on: date | None
    url: str | None
    thumbnail_url: str | None
    gps_x: float | None
    gps_y: float | None
    source_name: str = DEFAULT_SOURCE_NAME

    @property
    def event_id(self) -> str:
        return f"kcisa-culture-info-{self.seq}"

    @property
    def region_name_ko(self) -> str | None:
        return self.sigungu or self.area

    def to_event_row(self) -> dict[str, Any]:
        return {
            "event_id": self.event_id,
            "title_ko": self.title_ko,
            "title_en": None,
            "event_type": self.event_type,
            "venue_name_ko": self.venue_name_ko,
            "venue_place_id": None,
            "region_name_ko": self.region_name_ko,
            "starts_on": self.starts_on.isoformat() if self.starts_on else None,
            "ends_on": self.ends_on.isoformat() if self.ends_on else None,
            "url": self.url,
            "primary_source": self.source_name,
            "source_record_id": self.seq,
        }

    def to_public_dict(self) -> dict[str, Any]:
        payload = self.to_event_row()
        payload["area"] = self.area
        payload["sigungu"] = self.sigungu
        payload["thumbnail_url"] = self.thumbnail_url
        payload["gps_x"] = self.gps_x
        payload["gps_y"] = self.gps_y
        return payload


@dataclass(frozen=True)
class CultureInfoFetchResult:
    events: tuple[CultureInfoEvent, ...]
    request_count: int
    raw_count: int
    total_count: int | None
    operation: str
    sido: str
    sigungu: str | None
    source_name: str = DEFAULT_SOURCE_NAME
    dataset_name: str = DEFAULT_DATASET_NAME

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "operation": self.operation,
            "sido": self.sido,
            "sigungu": self.sigungu,
            "request_count": self.request_count,
            "raw_count": self.raw_count,
            "total_count": self.total_count,
            "event_count": len(self.events),
            "preview": [item.to_public_dict() for item in self.events[:5]],
        }


def fetch_culture_info_events(
    *,
    service_key: str,
    operation: str = DEFAULT_OPERATION,
    sido: str = DEFAULT_SIDO,
    sigungu: str | None = DEFAULT_SIGUNGU,
    rows: int = 20,
    page_size: int = 10,
    timeout: int = 10,
) -> CultureInfoFetchResult:
    if not service_key:
        raise ValueError("PUBLIC_DATA_SERVICE_KEY is required.")
    if operation not in {"area2", "period2", "realm2", "livelihood2"}:
        raise ValueError("Unsupported KCISA culture info operation.")
    if rows <= 0:
        raise ValueError("rows must be positive.")
    if page_size <= 0:
        raise ValueError("page_size must be positive.")

    import requests

    events: list[CultureInfoEvent] = []
    request_count = 0
    raw_count = 0
    total_count: int | None = None
    page_no = 1
    remaining = rows

    while remaining > 0:
        num_rows = min(page_size, remaining)
        params = _request_params(
            service_key=service_key,
            operation=operation,
            sido=sido,
            sigungu=sigungu,
            page_no=page_no,
            rows=num_rows,
        )
        response = requests.get(
            f"{CULTURE_INFO_BASE_URL}/{operation}",
            params=params,
            timeout=timeout,
        )
        request_count += 1
        response.raise_for_status()
        payload = response.text
        page_events, page_total = parse_culture_info_events(
            payload,
            source_name=DEFAULT_SOURCE_NAME,
        )
        if page_total is not None:
            total_count = page_total
        raw_count += len(page_events)
        events.extend(page_events)
        if len(page_events) < num_rows:
            break
        remaining -= num_rows
        page_no += 1

    return CultureInfoFetchResult(
        events=tuple(_dedupe_events(events)),
        request_count=request_count,
        raw_count=raw_count,
        total_count=total_count,
        operation=operation,
        sido=sido,
        sigungu=sigungu,
    )


def parse_culture_info_events(
    xml_text: str,
    *,
    source_name: str = DEFAULT_SOURCE_NAME,
) -> tuple[list[CultureInfoEvent], int | None]:
    root = ElementTree.fromstring(xml_text)
    _raise_for_error(root)
    total_count = _optional_int(_find_text(root, "totalCount"))
    items = root.findall(".//items/item")
    events = [
        event
        for item in items
        if (event := parse_culture_info_event(item, source_name=source_name)) is not None
    ]
    return events, total_count


def parse_culture_info_event(
    item: ElementTree.Element,
    *,
    source_name: str = DEFAULT_SOURCE_NAME,
) -> CultureInfoEvent | None:
    seq = _find_text(item, "seq", "SEQ", "contentSeq")
    title = _find_text(item, "title", "TITLE", "subject")
    if not (seq and title):
        return None

    return CultureInfoEvent(
        seq=seq,
        title_ko=title,
        event_type=_find_text(item, "realmName", "serviceName", "realm", "eventType"),
        venue_name_ko=_find_text(item, "place", "PLACE", "venue", "spatial"),
        area=_normalize_area(_find_text(item, "area", "sido")),
        sigungu=_find_text(item, "sigungu", "gugun"),
        starts_on=_parse_date(_find_text(item, "startDate", "start", "from")),
        ends_on=_parse_date(_find_text(item, "endDate", "end", "to")),
        url=_find_text(item, "url", "link", "placeUrl"),
        thumbnail_url=_find_text(item, "thumbnail", "imgUrl", "image"),
        gps_x=_optional_float(_find_text(item, "gpsX", "mapx", "longitude")),
        gps_y=_optional_float(_find_text(item, "gpsY", "mapy", "latitude")),
        source_name=source_name,
    )


def upsert_culture_info_events(
    *,
    dsn: str,
    result: CultureInfoFetchResult,
    connect_timeout: int,
) -> dict[str, Any]:
    import psycopg2

    source_payload = result.to_public_dict()
    source_payload["preview"] = []
    file_sha256 = hashlib.sha256(
        json.dumps(source_payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()

    source_sql = """
        INSERT INTO ingest.source_files (
            source_name,
            dataset_name,
            file_name,
            file_sha256,
            local_path
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id
    """
    upsert_sql = """
        INSERT INTO culture.events (
            event_id,
            title_ko,
            title_en,
            event_type,
            venue_name_ko,
            venue_place_id,
            region_name_ko,
            starts_on,
            ends_on,
            url,
            primary_source,
            source_record_id
        )
        VALUES (
            %(event_id)s,
            %(title_ko)s,
            %(title_en)s,
            %(event_type)s,
            %(venue_name_ko)s,
            %(venue_place_id)s,
            %(region_name_ko)s,
            %(starts_on)s,
            %(ends_on)s,
            %(url)s,
            %(primary_source)s,
            %(source_record_id)s
        )
        ON CONFLICT (event_id) DO UPDATE SET
            title_ko = EXCLUDED.title_ko,
            title_en = EXCLUDED.title_en,
            event_type = EXCLUDED.event_type,
            venue_name_ko = EXCLUDED.venue_name_ko,
            venue_place_id = EXCLUDED.venue_place_id,
            region_name_ko = EXCLUDED.region_name_ko,
            starts_on = EXCLUDED.starts_on,
            ends_on = EXCLUDED.ends_on,
            url = EXCLUDED.url,
            primary_source = EXCLUDED.primary_source,
            source_record_id = EXCLUDED.source_record_id,
            updated_at = now()
    """

    inserted_or_updated = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                source_sql,
                (
                    result.source_name,
                    result.dataset_name,
                    _source_file_name(result),
                    file_sha256,
                    None,
                ),
            )
            source_file_id = str(cur.fetchone()[0])
            for event in result.events:
                params = event.to_event_row()
                cur.execute(upsert_sql, params)
                inserted_or_updated += cur.rowcount
        conn.commit()

    return {
        "ok": True,
        "source_file_id": source_file_id,
        "upserted_rows": inserted_or_updated,
        "event_count": len(result.events),
    }


def _request_params(
    *,
    service_key: str,
    operation: str,
    sido: str,
    sigungu: str | None,
    page_no: int,
    rows: int,
) -> dict[str, str]:
    params = {
        "serviceKey": service_key,
        "cPage": str(page_no),
        "numOfrows": str(rows),
    }
    if operation == "area2":
        params["sido"] = sido
        if sigungu:
            params["sigungu"] = sigungu
    elif operation == "period2":
        today = datetime.now(UTC).date()
        params["from"] = today.strftime("%Y%m%d")
        params["to"] = date(today.year + 1, today.month, today.day).strftime("%Y%m%d")
        params["place"] = ""
        params["keyword"] = ""
        params["sortStdr"] = "1"
    return params


def _raise_for_error(root: ElementTree.Element) -> None:
    result_code = _find_text(root, "resultCode")
    if result_code and result_code not in {"00", "0000"}:
        result_message = _find_text(root, "resultMsg") or "KCISA culture info request failed."
        raise RuntimeError(f"KCISA culture info error {result_code}: {result_message}")


def _dedupe_events(events: Iterable[CultureInfoEvent]) -> list[CultureInfoEvent]:
    deduped: dict[str, CultureInfoEvent] = {}
    for event in events:
        deduped[event.event_id] = event
    return list(deduped.values())


def _source_file_name(result: CultureInfoFetchResult) -> str:
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    region = result.sido
    if result.sigungu:
        region = f"{region}_{result.sigungu}"
    return f"kcisa_culture_info_{result.operation}_{region}_{timestamp}.xml"


def _find_text(element: ElementTree.Element, *names: str) -> str | None:
    for name in names:
        child = element.find(name)
        if child is None:
            child = element.find(f".//{name}")
        if child is not None and child.text:
            return _clean_text(child.text)
    return None


def _clean_text(value: Any) -> str | None:
    text = str(value).strip()
    for _ in range(2):
        text = html.unescape(text)
    return text.strip() or None


def _normalize_area(value: Any) -> str | None:
    text = _clean_text(value)
    if text == "경기":
        return "경기도"
    return text


def _parse_date(value: Any) -> date | None:
    text = _clean_text(value)
    if not text:
        return None
    digits = "".join(ch for ch in text if ch.isdigit())
    if len(digits) < 8:
        return None
    try:
        return date(int(digits[:4]), int(digits[4:6]), int(digits[6:8]))
    except ValueError:
        return None


def _optional_float(value: Any) -> float | None:
    text = _clean_text(value)
    if not text:
        return None
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def _optional_int(value: Any) -> int | None:
    text = _clean_text(value)
    if not text:
        return None
    try:
        return int(text)
    except (TypeError, ValueError):
        return None
