from __future__ import annotations

import hashlib
import html
import json
import re
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any, Iterable
from xml.etree import ElementTree
from zoneinfo import ZoneInfo

KOPIS_BASE_URL = "http://www.kopis.or.kr/openApi/restful"
KOPIS_OPERATION = "pblprfr"
DEFAULT_SIGNGUCODE = "41"
DEFAULT_SOURCE_NAME = "kopis"
DEFAULT_DATASET_NAME = "공연예술통합전산망_공연목록 조회 서비스"
MAX_DATE_RANGE_DAYS = 31
KST = ZoneInfo("Asia/Seoul")

GYEONGGI_REGION_ALIASES = {
    "가평": "가평군",
    "가평군": "가평군",
    "고양": "고양시",
    "고양시": "고양시",
    "과천": "과천시",
    "과천시": "과천시",
    "광명": "광명시",
    "광명시": "광명시",
    "광주": "광주시",
    "광주시": "광주시",
    "구리": "구리시",
    "구리시": "구리시",
    "군포": "군포시",
    "군포시": "군포시",
    "김포": "김포시",
    "김포시": "김포시",
    "남양주": "남양주시",
    "남양주시": "남양주시",
    "동두천": "동두천시",
    "동두천시": "동두천시",
    "부천": "부천시",
    "부천시": "부천시",
    "성남": "성남시",
    "성남시": "성남시",
    "수원": "수원시",
    "수원시": "수원시",
    "시흥": "시흥시",
    "시흥시": "시흥시",
    "안산": "안산시",
    "안산시": "안산시",
    "안성": "안성시",
    "안성시": "안성시",
    "안양": "안양시",
    "안양시": "안양시",
    "양주": "양주시",
    "양주시": "양주시",
    "양평": "양평군",
    "양평군": "양평군",
    "여주": "여주시",
    "여주시": "여주시",
    "연천": "연천군",
    "연천군": "연천군",
    "오산": "오산시",
    "오산시": "오산시",
    "용인": "용인시",
    "용인시": "용인시",
    "의왕": "의왕시",
    "의왕시": "의왕시",
    "의정부": "의정부시",
    "의정부시": "의정부시",
    "이천": "이천시",
    "이천시": "이천시",
    "파주": "파주시",
    "파주시": "파주시",
    "평택": "평택시",
    "평택시": "평택시",
    "포천": "포천시",
    "포천시": "포천시",
    "하남": "하남시",
    "하남시": "하남시",
    "화성": "화성시",
    "화성시": "화성시",
}


@dataclass(frozen=True)
class KopisPerformance:
    mt20id: str
    title_ko: str
    starts_on: date | None
    ends_on: date | None
    venue_name_ko: str | None
    poster_url: str | None
    area: str | None
    genre_name: str | None
    openrun: str | None
    performance_state: str | None

    @property
    def event_id(self) -> str:
        return f"kopis-{self.mt20id}"

    @property
    def region_name_ko(self) -> str | None:
        return infer_region_name_ko(
            title=self.title_ko,
            venue_name=self.venue_name_ko,
            area=self.area,
        )

    def to_event_row(self) -> dict[str, Any]:
        return {
            "event_id": self.event_id,
            "title_ko": self.title_ko,
            "title_en": None,
            "event_type": self.genre_name,
            "venue_name_ko": self.venue_name_ko,
            "venue_place_id": None,
            "region_name_ko": self.region_name_ko,
            "starts_on": self.starts_on.isoformat() if self.starts_on else None,
            "ends_on": self.ends_on.isoformat() if self.ends_on else None,
            "url": None,
            "primary_source": DEFAULT_SOURCE_NAME,
            "source_record_id": self.mt20id,
        }

    def to_public_dict(self) -> dict[str, Any]:
        payload = self.to_event_row()
        payload["poster_url"] = self.poster_url
        payload["area"] = self.area
        payload["openrun"] = self.openrun
        payload["performance_state"] = self.performance_state
        return payload


