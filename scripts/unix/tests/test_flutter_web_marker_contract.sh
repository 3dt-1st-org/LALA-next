#!/usr/bin/env bash
# Test-only: verifies scripts/unix/_flutter_web_marker_contract.py enforces the
# deployed Flutter web map-marker contract against fixture marker states. Every
# fixture mirrors the shape the smoke probe captures from the same-origin map
# iframe (or the top document, as drift); no real place data, coordinates, or
# identifiers are used.
#
# Wired into scripts/unix/verify_repo.sh, so it runs in the unix-verification
# CI job. Run directly:
#
#   bash scripts/unix/tests/test_flutter_web_marker_contract.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CONTRACT="$ROOT/scripts/unix/_flutter_web_marker_contract.py"
PYTHON="${PYTHON:-python3}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# run_case <expect: pass|fail> <label> <place_count> <state_json>
run_case() {
  local expect="$1" label="$2" place_count="$3" state_json="$4"
  printf '%s' "$state_json" >"$TMP/state.json"
  printf '%s' "$place_count" >"$TMP/place-count.txt"
  set +e
  output="$("$PYTHON" "$CONTRACT" \
    --state-file "$TMP/state.json" \
    --place-count-file "$TMP/place-count.txt" 2>&1)"
  rc=$?
  set -e
  if [[ "$expect" == "pass" && $rc -ne 0 ]]; then
    fail "$label: expected PASS, got rc=$rc: $output"
  fi
  if [[ "$expect" == "fail" && $rc -eq 0 ]]; then
    fail "$label: expected FAIL, got PASS: $output"
  fi
  echo "ok ($expect): $label"
}

# A frame-state builder with overridable parts; defaults describe a healthy
# iframe render.
frame_state() {
  local pins="$1" clusters="$2" counts_json="$3" level="$4"
  printf '{
    "frame": {
      "pins": %s,
      "clusters": %s,
      "clusterCounts": %s,
      "sampleMarkers": [%s],
      "stats": {"provider": "naver", "pins": %s, "clusters": %s, "total": %s, "level": %s},
      "mapLevel": "%s",
      "containerPins": "%s",
      "containerClusters": "%s"
    },
    "topDocument": {
      "pins": 0,
      "clusters": 0,
      "clusterCounts": [],
      "sampleMarkers": [],
      "stats": null,
      "mapLevel": null,
      "containerPins": null,
      "containerClusters": null
    }
  }' \
    "$pins" "$clusters" "$counts_json" \
    "$(sample_entries "$pins" pin)" \
    "$pins" "$clusters" "$((pins + clusters))" "$level" \
    "$level" "$pins" "$clusters"
}

sample_entries() {
  # Enough placeholder samples to look rendered; content is irrelevant here.
  local count="$1" kind="$2" out="" i
  for ((i = 0; i < count && i < 8; i += 1)); do
    [[ -n "$out" ]] && out+=","
    out+="{\"id\": \"fixture-$kind-$i\", \"category\": \"restaurant\", \"clusterCount\": \"\", \"title\": \"\"}"
  done
  printf '%s' "$out"
}

echo "Case 1: sparse zoomed-in viewport stays on individual pins (PASS)."
run_case pass "sparse individual pins" 8 "$(frame_state 8 0 "[]" 6)"

echo "Case 2: dense viewport renders clusters only, members reconcile (PASS)."
run_case pass "dense cluster-only" 32 \
  "$(frame_state 0 6 "[5, 9, 7, 3, 4, 4]" 6)"

echo "Case 2b: dense viewport may keep singleton/selected pins next to clusters (PASS)."
run_case pass "dense mixed pins and clusters" 32 \
  "$(frame_state 1 5 "[7, 9, 7, 4, 4]" 6)"

echo "Case 2c: far zoom clusters a sparse list (PASS)."
run_case pass "far-zoom sparse clusters" 5 "$(frame_state 0 1 "[5]" 10)"

echo "Case 3: nothing rendered fails closed (FAIL)."
run_case fail "empty rendering" 32 "$(frame_state 0 0 "[]" 6)"

