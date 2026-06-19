from __future__ import annotations

import json
import math
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any

from apps.api.app.services.franchise_identity import normalize_business_name

DEFAULT_SOURCE_NAME = "fair_trade_commission"
DEFAULT_DATASET_NAME = "공정거래위원회_가맹정보_브랜드별 가맹점 현황 제공 서비스"
DEFAULT_API_URL = "https://apis.data.go.kr/1130000/FftcBrandFrcsStatsService/getBrandFrcsStats"


@dataclass(frozen=True)
class FranchiseBrandReference:
    brand_id: str
    brand_name_ko: str
    normalized_brand_name: str
    headquarters_name_ko: str | None
    business_category: str | None
    main_product: str | None
    franchise_store_count: int | None
    average_sales_amount: float | None
    chain_scale_score: float | None
    primary_source: str
    source_record_id: str

    def to_public_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class FranchiseReferenceIngestResult:
    source_name: str
    dataset_name: str
    source_url: str
    year: int
    requested_rows: int
    total_count: int
    parsed_row_count: int
    skipped_row_count: int
    brands: tuple[FranchiseBrandReference, ...]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "source_url": self.source_url,
            "year": self.year,
            "requested_rows": self.requested_rows,
            "total_count": self.total_count,
            "parsed_row_count": self.parsed_row_count,
            "skipped_row_count": self.skipped_row_count,
            "preview": [item.to_public_dict() for item in self.brands[:5]],
        }


def fetch_franchise_brand_references(
    *,
    api_key: str,
    year: int,
    rows: int,
    page_size: int,
    timeout: int,
    api_url: str = DEFAULT_API_URL,
    source_name: str = DEFAULT_SOURCE_NAME,
    dataset_name: str = DEFAULT_DATASET_NAME,
) -> FranchiseReferenceIngestResult:
    if not api_key.strip():
        raise ValueError("PUBLIC_DATA_SERVICE_KEY is required.")
    if year < 2000:
        raise ValueError("year must be 2000 or later.")
    if rows < 0:
        raise ValueError("rows cannot be negative.")
    if page_size <= 0 or page_size > 1000:
        raise ValueError("page_size must be between 1 and 1000.")

    parsed_by_id: dict[str, FranchiseBrandReference] = {}
    skipped = 0
    total_count = 0
    page_no = 1
    requested_rows = rows

    while True:
        payload = _fetch_page(
            api_url=api_url,
            api_key=api_key,
            year=year,
            page_no=page_no,
            page_size=page_size,
            timeout=timeout,
        )
        total_count = _int_value(payload.get("totalCount")) or 0
        page_records, page_skipped = parse_brand_stats_items(
            payload.get("items") or [],
            year=year,
            source_name=source_name,
        )
        skipped += page_skipped
        for record in page_records:
            if record.source_record_id in parsed_by_id:
                skipped += 1
            parsed_by_id[record.source_record_id] = record

        target_rows = total_count if rows == 0 else min(rows, total_count or rows)
        if len(parsed_by_id) >= target_rows:
            break
        if not page_records and not payload.get("items"):
            break
        if total_count and page_no * page_size >= total_count:
            break
        page_no += 1

    parsed = list(parsed_by_id.values())
    target_rows = total_count if rows == 0 else min(rows, total_count or rows)
    parsed = parsed[:target_rows]
    return FranchiseReferenceIngestResult(
        source_name=source_name,
        dataset_name=dataset_name,
        source_url=api_url,
        year=year,
        requested_rows=requested_rows,
        total_count=total_count,
        parsed_row_count=len(parsed),
        skipped_row_count=skipped,
        brands=tuple(parsed),
    )


