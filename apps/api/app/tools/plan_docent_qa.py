from __future__ import annotations

import argparse
import json
import os
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.docent_qa import (
    DEFAULT_QA_LIMIT,
    MAX_QA_LIMIT,
    MIN_QA_LIMIT,
    RUBRIC_AREAS,
    SUPPORTED_CATEGORIES,
    build_docent_qa_plan,
    fetch_docent_qa_candidates,
)

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan or preview the representative docent manual QA set."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Read DB/RAG signals and select candidates.")
    parser.add_argument(
        "--category",
        choices=sorted(SUPPORTED_CATEGORIES),
        default="all",
    )
    parser.add_argument("--limit", type=int, default=DEFAULT_QA_LIMIT)
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.limit < MIN_QA_LIMIT or args.limit > MAX_QA_LIMIT:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": f"--limit must be between {MIN_QA_LIMIT} and {MAX_QA_LIMIT}.",
            },
        )
        return 2

    if not args.preview:
        _write(args, _plan_payload(args))
        return 0

    dsn = _env_or_secret("DB_DSN", "db-dsn")
    if not dsn:
        _write(args, {"ok": False, "mode": "preview", "error": "DB_DSN is not configured."})
        return 2

    try:
        candidates = fetch_docent_qa_candidates(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        plan = build_docent_qa_plan(candidates)
    except Exception as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": "preview",
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
            },
        )
        return 2

    payload = {
        "ok": True,
        "mode": "preview",
        "db_mutation": False,
        "source": [
            "travel.places",
            "analytics.place_score_snapshots",
            "rag.knowledge_chunks",
            "travel.weather_observations",
        ],
        "target": "manual_docent_qa_record",
        **plan.to_public_dict(),
    }
    _write(args, payload)
    return 0


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "source": [
            "travel.places",
            "analytics.place_score_snapshots",
            "rag.knowledge_chunks",
            "travel.weather_observations",
        ],
        "target": "manual_docent_qa_record",
        "category": args.category,
        "limit": args.limit,
        "required_env": ["DB_DSN"],
        "rubric": RUBRIC_AREAS,
        "notes": [
            "No scripts are generated in plan mode.",
            "Preview selects DB-backed candidates and prints sanitized QA metadata.",
            "Reviewer names stay blank in committed docs.",
        ],
    }


def _env_or_secret(env_name: str, secret_name: str) -> str:
    value = (os.getenv(env_name) or "").strip()
    if value:
        return value
    return get_secret_if_configured((os.getenv("KEY_VAULT_URL") or "").strip(), secret_name)


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next docent manual QA plan")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target')}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    print(f"candidate_count={payload.get('candidate_count', 0)}")
    coverage = payload.get("coverage") or {}
    for key in ("category_counts", "region_counts", "tag_counts"):
        if key in coverage:
            print(f"{key}=" + json.dumps(coverage[key], ensure_ascii=False, sort_keys=True))
    for item in (payload.get("candidates") or [])[:10]:
        print(
            "candidate="
            + json.dumps(
                {
                    "place_id": item.get("place_id"),
                    "name_ko": item.get("name_ko"),
                    "category": item.get("category"),
                    "region_name_ko": item.get("region_name_ko"),
                    "coverage_tags": item.get("coverage_tags"),
                    "qa_modes": item.get("qa_modes"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    return "preview" if args.preview else "plan"


if __name__ == "__main__":
    raise SystemExit(main())
