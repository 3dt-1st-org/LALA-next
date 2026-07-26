from __future__ import annotations

import argparse
import contextlib
import json
import os
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.job_runs import duration_ms, record_job_run
from apps.api.app.services.rag_index import (
    DYNAMIC_SOURCE_TYPES,
    STATIC_SOURCE_TYPES,
    assert_semantic_embedding_when_live,
    fetch_candidate_chunks,
    query_knowledge_chunks,
    reindex_stale_chunks,
    resolve_serving_embedding_method,
    select_stale_chunks,
    upsert_knowledge_chunks,
)

CONFIRM_TEXT = "APPLY_RAG_INDEX"
ALLOW_ENV = "ALLOW_RAG_INDEX_APPLY"
JOB_NAME = "rag-index"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, apply, or query the LALA RAG knowledge index."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview", action="store_true", help="Read source rows and preview chunks."
    )
    parser.add_argument("--apply", action="store_true", help="Upsert rag.knowledge_chunks rows.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--query", default="", help="Run a read-only vector search query.")
    parser.add_argument(
        "--source",
        choices=["all", "static", "dynamic"],
        default="all",
        help="static=preloaded place profiles, dynamic=events/community/weather.",
    )
    parser.add_argument(
        "--embedding-method",
        choices=["local-hash", "openai"],
        default="local-hash",
    )
    parser.add_argument("--place-id", default="", help="Optional query filter for a place_id.")
    parser.add_argument("--limit", type=int, default=500, help="Chunk candidate limit.")
    parser.add_argument("--top-k", type=int, default=5, help="Vector search result count.")
    parser.add_argument(
        "--reindex",
        action="store_true",
        help="Plan, preview, or apply stale-chunk re-embedding (embedding_generation lifecycle).",
    )
    parser.add_argument(
        "--embedding-generation",
        type=int,
        default=None,
        help="Serving embedding generation for --reindex (default: rag_embedding_generation).",
    )
    parser.add_argument(
        "--chunk-cap",
        type=int,
        default=None,
        help="Max chunks re-embedded per --reindex apply run (default: rag_reindex_chunk_cap).",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=None,
        help="Commit batch size for --reindex apply (default: rag_reindex_batch_size).",
    )
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.top_k <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--top-k must be positive."})
        return 2
    if args.reindex:
        return _run_reindex(args)
    selected_modes = sum(bool(value) for value in (args.preview, args.apply, args.query.strip()))
    if selected_modes > 1:
        _write(
            args,
            {
                "ok": False,
                "mode": "plan",
                "error": "Use only one of --preview, --apply, or --query.",
            },
        )
        return 2

    if not args.apply and not args.preview and not args.query.strip():
        _write(args, _plan_payload(args))
        return 0

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    started_at = datetime.now(UTC)
    try:
        if args.query.strip():
            results = query_knowledge_chunks(
                dsn=dsn,
                query=args.query,
                source=args.source,
                top_k=args.top_k,
                embedding_method=args.embedding_method,
                connect_timeout=args.connect_timeout,
                place_id=args.place_id.strip() or None,
            )
            _write(
                args,
                {
                    "ok": True,
                    "mode": "query",
                    "db_mutation": False,
                    "target": "rag.knowledge_chunks",
                    "source": args.source,
                    "embedding_method": args.embedding_method,
                    "result_count": len(results),
                    "results": [item.to_public_dict() for item in results],
                },
            )
            return 0

        chunks = fetch_candidate_chunks(
            dsn=dsn,
            source=args.source,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        upserted_rows = 0
        if args.apply:
            upserted_rows = upsert_knowledge_chunks(
                dsn=dsn,
                chunks=chunks,
                embedding_method=args.embedding_method,
                connect_timeout=args.connect_timeout,
            )
            finished_at = datetime.now(UTC)
            record_job_run(
                dsn=dsn,
                job_name=JOB_NAME,
                status="succeeded",
                started_at=started_at,
                finished_at=finished_at,
                duration_ms=duration_ms(started_at, finished_at),
                error_message=None,
                connect_timeout=args.connect_timeout,
            )
    except Exception as exc:
        if args.apply:
            finished_at = datetime.now(UTC)
            with contextlib.suppress(Exception):
                record_job_run(
                    dsn=dsn,
                    job_name=JOB_NAME,
                    status="failed",
                    started_at=started_at,
                    finished_at=finished_at,
                    duration_ms=duration_ms(started_at, finished_at),
                    error_message=redact_secret_text(
                        str(exc) or exc.__class__.__name__,
                        (dsn, settings.openai_api_key),
                    ),
                    connect_timeout=args.connect_timeout,
                )
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": redact_secret_text(
                    str(exc) or exc.__class__.__name__,
                    (dsn, settings.openai_api_key),
                ),
            },
        )
        return 2

    _write(
        args,
        {
            "ok": True,
            "mode": _mode(args),
            "db_mutation": bool(args.apply),
            "target": "rag.knowledge_chunks",
            "job_name": JOB_NAME,
            "source": args.source,
            "embedding_method": args.embedding_method,
            "candidate_count": len(chunks),
            "upserted_rows": upserted_rows,
            "preview": [item.to_public_dict() for item in chunks[:5]],
        },
    )
    return 0