echo "Case 4: marker evidence tolerated in either document (drift) (PASS)."
run_case pass "top-document drift" 8 '{
  "frame": null,
  "topDocument": {
    "pins": 8,
    "clusters": 0,
    "clusterCounts": [],
    "sampleMarkers": [{"id": "fixture-top-0", "category": "restaurant", "clusterCount": "", "title": ""}],
    "stats": null,
    "mapLevel": "6",
    "containerPins": "8",
    "containerClusters": "0"
  }
}'
run_case pass "iframe DOM without bridge stats" 8 '{
  "frame": {
    "pins": 8,
    "clusters": 0,
    "clusterCounts": [],
    "sampleMarkers": [{"id": "fixture-frame-0", "category": "restaurant", "clusterCount": "", "title": ""}],
    "stats": null,
    "mapLevel": "6",
    "containerPins": "8",
    "containerClusters": "0"
  },
  "topDocument": {
    "pins": 0,
    "clusters": 0,
    "clusterCounts": [],
    "sampleMarkers": [],
    "stats": null,
    "mapLevel": null,
    "containerPins": null,
    "containerClusters": null
  }
}'

echo "Case 5: totals that do not reconcile fail closed (FAIL)."
run_case fail "cluster members under-cover the live count" 32 \
  "$(frame_state 0 6 "[5, 9, 7, 3, 4, 3]" 6)"
run_case fail "cluster members over-cover the live count" 32 \
  "$(frame_state 0 6 "[5, 9, 7, 3, 4, 5]" 6)"
run_case fail "sparse pins under-cover the live count" 8 "$(frame_state 7 0 "[]" 6)"

echo "Case 6: stale or malformed marker state fails closed (FAIL)."
run_case fail "bridge stats disagree with rendered DOM" 32 '{
  "frame": {
    "pins": 0,
    "clusters": 6,
    "clusterCounts": [5, 9, 7, 3, 4, 4],
    "sampleMarkers": [{"id": "fixture-c-0", "category": "restaurant", "clusterCount": "5", "title": ""}],
    "stats": {"provider": "naver", "pins": 0, "clusters": 5, "total": 5, "level": 6},
    "mapLevel": "6",
    "containerPins": "0",
    "containerClusters": "6"
  },
  "topDocument": {
    "pins": 0,
    "clusters": 0,
    "clusterCounts": [],
    "sampleMarkers": [],
    "stats": null,
    "mapLevel": null,
    "containerPins": null,
    "containerClusters": null
  }
}'
run_case fail "cluster DOM member counts do not cover every cluster" 32 \
  "$(frame_state 0 6 "[5, 9, 7, 3, 4]" 6)"
run_case fail "invalid cluster member count" 6 "$(frame_state 0 2 "[5, 1]" 6)"

echo "Case 7: sparse viewport that clustered early fails the pin-first rule (FAIL)."
run_case fail "sparse clustered before far zoom" 8 "$(frame_state 0 2 "[4, 4]" 6)"

echo "Case 8: duplicated rendering and missing bridge fail closed (FAIL)."
run_case fail "markers rendered in both documents" 32 '{
  "frame": {
    "pins": 0,
    "clusters": 6,
    "clusterCounts": [5, 9, 7, 3, 4, 4],
    "sampleMarkers": [{"id": "fixture-dup-0", "category": "restaurant", "clusterCount": "5", "title": ""}],
    "stats": {"provider": "naver", "pins": 0, "clusters": 6, "total": 6, "level": 6},
    "mapLevel": "6",
    "containerPins": "0",
    "containerClusters": "6"
  },
  "topDocument": {
    "pins": 8,
    "clusters": 0,
    "clusterCounts": [],
    "sampleMarkers": [{"id": "fixture-top-dup-0", "category": "restaurant", "clusterCount": "", "title": ""}],
    "stats": null,
    "mapLevel": null,
    "containerPins": null,
    "containerClusters": null
  }
}'
run_case fail "no map container or bridge" 32 '{"frame": null, "topDocument": null}'
run_case fail "zero live place count" 0 "$(frame_state 8 0 "[]" 6)"

echo "PASS: marker contract handles sparse, dense, drift, and reconciliation failures."