@dataclass(frozen=True)
class KopisFetchResult:
    performances: tuple[KopisPerformance, ...]
    request_count: int
    raw_count: int
    stdate: str
    eddate: str
    signgucode: str | None
    signgucodesub: str | None
    prfstate: str | None
    source_name: str = DEFAULT_SOURCE_NAME
    dataset_name: str = DEFAULT_DATASET_NAME
    operation: str = KOPIS_OPERATION

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "operation": self.operation,
            "stdate": self.stdate,
            "eddate": self.eddate,
            "signgucode": self.signgucode,
            "signgucodesub": self.signgucodesub,
            "prfstate": self.prfstate,
            "request_count": self.request_count,
            "raw_count": self.raw_count,
            "performance_count": len(self.performances),
            "preview": [item.to_public_dict() for item in self.performances[:5]],
        }


def default_date_window(*, today: date | None = None, days: int = 30) -> tuple[str, str]:
    base = today or datetime.now(KST).date()
    return base.strftime("%Y%m%d"), (base + timedelta(days=days)).strftime("%Y%m%d")


def fetch_kopis_performances(
    *,
    service_key: str,
    stdate: str,
    eddate: str,
    signgucode: str | None = DEFAULT_SIGNGUCODE,
    signgucodesub: str | None = None,
    prfstate: str | None = None,
    rows: int = 20,
    page_size: int = 10,
    timeout: int = 10,
) -> KopisFetchResult:
    if not service_key:
        raise ValueError("KOPIS_API_KEY is required.")
    _validate_date_window(stdate, eddate)
    if rows <= 0:
        raise ValueError("rows must be positive.")
    if page_size <= 0:
        raise ValueError("page_size must be positive.")

    import requests

    performances: list[KopisPerformance] = []
    request_count = 0
    raw_count = 0
    page_no = 1
    remaining = rows

    while remaining > 0:
        num_rows = min(page_size, remaining)
        response = requests.get(
            f"{KOPIS_BASE_URL}/{KOPIS_OPERATION}",
            params=_request_params(
                service_key=service_key,
                stdate=stdate,
                eddate=eddate,
                page_no=page_no,
                rows=num_rows,
                signgucode=signgucode,
                signgucodesub=signgucodesub,
                prfstate=prfstate,
            ),
            timeout=timeout,
        )
        request_count += 1
        response.raise_for_status()
        page_items = parse_kopis_performances(response.text)
        raw_count += len(page_items)
        performances.extend(page_items)
        if len(page_items) < num_rows:
            break
        remaining -= num_rows
        page_no += 1

    return KopisFetchResult(
        performances=tuple(_dedupe_performances(performances)),
        request_count=request_count,
        raw_count=raw_count,
        stdate=stdate,
        eddate=eddate,
        signgucode=signgucode,
        signgucodesub=signgucodesub,
        prfstate=prfstate,
    )


def parse_kopis_performances(xml_text: str) -> list[KopisPerformance]:
    root = ElementTree.fromstring(xml_text)
    _raise_for_error(root)
    performances: list[KopisPerformance] = []
    for item in root.findall(".//db"):
        if performance := parse_kopis_performance(item):
            performances.append(performance)
    return performances


def parse_kopis_performance(item: ElementTree.Element) -> KopisPerformance | None:
    mt20id = _find_text(item, "mt20id")
    title = _find_text(item, "prfnm")
    if not (mt20id and title):
        return None
    return KopisPerformance(
        mt20id=mt20id,
        title_ko=title,
        starts_on=_parse_date(_find_text(item, "prfpdfrom")),
        ends_on=_parse_date(_find_text(item, "prfpdto")),
        venue_name_ko=_find_text(item, "fcltynm"),
        poster_url=_find_text(item, "poster"),
        area=_find_text(item, "area"),
        genre_name=_find_text(item, "genrenm"),
        openrun=_find_text(item, "openrun"),
        performance_state=_find_text(item, "prfstate"),
    )