def _run_reindex(args: argparse.Namespace) -> int:
    """--reindex: plan (no DB), preview (read-only stale SELECT), or apply (re-embed + stamp
    embedding_generation). Apply reuses the same confirm + env gate as chunk upsert."""
    if args.query.strip():
        _write(
            args,
            {"ok": False, "mode": "reindex", "error": "--query is not valid with --reindex."},
        )
        return 2
    selected = sum(bool(value) for value in (args.preview, args.apply))
    if selected > 1:
        _write(
            args,
            {
                "ok": False,
                "mode": "reindex",
                "error": "Use only one of --preview or --apply with --reindex.",
            },
        )
        return 2

    settings = get_settings()
    serving_generation = (
        args.embedding_generation
        if args.embedding_generation is not None
        else settings.rag_embedding_generation
    )
    chunk_cap = args.chunk_cap if args.chunk_cap is not None else settings.rag_reindex_chunk_cap
    batch_size = args.batch_size if args.batch_size is not None else settings.rag_reindex_batch_size
    if serving_generation < 0:
        _write(
            args,
            {
                "ok": False,
                "mode": "reindex",
                "error": "--embedding-generation must be non-negative.",
            },
        )
        return 2
    if chunk_cap <= 0 or batch_size <= 0:
        _write(
            args,
            {
                "ok": False,
                "mode": "reindex",
                "error": "--chunk-cap and --batch-size must be positive.",
            },
        )
        return 2

    if not args.preview and not args.apply:
        _write(args, _reindex_plan_payload(args, serving_generation, chunk_cap, batch_size))
        return 0

    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "reindex-apply", "error": guard_error})
            return 2

    started_at = datetime.now(UTC)
    try:
        if args.preview:
            stale = select_stale_chunks(
                dsn=dsn,
                serving_generation=serving_generation,
                limit=chunk_cap,
                connect_timeout=args.connect_timeout,
            )
            _write(
                args,
                {
                    "ok": True,
                    "mode": "reindex-preview",
                    "db_mutation": False,
                    "target": "rag.knowledge_chunks",
                    "job_name": JOB_NAME,
                    "embedding_method": args.embedding_method,
                    "serving_generation": serving_generation,
                    "stale_count": len(stale),
                    "preview": [
                        {
                            "source_type": chunk.source_type,
                            "source_id": chunk.source_id,
                            "reason": chunk.reason,
                            "stored_generation": chunk.stored_generation,
                        }
                        for chunk in stale[:5]
                    ],
                },
            )
            return 0

        result = reindex_stale_chunks(
            dsn=dsn,
            serving_generation=serving_generation,
            embedding_method=args.embedding_method,
            batch_size=batch_size,
            chunk_cap=chunk_cap,
            connect_timeout=args.connect_timeout,
        )
        finished_at = datetime.now(UTC)
        record_job_run(
            dsn=dsn,
            job_name=JOB_NAME,
            status="succeeded",
            started_at=started_at,
            finished_at=finished_at,
            duration_ms=duration_ms(started_at, finished_at),
            error_message=None,
            connect_timeout=args.connect_timeout,
        )
        _write(
            args,
            {
                "ok": True,
                "mode": "reindex-apply",
                "db_mutation": True,
                "target": "rag.knowledge_chunks",
                "job_name": JOB_NAME,
                "embedding_method": args.embedding_method,
                "serving_generation": serving_generation,
                **result.to_dict(),
            },
        )
        return 0
    except Exception as exc:
        if args.apply:
            finished_at = datetime.now(UTC)
            with contextlib.suppress(Exception):
                record_job_run(
                    dsn=dsn,
                    job_name=JOB_NAME,
                    status="failed",
                    started_at=started_at,
                    finished_at=finished_at,
                    duration_ms=duration_ms(started_at, finished_at),
                    error_message=redact_secret_text(
                        str(exc) or exc.__class__.__name__,
                        (dsn, settings.openai_api_key),
                    ),
                    connect_timeout=args.connect_timeout,
                )
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": redact_secret_text(
                    str(exc) or exc.__class__.__name__,
                    (dsn, settings.openai_api_key),
                ),
            },
        )
        return 2


