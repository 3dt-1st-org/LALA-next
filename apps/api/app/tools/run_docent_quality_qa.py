from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.docent_quality_qa import (
    build_docent_qa_records,
    fetch_docent_qa_candidates,
    select_representative_candidates,
    summarize_qa_records,
    write_local_qa_artifacts,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or write local docent quality QA seed records."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Read DB and preview QA sample.")
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write sanitized local QA seed artifacts under output/local.",
    )
    parser.add_argument(
        "--category",
        choices=["all", "attraction", "restaurant", "event", "culture_venue"],
        default="all",
    )
    parser.add_argument("--language", choices=["ko", "en"], default="ko")
    parser.add_argument("--mode", choices=["brief", "detail"], default="brief")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("--connect-timeout", type=int, default=5)
    parser.add_argument(
        "--output-dir",
        default="output/local/docent-qa",
        help="Local-only output directory used with --write.",
    )
    parser.add_argument("--label", default="docent-quality-qa")
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.preview and args.write:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --preview or --write."})
        return 2
    if not args.preview and not args.write:
        _write(args, _plan_payload(args))
        return 0

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    try:
        candidates = fetch_docent_qa_candidates(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            language=args.language,
            mode=args.mode,
            connect_timeout=args.connect_timeout,
        )
        sample = select_representative_candidates(candidates, limit=args.limit)
        records = build_docent_qa_records(
            sample,
            language=args.language,
            mode=args.mode,
        )
        summary = summarize_qa_records(records)
        written_paths: dict[str, str] = {}
        if args.write:
            written_paths = write_local_qa_artifacts(
                records=records,
                output_dir=Path(args.output_dir),
                label=args.label,
            )
    except Exception as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
            },
        )
        return 2

    _write(
        args,
        {
            "ok": True,
            "mode": _mode(args),
            "db_mutation": False,
            "file_write": bool(args.write),
            "target": "output/local/docent-qa",
            "input_relations": _input_relations(),
            "candidate_count": len(candidates),
            "sample_count": len(sample),
            "summary": summary,
            "written_paths": written_paths,
            "preview": records[:5],
        },
    )
    return 0


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "file_write": False,
        "target": "output/local/docent-qa",
        "category": args.category,
        "language": args.language,
        "mode_to_review": args.mode,
        "sample_size": args.limit,
        "input_relations": _input_relations(),
        "rubric_points": {
            "factual_grounding": 20,
            "category_persona": 15,
            "local_value": 15,
            "weather_pm_context": 10,
            "route_usefulness": 10,
            "review_mention_quality": 10,
            "language_purity": 8,
            "tone_listenability": 7,
            "safety_presentation": 5,
        },
        "manual_thresholds": {
            "sample_size": "30-50",
            "blocker_count": 0,
            "average_score_min": 90,
            "category_average_min": 85,
        },
    }


def _input_relations() -> list[str]:
    return [
        "travel.places",
        "travel.docent_scripts",
        "travel.weather_observations",
        "analytics.place_score_snapshots",
        "community.place_mentions_weekly",
        "rag.knowledge_chunks",
    ]


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next docent quality QA")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'output/local/docent-qa')}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if "file_write" in payload:
        print(f"file_write={str(payload.get('file_write')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for relation in payload.get("input_relations") or []:
        print(f"input_relation={relation}")
    for key in ("candidate_count", "sample_count"):
        if key in payload:
            print(f"{key}={payload[key]}")
    summary = payload.get("summary") or {}
    for key in (
        "record_count",
        "scored_count",
        "pending_generation_count",
        "blocker_count",
        "average_auto_precheck_score",
    ):
        if key in summary:
            print(f"{key}={summary[key]}")
    for path_key, path_value in (payload.get("written_paths") or {}).items():
        print(f"{path_key}={path_value}")


def _mode(args: argparse.Namespace) -> str:
    return "write" if args.write else "preview" if args.preview else "plan"


if __name__ == "__main__":
    raise SystemExit(main())
