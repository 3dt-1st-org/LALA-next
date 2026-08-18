"""Bounded live docent QA runner (Lane C, 30-50 real production places).

Loads the local QA manifest (IDs + safe metadata only, gitignored under
``output/local/``), calls the deployed public docent endpoint
``POST /api/v1/docents/script`` for each place x {ko,en}, applies the existing
deterministic precheck from :mod:`docent_quality_qa`, and records token/cost
counters reported by the API without any secrets.

Hard run caps live in ``RUN_CAPS`` and are enforced before any network call:
the runner aborts once ``max_places``, ``max_calls``, or ``max_estimated_cost_usd``
is reached. Paid calls go through the standard OpenAI lane behind the deployed
API (never Azure); this tool itself holds no provider key.

Targeted replay mode: repeatable ``--target place_id:language`` args select
exact manifest pairs for correction runs (e.g. 3 records after a manual
rubric). Targets are validated against the authoritative manifest before the
weather lookup or any POST, and every existing cap still applies. Without
``--target`` the default full-run behavior is unchanged.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[4]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from apps.api.app.services import docent_quality_qa  # noqa: E402

# Hard caps for this bounded QA run. The runner refuses to exceed them.
RUN_CAPS = {
    "max_places": 50,  # manifest rows (mission ceiling: 30-50)
    "max_calls": 100,  # places x languages ceiling
    "max_estimated_cost_usd": 5.0,  # conservative stop-loss from API-reported tokens
}

# Rough standard-OpenAI price ceiling per 1M tokens for the docent model lane.
# Used only as a stop-loss guard; the report records raw token counts.
_EST_COST_PER_1M_USD = 2.00

_PM_RE = re.compile(r"PM10|PM2\.5|미세먼지|초미세먼지")

# Languages the docent script endpoint produces; targets outside this set are
# rejected at parse time.
_SUPPORTED_LANGUAGES = ("ko", "en")


def _http_post_json(url: str, payload: dict[str, Any], timeout: float) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    # The edge blocks the bare python-urllib UA; a browser-style UA matches how the
    # deployed web smoke already calls these public endpoints.
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "lala-docent-qa/1.0"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _http_get_json(url: str, timeout: float) -> dict[str, Any]:
    req = urllib.request.Request(
        url, headers={"Accept": "application/json", "User-Agent": "lala-docent-qa/1.0"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def parse_target(raw: str) -> tuple[str, str]:
    """Parse a ``place_id:language`` target; raise ValueError when malformed."""
    place_id, sep, language = raw.partition(":")
    if not sep or not place_id or ":" in language:
        raise ValueError(f"target must be 'place_id:language', got {raw!r}")
    if language not in _SUPPORTED_LANGUAGES:
        raise ValueError(
            f"unsupported language {language!r}; expected one of {_SUPPORTED_LANGUAGES}"
        )
    return place_id, language


def validate_manifest(manifest: list[dict[str, Any]]) -> None:
    """Enforce the authoritative-manifest shape before any network call."""
    if not isinstance(manifest, list) or not 30 <= len(manifest) <= RUN_CAPS["max_places"]:
        count = len(manifest) if isinstance(manifest, list) else -1
        raise ValueError(f"manifest must hold 30-{RUN_CAPS['max_places']} places; has {count}")


def select_target_pairs(
    manifest: list[dict[str, Any]], targets: list[tuple[str, str]]
) -> list[tuple[dict[str, Any], str]]:
    """Resolve exact ``(place, language)`` pairs against the manifest.

    Fails (ValueError) on duplicate, unknown-place, or unsupported-language
    targets so a bad run dies before the weather lookup or any POST. Output
    order follows manifest order, then the place's language order — never the
    CLI order — so repeated runs are byte-stable.
    """
    seen: set[tuple[str, str]] = set()
    for pair in targets:
        if pair in seen:
            raise ValueError(f"duplicate target {pair[0]}:{pair[1]}")
        seen.add(pair)
    by_id: dict[str, dict[str, Any]] = {}
    for place in manifest:
        place_id = place.get("place_id")
        if not place_id:
            raise ValueError("manifest row is missing place_id")
        if place_id in by_id:
            raise ValueError(f"manifest holds duplicate place_id {place_id}")
        by_id[place_id] = place
    wanted_ids = {place_id for place_id, _ in targets}
    for place_id in sorted(wanted_ids):
        if place_id not in by_id:
            raise ValueError(f"target place {place_id} not found in manifest")
    pairs: list[tuple[dict[str, Any], str]] = []
    for place in manifest:
        if place.get("place_id") not in wanted_ids:
            continue
        languages = place.get("language_samples") or ["ko"]
        for language in languages:
            if (place["place_id"], language) in seen:
                pairs.append((place, language))
    resolved = {(place["place_id"], language) for place, language in pairs}
    for place_id, language in sorted(seen):
        if (place_id, language) not in resolved:
            raise ValueError(f"target {place_id}:{language} is not in the place's language_samples")
    return pairs


def build_request_body(
    place: dict[str, Any], language: str, weather: dict[str, Any]
) -> dict[str, Any]:
    features = place.get("sample_features") or {}
    dust = weather.get("dust") or {}
    body: dict[str, Any] = {
        "place_id": place["place_id"],
        "place_name": place.get(f"place_name_{language}") or place.get("place_name_ko"),
        "category": place["category"],
        "language": language,
        "mode": "brief",
        "source": "db",
        "upstream_source": place.get("primary_source"),
    }
    if place.get("region_ko"):
        body["region_ko"] = place["region_ko"]
    if place.get("address_ko") and language == "ko":
        body["address"] = place["address_ko"]
    score = features.get("final_score")
    if score is not None:
        body["final_score"] = score
    if features.get("local_spending_score") is not None:
        body["local_spending_score"] = features["local_spending_score"]
    if weather.get("temp"):
        body["weather_temp"] = str(weather["temp"])
    if weather.get("icon"):
        body["weather_icon"] = str(weather["icon"])
    if weather.get("outdoor_status"):
        body["weather_outdoor_status"] = str(weather["outdoor_status"])
    if dust.get("pm10"):
        body["dust_pm10"] = str(dust["pm10"])
    if dust.get("pm25"):
        body["dust_pm25"] = str(dust["pm25"])
    if dust.get("pm10_grade_ko"):
        body["dust_pm10_grade"] = str(dust["pm10_grade_ko"])
    if dust.get("pm25_grade_ko"):
        body["dust_pm25_grade"] = str(dust["pm25_grade_ko"])
    return body


def _extract_usage(envelope: dict[str, Any]) -> dict[str, int]:
    """Pull the API-reported token counters, if the deployment exposes them."""
    data = envelope.get("data") or {}
    meta = envelope.get("meta") or {}
    usage = data.get("usage") or meta.get("usage") or envelope.get("usage") or {}
    return {
        "prompt_tokens": int(usage.get("prompt_tokens") or 0),
        "completion_tokens": int(usage.get("completion_tokens") or 0),
        "total_tokens": int(usage.get("total_tokens") or 0),
    }


def run(
    *,
    manifest_path: Path,
    base_url: str,
    output_dir: Path,
    limit: int,
    request_delay_sec: float,
    weather: dict[str, Any],
    targets: list[tuple[str, str]] | None = None,
) -> int:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    try:
        validate_manifest(manifest)
        selected = select_target_pairs(manifest, targets) if targets is not None else None
    except ValueError as exc:
        print(str(exc))
        return 2
    if selected is not None:
        # Targeted replay: --limit is a full-run concept and is deliberately ignored.
        places = []
        for place, _language in selected:
            if place not in places:
                places.append(place)
        pairs = selected
    else:
        places = manifest[:limit]
        pairs = [
            (place, language)
            for place in places
            for language in place.get("language_samples") or ["ko"]
        ]
    planned_calls = len(pairs)
    if planned_calls > RUN_CAPS["max_calls"]:
        print(f"planned {planned_calls} calls exceeds cap {RUN_CAPS['max_calls']}")
        return 2
    selection: dict[str, Any] | None = None
    if targets is not None:
        # Planned-call statement only: IDs stay in the report, nothing secret here.
        selection = {
            "mode": "targeted",
            "targets": [f"{place_id}:{language}" for place_id, language in sorted(targets)],
        }
        print(
            f"targeted mode: {planned_calls} planned call(s) across {len(places)} place(s) "
            f"(caps: max_calls={RUN_CAPS['max_calls']}, "
            f"max_estimated_cost_usd={RUN_CAPS['max_estimated_cost_usd']})"
        )

    endpoint = base_url.rstrip("/") + "/api/v1/docents/script"
    records: list[dict[str, Any]] = []
    counters = {"calls": 0, "ok": 0, "service_errors": 0, "transport_errors": 0}
    tokens = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}

    for place, language in pairs:
        if counters["calls"] >= RUN_CAPS["max_calls"]:
            break
        body = build_request_body(place, language, weather)
        record: dict[str, Any] = {
            "place_id": place["place_id"],
            "place_name": place.get("place_name_ko"),
            "category": place["category"],
            "region": place.get("region_ko"),
            "language": language,
            "mode": "brief",
            "expectation": place.get("expectation", "nonempty"),
        }
        counters["calls"] += 1
        try:
            envelope = _http_post_json(endpoint, body, timeout=40.0)
        except urllib.error.HTTPError as exc:
            try:
                detail = json.loads(exc.read().decode("utf-8"))
            except Exception:
                detail = {}
            record["http_status"] = exc.code
            record["error_code"] = detail.get("error", {}).get("code") or f"HTTP{exc.code}"
            counters["service_errors" if exc.code >= 400 else "ok"] += 1
            records.append(record)
            time.sleep(request_delay_sec)
            continue
        except Exception as exc:  # transport failure: record honestly, never fabricate
            record["http_status"] = None
            record["error_code"] = exc.__class__.__name__
            counters["transport_errors"] += 1
            records.append(record)
            time.sleep(request_delay_sec)
            continue
        counters["ok"] += 1
        data = envelope.get("data") or {}
        usage = _extract_usage(envelope)
        for key in tokens:
            tokens[key] += usage[key]
        estimated = tokens["total_tokens"] / 1_000_000 * _EST_COST_PER_1M_USD
        if estimated >= RUN_CAPS["max_estimated_cost_usd"]:
            print(f"stop-loss: estimated ${estimated:.4f} reached cap; halting")
            records.append({**record, "halted": True, "reason": "cost_stop_loss"})
            return _write_report(
                output_dir,
                manifest_path,
                base_url,
                places,
                records,
                counters,
                tokens,
                selection=selection,
            )

        script = str(data.get("script") or "")
        candidate = docent_quality_qa.DocentQaCandidate(
            place_id=place["place_id"],
            name_ko=place.get("place_name_ko") or "",
            category=place["category"],
            region_name_ko=place.get("region_ko"),
            primary_source=place.get("primary_source"),
            final_score=(place.get("sample_features") or {}).get("final_score"),
            rag_chunk_count=int(data.get("grounding_count") or 0),
            review_mention_count=(place.get("sample_features") or {}).get("mention_count"),
            review_organic_mention_count=(place.get("sample_features") or {}).get(
                "organic_mention_count"
            ),
            weather_pm10=_to_float((weather.get("dust") or {}).get("pm10")),
            weather_pm25=_to_float((weather.get("dust") or {}).get("pm25")),
            weather_temperature_c=_to_float(weather.get("temp")),
            script=script,
            script_source_method=str(data.get("source") or ""),
            script_generated_at=str(data.get("generated_at") or ""),
        )
        precheck = docent_quality_qa.evaluate_docent_script(candidate, language=language)
        record.update(
            {
                "http_status": 200,
                "source": data.get("source"),
                "grounding_count": data.get("grounding_count"),
                "grounding_sources": data.get("grounding_sources"),
                "retrieval_mode": (data.get("retrieval") or {}).get("mode"),
                "script_chars": len(script),
                "script": script,
                "auto_precheck": precheck.to_public_dict(),
                "usage": usage,
            }
        )
        records.append(record)
        time.sleep(request_delay_sec)

    return _write_report(
        output_dir,
        manifest_path,
        base_url,
        places,
        records,
        counters,
        tokens,
        selection=selection,
    )


def _write_report(
    output_dir: Path,
    manifest_path: Path,
    base_url: str,
    places: list[dict[str, Any]],
    records: list[dict[str, Any]],
    counters: dict[str, int],
    tokens: dict[str, int],
    selection: dict[str, Any] | None = None,
) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    estimated_cost = round(tokens["total_tokens"] / 1_000_000 * _EST_COST_PER_1M_USD, 6)
    report = {
        "generated_at": stamp,
        "base_url": base_url,
        "manifest": str(manifest_path),
        "run_caps": RUN_CAPS,
        "counters": counters,
        "token_counters": tokens,
        "estimated_cost_usd": estimated_cost,
        "est_cost_assumption": f"${_EST_COST_PER_1M_USD}/1M total tokens (stop-loss only)",
        "place_count": len(places),
        "records": records,
    }
    if selection is not None:
        report["selection"] = selection
    path = output_dir / f"live-docent-qa-{stamp}.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print(
        f"records={len(records)} ok={counters['ok']} "
        f"service_errors={counters['service_errors']} transport_errors={counters['transport_errors']} "
        f"tokens={tokens['total_tokens']} est=${estimated_cost} report={path}"
    )
    return 0


def _to_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the bounded live docent QA sample.")
    parser.add_argument(
        "--manifest",
        default=str(
            _REPO_ROOT / "output" / "local" / "docent-qa-lane-c" / "qa_manifest_40places.json"
        ),
    )
    parser.add_argument("--base-url", default="https://api.lala-next.cloud")
    parser.add_argument(
        "--output-dir", default=str(_REPO_ROOT / "output" / "local" / "docent-qa-lane-c")
    )
    parser.add_argument("--limit", type=int, default=RUN_CAPS["max_places"])
    parser.add_argument("--request-delay-sec", type=float, default=1.2)
    parser.add_argument(
        "--target",
        action="append",
        default=None,
        metavar="PLACE_ID:LANGUAGE",
        help=(
            "exact manifest pair to replay (repeatable, e.g. tour-api-123:ko); "
            "validated against the manifest before any network call; "
            "ignores --limit and keeps every run cap"
        ),
    )
    args = parser.parse_args(argv)

    targets: list[tuple[str, str]] | None = None
    if args.target:
        targets = []
        try:
            for raw in args.target:
                targets.append(parse_target(raw))
        except ValueError as exc:
            print(str(exc))
            return 2
        # Fail-before-network: full manifest + target validation happens before
        # the weather lookup, so bad arguments cost nothing.
        try:
            manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
            validate_manifest(manifest)
            selected = select_target_pairs(manifest, targets)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            print(f"target validation failed: {exc}")
            return 2
        if len(selected) > RUN_CAPS["max_calls"]:
            print(f"planned {len(selected)} calls exceeds cap {RUN_CAPS['max_calls']}")
            return 2

    weather_url = args.base_url.rstrip("/") + "/api/v1/weather?lat=37.5665&lng=126.9780"
    try:
        weather = _http_get_json(weather_url, timeout=20.0).get("data") or {}
    except Exception as exc:
        print(f"weather lookup failed: {exc}")
        return 2
    return run(
        manifest_path=Path(args.manifest),
        base_url=args.base_url,
        output_dir=Path(args.output_dir),
        limit=args.limit,
        request_delay_sec=args.request_delay_sec,
        weather=weather,
        targets=targets,
    )


if __name__ == "__main__":
    raise SystemExit(main())