def _reindex_plan_payload(
    args: argparse.Namespace,
    serving_generation: int,
    chunk_cap: int,
    batch_size: int,
) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "reindex-plan",
        "db_mutation": False,
        "target": "rag.knowledge_chunks",
        "job_name": JOB_NAME,
        "embedding_method": args.embedding_method,
        "serving_generation": serving_generation,
        "chunk_cap": chunk_cap,
        "batch_size": batch_size,
        "stale_predicate": "embedding_generation < serving_generation OR embedding IS NULL",
        "requires": "sql/operator-pending/064_rag_knowledge_retrieval_metadata.sql (separately approved and applied)",
        "note": (
            "preview/apply require DB_DSN; apply requires --confirm APPLY_RAG_INDEX "
            "and ALLOW_RAG_INDEX_APPLY=1."
        ),
    }


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "target": "rag.knowledge_chunks",
        "job_name": JOB_NAME,
        "source": args.source,
        "embedding_method": args.embedding_method,
        "static_source_types": STATIC_SOURCE_TYPES,
        "dynamic_source_types": DYNAMIC_SOURCE_TYPES,
        "input_relations": [
            "travel.places",
            "analytics.place_score_snapshots",
            "culture.events",
            "community.posts",
            "community.place_mentions_weekly",
            "travel.weather_observations",
        ],
        "retrieval": "pgvector cosine search",
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    # No silent semantic fallback: shared by --apply and --reindex --apply, evaluated before
    # any DB connection is opened (R1). resolve_serving_embedding_method's Literal validation
    # runs unconditionally too (R10) — an unsupported rag_embedding_method must not escape as
    # an unhandled traceback; it returns the same {"ok": false, "error": ...} + exit 2 contract
    # as any other guard violation.
    try:
        resolve_serving_embedding_method()
        assert_semantic_embedding_when_live()
    except (RuntimeError, ValueError) as exc:
        return str(exc)
    return ""


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next RAG knowledge index")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'rag.knowledge_chunks')}")
    print(f"source={payload.get('source', args.source)}")
    print(f"embedding_method={payload.get('embedding_method', args.embedding_method)}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for key in ("candidate_count", "upserted_rows", "result_count"):
        if key in payload:
            print(f"{key}={payload[key]}")
    for relation in payload.get("input_relations") or []:
        print(f"input_relation={relation}")
    for source_type in payload.get("static_source_types") or []:
        print(f"static_source_type={source_type}")
    for source_type in payload.get("dynamic_source_types") or []:
        print(f"dynamic_source_type={source_type}")
    for item in payload.get("preview") or []:
        print(
            "preview="
            + json.dumps(
                {
                    "source_type": item.get("source_type"),
                    "source_id": item.get("source_id"),
                    "place_id": item.get("place_id"),
                    "title_ko": item.get("title_ko"),
                    "content_sha256": item.get("content_sha256"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
    for item in payload.get("results") or []:
        print(
            "result="
            + json.dumps(
                {
                    "source_type": item.get("source_type"),
                    "source_id": item.get("source_id"),
                    "place_id": item.get("place_id"),
                    "title_ko": item.get("title_ko"),
                    "similarity": item.get("similarity"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    if args.reindex:
        if args.apply:
            return "reindex-apply"
        if args.preview:
            return "reindex-preview"
        return "reindex-plan"
    if args.apply:
        return "apply"
    if args.preview:
        return "preview"
    if args.query.strip():
        return "query"
    return "plan"


if __name__ == "__main__":
    raise SystemExit(main())