def parse_brand_stats_items(
    items: Any,
    *,
    year: int,
    source_name: str = DEFAULT_SOURCE_NAME,
) -> tuple[list[FranchiseBrandReference], int]:
    if isinstance(items, dict):
        item_values = [items]
    elif isinstance(items, list):
        item_values = items
    else:
        return [], 0

    records: list[FranchiseBrandReference] = []
    skipped = 0
    for item in item_values:
        if not isinstance(item, dict):
            skipped += 1
            continue
        brand_name = _text_value(item.get("brandNm"))
        if not brand_name:
            skipped += 1
            continue
        headquarters_name = _text_value(item.get("corpNm"))
        large_category = _text_value(item.get("indutyLclasNm"))
        middle_category = _text_value(item.get("indutyMlsfcNm"))
        business_category = " / ".join(
            value for value in (large_category, middle_category) if value
        ) or None
        source_year = _int_value(item.get("yr")) or year
        franchise_store_count = _int_value(item.get("frcsCnt"))
        normalized_brand_name = normalize_business_name(brand_name)
        source_record_id = ":".join(
            [
                str(source_year),
                normalize_business_name(headquarters_name),
                normalized_brand_name,
            ]
        )
        records.append(
            FranchiseBrandReference(
                brand_id=source_record_id,
                brand_name_ko=brand_name,
                normalized_brand_name=normalized_brand_name,
                headquarters_name_ko=headquarters_name,
                business_category=business_category,
                main_product=None,
                franchise_store_count=franchise_store_count,
                average_sales_amount=_float_value(item.get("avrgSlsAmt")),
                chain_scale_score=_chain_scale_score(franchise_store_count),
                primary_source=source_name,
                source_record_id=source_record_id,
            )
        )
    return records, skipped


def insert_franchise_brand_references(
    *,
    dsn: str,
    result: FranchiseReferenceIngestResult,
    connect_timeout: int,
) -> dict[str, Any]:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if not result.brands:
        return {"inserted_or_updated_rows": 0}

    import psycopg2
    from psycopg2.extras import execute_values

    sql = """
        INSERT INTO economy.franchise_brands (
            brand_id,
            brand_name_ko,
            normalized_brand_name,
            headquarters_name_ko,
            business_category,
            main_product,
            franchise_store_count,
            average_sales_amount,
            chain_scale_score,
            primary_source,
            source_record_id
        )
        VALUES %s
        ON CONFLICT (primary_source, source_record_id)
        WHERE source_record_id IS NOT NULL
        DO UPDATE SET
            brand_id = EXCLUDED.brand_id,
            brand_name_ko = EXCLUDED.brand_name_ko,
            normalized_brand_name = EXCLUDED.normalized_brand_name,
            headquarters_name_ko = EXCLUDED.headquarters_name_ko,
            business_category = EXCLUDED.business_category,
            main_product = EXCLUDED.main_product,
            franchise_store_count = EXCLUDED.franchise_store_count,
            average_sales_amount = EXCLUDED.average_sales_amount,
            chain_scale_score = EXCLUDED.chain_scale_score,
            updated_at = now()
    """
    values = [
        (
            item.brand_id,
            item.brand_name_ko,
            item.normalized_brand_name,
            item.headquarters_name_ko,
            item.business_category,
            item.main_product,
            item.franchise_store_count,
            item.average_sales_amount,
            item.chain_scale_score,
            item.primary_source,
            item.source_record_id,
        )
        for item in result.brands
    ]
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            execute_values(cur, sql, values, page_size=500)
        conn.commit()
    return {"inserted_or_updated_rows": len(values)}


def _fetch_page(
    *,
    api_url: str,
    api_key: str,
    year: int,
    page_no: int,
    page_size: int,
    timeout: int,
) -> dict[str, Any]:
    query = urllib.parse.urlencode(
        {
            "serviceKey": api_key,
            "pageNo": str(page_no),
            "numOfRows": str(page_size),
            "resultType": "json",
            "yr": str(year),
        }
    )
    with urllib.request.urlopen(f"{api_url}?{query}", timeout=timeout) as response:
        raw = response.read().decode("utf-8", errors="replace")
    payload = json.loads(raw)
    if str(payload.get("resultCode")) != "00":
        message = str(payload.get("resultMsg") or "franchise reference API error")
        raise ValueError(message)
    return payload


def _chain_scale_score(store_count: int | None) -> float | None:
    if store_count is None:
        return None
    return round(min(1.0, max(0.0, math.log10(max(1, store_count)) / 3.0)), 4)


def _text_value(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _int_value(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(float(str(value).replace(",", "")))
    except (TypeError, ValueError):
        return None


def _float_value(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(str(value).replace(",", ""))
    except (TypeError, ValueError):
        return None
