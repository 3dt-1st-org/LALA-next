#!/usr/bin/env python3
"""Deployed Flutter web map-marker contract validator.

The production map renders Naver Dynamic Map markers inside the same-origin
``naver-map-embed.html`` iframe, which publishes bridge stats
(``__lalaLastMapMarkerStats``), dataset counts on its ``#map`` element, and
``.lala-marker-pin`` / ``.lala-marker-cluster`` DOM elements carrying
``data-lala-cluster-count`` member counts. Markers living in the top document
are tolerated as drift so the smoke tracks the marker location, not one
architecture.

Contract (map_helpers.dart pin-first clustering):
- clustering engages only when the visible place count reaches 24 or the app
  map level reaches the far-zoom boundary (10); a sparse zoomed-in list must
  stay on individual pins;
- the rendered payload is capped at 60 visible places;
- every cluster carries a member count of at least 2;
- individual pins plus cluster member counts must reconcile exactly with the
  live place count, so missing, duplicated, or empty rendering fails closed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Mirrors map_helpers.dart: clusterCountThreshold / clusterFarLevel / take(60).
CLUSTER_COUNT_THRESHOLD = 24
CLUSTER_FAR_LEVEL = 10
VISIBLE_PLACE_CAP = 60

FAIL_PREFIX = "Flutter location flow"


def _fail(message: str) -> None:
    raise SystemExit(f"{FAIL_PREFIX} {message}")


def _as_int(value: object) -> int | None:
    try:
        if isinstance(value, bool):
            return None
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _collect(source: object) -> dict | None:
    """Normalize one evidence document (iframe or top-level) to counts."""
    if not isinstance(source, dict):
        return None
    dom_pins = _as_int(source.get("pins"))
    dom_clusters = _as_int(source.get("clusters"))
    cluster_counts_raw = source.get("clusterCounts")
    cluster_counts: list[int] = []
    if isinstance(cluster_counts_raw, list):
        for raw in cluster_counts_raw:
            parsed = _as_int(raw)
            cluster_counts.append(parsed if parsed is not None else -1)
    stats = source.get("stats") if isinstance(source.get("stats"), dict) else {}
    stat_pins = _as_int(stats.get("pins"))
    stat_clusters = _as_int(stats.get("clusters"))
    stat_total = _as_int(stats.get("total"))
    stat_level = _as_int(stats.get("level"))
    dataset_level = _as_int(source.get("mapLevel"))
    return {
        "dom_pins": dom_pins,
        "dom_clusters": dom_clusters,
        "cluster_counts": cluster_counts,
        "stat_pins": stat_pins,
        "stat_clusters": stat_clusters,
        "stat_total": stat_total,
        "level": stat_level if stat_level is not None else dataset_level,
        "sample": source.get("sampleMarkers"),
    }


def _evidence(state: dict) -> tuple[dict, str]:
    """Pick the marker evidence document, preferring the iframe bridge."""
    frame = _collect(state.get("frame"))
    top = _collect(state.get("topDocument"))

    def marker_count(source: dict | None) -> int:
        if source is None:
            return 0
        dom = (source["dom_pins"] or 0) + (source["dom_clusters"] or 0)
        stats = (source["stat_pins"] or 0) + (source["stat_clusters"] or 0)
        return max(dom, stats)

    frame_markers = marker_count(frame)
    top_markers = marker_count(top)
    if frame_markers > 0 and top_markers > 0:
        _fail("rendered markers in both the map iframe and the top document.")
    if frame is not None and frame_markers > 0:
        return frame, "iframe"
    if top is not None and top_markers > 0:
        return top, "top-document"
    # No markers yet: still require a live map surface to exist.
    if frame is not None:
        return frame, "iframe"
    if top is not None:
        return top, "top-document"
    _fail("had no map container or marker bridge to inspect.")


def _reconciled_pins(source: dict, origin: str) -> tuple[int, int]:
    """Resolve pin/cluster counts, failing closed on stale bridge state."""
    dom_pins = source["dom_pins"]
    dom_clusters = source["dom_clusters"]
    stat_pins = source["stat_pins"]
    stat_clusters = source["stat_clusters"]
    if dom_pins is None and dom_clusters is None and stat_pins is None and stat_clusters is None:
        _fail("marker state was malformed (no numeric pin or cluster counts).")
    pins = dom_pins if dom_pins is not None else 0
    clusters = dom_clusters if dom_clusters is not None else 0
    if stat_pins is not None or stat_clusters is not None:
        stat_p = stat_pins if stat_pins is not None else 0
        stat_c = stat_clusters if stat_clusters is not None else 0
        if origin == "iframe" and dom_pins is not None and (stat_p, stat_c) != (pins, clusters):
            _fail(
                "marker state was stale: bridge stats and rendered DOM marker "
                f"counts disagree ({stat_p}+{stat_c} vs {pins}+{clusters})."
            )
        pins = max(pins, stat_p)
        clusters = max(clusters, stat_c)
        if source["stat_total"] is not None and source["stat_total"] != pins + clusters:
            _fail(
                "marker state was stale: bridge entry total does not match the "
                f"rendered marker count ({source['stat_total']} vs {pins + clusters})."
            )
    return pins, clusters


def _cluster_member_counts(source: dict, clusters: int) -> list[int]:
    counts = source["cluster_counts"]
    if len(counts) != clusters:
        _fail(
            "marker state was stale: cluster DOM member counts do not cover every "
            f"rendered cluster ({len(counts)} of {clusters})."
        )
    for count in counts:
        if count is None or count < 2:
            _fail(f"rendered an invalid cluster marker (member count {count!r}).")
    return counts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--state-file",
        type=Path,
        required=True,
        help="Marker-state JSON captured from the deployed page.",
    )
    parser.add_argument(
        "--place-count-file",
        type=Path,
        required=True,
        help="Text file holding the live API place count for the smoke viewport.",
    )
    args = parser.parse_args(argv)

    try:
        state = json.loads(args.state_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _fail(f"marker state could not be parsed: {exc}")
    if not isinstance(state, dict):
        _fail("marker state could not be parsed (not a JSON object).")

    try:
        place_count = int(args.place_count_file.read_text(encoding="utf-8").strip() or 0)
    except (OSError, ValueError):
        place_count = 0
    if place_count <= 0:
        _fail("did not capture a positive live place count to reconcile against.")

    source, origin = _evidence(state)
    pins, clusters = _reconciled_pins(source, origin)
    if pins <= 0 and clusters <= 0:
        _fail("rendered no real map pins or clusters.")

    member_counts = _cluster_member_counts(source, clusters)

    # Pin-first clustering: clusters are legitimate only in a dense viewport.
    level = source["level"] or 0
    dense = place_count >= CLUSTER_COUNT_THRESHOLD or level >= CLUSTER_FAR_LEVEL
    if clusters > 0 and not dense:
        _fail(
            "clustered a sparse zoomed-in map before the far-zoom boundary "
            f"({place_count} places, level {level})."
        )

    expected = min(place_count, VISIBLE_PLACE_CAP)
    coverage = pins + sum(member_counts)
    if coverage != expected:
        _fail(
            "marker rendering did not reconcile with the live place count "
            f"({coverage} covered vs {expected} expected: "
            f"{'missing' if coverage < expected else 'duplicated'} places)."
        )

    if clusters > 0 and source["sample"] is None:
        _fail("marker sample was empty while clusters rendered.")

    print(
        "Flutter web map markers reconciled: "
        f"origin={origin} pins={pins} clusters={clusters} "
        f"members={sum(member_counts)} live_places={expected} level={level}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
