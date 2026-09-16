from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any, Protocol

from apps.api.app.services.official_source_errors import raise_for_official_http_status
from apps.api.app.services.official_source_receipts import reconcile_partial_run


class HttpGetter(Protocol):
    def __call__(
        self,
        url: str,
        *,
        params: Mapping[str, Any],
        timeout: int,
    ) -> Any: ...


@dataclass(frozen=True)
class OfficialPage:
    items: tuple[Any, ...]
    total_count: int | None = None
    raw_count: int | None = None


@dataclass(frozen=True)
class OfficialPagedResult:
    items: tuple[Any, ...]
    request_count: int
    raw_count: int
    total_count: int | None
    partial_run: bool


def run_official_paged_fetch(
    *,
    source: str,
    url: str,
    service_key: str,
    rows: int,
    page_size: int,
    timeout: int,
    build_params: Callable[[int, int, str], Mapping[str, Any]],
    parse_page: Callable[[Any], OfficialPage],
    http_get: HttpGetter,
    response_payload: Callable[[Any], Any],
    total_strategy: str = "latest",
) -> OfficialPagedResult:
    """Run common official-source page/count/error bookkeeping.

    Provider-specific URL params, payload parsing, detail-image calls, and SQL
    persistence stay in their owning modules. This helper only centralizes the
    shared lifecycle: page sizing, HTTP status classification, request/raw
    counters, total-count reconciliation, and early stop on a short page.
    """
    if rows <= 0:
        raise ValueError("rows must be positive.")
    if page_size <= 0:
        raise ValueError("page_size must be positive.")

    items: list[Any] = []
    request_count = 0
    raw_count = 0
    total_count: int | None = None
    remaining = rows
    page_no = 1

    while remaining > 0:
        num_rows = min(page_size, remaining)
        response = http_get(
            url,
            params=build_params(page_no, num_rows, service_key),
            timeout=timeout,
        )
        request_count += 1
        raise_for_official_http_status(source=source, status_code=response.status_code)
        page = parse_page(response_payload(response))
        page_items = list(page.items)
        raw_count += page.raw_count if page.raw_count is not None else len(page_items)
        items.extend(page_items)
        if page.total_count is not None:
            if total_strategy == "sum":
                total_count = (total_count or 0) + page.total_count
            else:
                total_count = page.total_count
        if len(page_items) < num_rows:
            break
        remaining -= num_rows
        page_no += 1

    partial = reconcile_partial_run(total=total_count, collected=raw_count)
    return OfficialPagedResult(
        items=tuple(items),
        request_count=request_count,
        raw_count=raw_count,
        total_count=partial.total,
        partial_run=partial.partial_run,
    )