def upsert_kopis_performances(
    *,
    dsn: str,
    result: KopisFetchResult,
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
            for performance in result.performances:
                cur.execute(upsert_sql, performance.to_event_row())
                inserted_or_updated += cur.rowcount
        conn.commit()

    return {
        "ok": True,
        "source_file_id": source_file_id,
        "upserted_rows": inserted_or_updated,
        "performance_count": len(result.performances),
    }


def infer_region_name_ko(
    *,
    title: str | None,
    venue_name: str | None,
    area: str | None,
) -> str | None:
    area_text = _clean_text(area)
    texts = [_clean_text(title), _clean_text(venue_name)]
    if area_text == "경기도":
        for text in texts:
            region = _infer_gyeonggi_region_from_text(text)
            if region:
                return region
    return area_text


def _request_params(
    *,
    service_key: str,
    stdate: str,
    eddate: str,
    page_no: int,
    rows: int,
    signgucode: str | None,
    signgucodesub: str | None,
    prfstate: str | None,
) -> dict[str, str]:
    params = {
        "service": service_key,
        "stdate": stdate,
        "eddate": eddate,
        "cpage": str(page_no),
        "rows": str(rows),
    }
    if signgucode:
        params["signgucode"] = signgucode
    if signgucodesub:
        params["signgucodesub"] = signgucodesub
    if prfstate:
        params["prfstate"] = prfstate
    return params


def _validate_date_window(stdate: str, eddate: str) -> None:
    start = _parse_date(stdate)
    end = _parse_date(eddate)
    if not start or not end:
        raise ValueError("stdate and eddate must use YYYYMMDD or YYYY.MM.DD.")
    if end < start:
        raise ValueError("eddate must be on or after stdate.")
    if (end - start).days + 1 > MAX_DATE_RANGE_DAYS:
        raise ValueError("KOPIS date windows must be 31 days or less.")


def _raise_for_error(root: ElementTree.Element) -> None:
    error_code = _find_text(root, "resultCode", "returnReasonCode", "code")
    if error_code and error_code not in {"00", "0000"}:
        message = _find_text(root, "resultMsg", "returnAuthMsg", "message") or "KOPIS request failed."
        raise RuntimeError(f"KOPIS error {error_code}: {message}")
    error_message = _find_text(root, "returnAuthMsg", "errMsg")
    if error_message and "SERVICE_KEY" in error_message.upper():
        raise RuntimeError(f"KOPIS error: {error_message}")


def _dedupe_performances(performances: Iterable[KopisPerformance]) -> list[KopisPerformance]:
    deduped: dict[str, KopisPerformance] = {}
    for performance in performances:
        deduped[performance.event_id] = performance
    return list(deduped.values())


def _source_file_name(result: KopisFetchResult) -> str:
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    region = result.signgucode or "all"
    if result.signgucodesub:
        region = f"{region}_{result.signgucodesub}"
    return f"kopis_{result.operation}_{region}_{result.stdate}_{result.eddate}_{timestamp}.xml"


def _find_text(element: ElementTree.Element, *names: str) -> str | None:
    for name in names:
        child = element.find(name)
        if child is None:
            child = element.find(f".//{name}")
        if child is not None and child.text:
            return _clean_text(child.text)
    return None


def _clean_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    for _ in range(2):
        text = html.unescape(text)
    return text.strip() or None


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


def _infer_gyeonggi_region_from_text(value: str | None) -> str | None:
    text = value or ""
    bracket_candidates = re.findall(r"[\[\(（【]([^\]\)）】]+)[\]\)）】]", text)
    for candidate in bracket_candidates:
        region = _lookup_gyeonggi_region(candidate)
        if region:
            return region
    return _lookup_gyeonggi_region(text)


def _lookup_gyeonggi_region(text: str) -> str | None:
    compact = re.sub(r"\s+", "", text)
    for alias, region in sorted(
        GYEONGGI_REGION_ALIASES.items(),
        key=lambda item: len(item[0]),
        reverse=True,
    ):
        if alias in compact:
            return region
    return None
