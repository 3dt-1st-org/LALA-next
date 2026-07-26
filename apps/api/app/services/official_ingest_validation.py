"""Bounded input validation + rejection accounting for official-source ingests.

Validates the fields the reliability contract calls out -- coordinates, dates,
categories, image URLs -- and counts rejected rows with a single bounded summary
reason. No raw row text is ever stored on the counter: the operator only sees
*which* rejection categories fired and how many rows each dropped.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from typing import Final

VALID_LAT_RANGE: Final[tuple[float, float]] = (-90.0, 90.0)
VALID_LNG_RANGE: Final[tuple[float, float]] = (-180.0, 180.0)

# Official-source rows frequently emit (0, 0) as a "missing coordinate" sentinel.
# That point is valid per the global bounds but is never a real Korean location,
# so it is dropped here (null-island guard).
_NULL_ISLAND: Final[tuple[float, float]] = (0.0, 0.0)

# Fixed labels for the bounded rejection categories -- never raw row content.
REJECTION_REASON_LABELS: Final[dict[str, str]] = {
    "invalid_coordinate": "invalid_coordinate",
    "invalid_date": "invalid_date",
    "unmapped_category": "unmapped_category",
    "invalid_image_url": "invalid_image_url",
    "missing_required_field": "missing_required_field",
}


def validate_official_coordinate(
    lat: object,
    lng: object,
) -> tuple[float, float] | None:
    """Return ``(lat, lng)`` when within global bounds, else ``None``.

    Rejects non-numeric values, out-of-range coordinates, and the (0, 0)
    null-island sentinel used by upstreams to mean "no coordinate". Does not
    restrict to Korean bounds, so legitimate edge coords are retained.
    """
    try:
        lat_value = float(lat)  # type: ignore[arg-type]
        lng_value = float(lng)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if (lat_value, lng_value) == _NULL_ISLAND:
        return None
    if not VALID_LAT_RANGE[0] <= lat_value <= VALID_LAT_RANGE[1]:
        return None
    if not VALID_LNG_RANGE[0] <= lng_value <= VALID_LNG_RANGE[1]:
        return None
    return lat_value, lng_value


@dataclass
class OfficialRejectionCounter:
    """Counts dropped rows by bounded category; emits one fixed summary string."""

    _counts: Counter[str] = field(default_factory=Counter)

    def add(self, reason_key: str) -> None:
        self._counts[reason_key] += 1

    @property
    def total(self) -> int:
        return sum(self._counts.values())

    def counts(self) -> dict[str, int]:
        return dict(self._counts)

    def summary_reason(self) -> str | None:
        """A bounded operator-facing reason, or ``None`` if nothing was rejected."""
        if not self._counts:
            return None
        # Stable ordering for deterministic output across runs.
        rendered = ", ".join(
            f"{REJECTION_REASON_LABELS[key]}={count}"
            for key, count in sorted(self._counts.items())
            if key in REJECTION_REASON_LABELS and count
        )
        if not rendered:
            return None
        return f"rows skipped ({rendered})"
