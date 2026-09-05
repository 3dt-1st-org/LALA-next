"""Sanitize a Lane C live docent QA run report for safe local storage.

Strips anything that could carry private/raw review content or secrets, keeps
short evidence excerpts, and aggregates per-dimension verdicts from the
deterministic audits in :mod:`docent_qa_dimensions` plus the manual review
notes file. Every dimension reports pass / flagged / not-applicable counts;
dimensions without enough evidence are counted as not-applicable, never as a
silent pass.

Input:  output/local/docent-qa-lane-c/live-docent-qa-*.json (gitignored run report)
Output: output/local/docent-qa-lane-c/sanitized-report.md (safe summary + evidence)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[4]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from apps.api.app.services import docent_qa_dimensions  # noqa: E402

_SECRET_RE = re.compile(
    r"(sk-[A-Za-z0-9]{8,}|Bearer\s+[A-Za-z0-9._-]{8,}|postgres(?:ql)?://[^\s\"']+|"
    r"Key Vault|vault\.azure\.net)",
    re.IGNORECASE,
)


def sanitize_text(value: str, limit: int = 700) -> str:
    cleaned = _SECRET_RE.sub("[redacted]", " ".join((value or "").split()))
    return cleaned[: limit - 3] + "..." if len(cleaned) > limit else cleaned


def build_sanitized_report(report: dict[str, Any], manual_notes: dict[str, Any]) -> dict[str, Any]:
    records = report.get("records") or []
    issue_counts: dict[str, int] = {}
    category_scores: dict[str, list[int]] = {}
    language_scores: dict[str, list[int]] = {}
    out_records: list[dict[str, Any]] = []

    for record in records:
        precheck = record.get("auto_precheck") or {}
        for tag in precheck.get("issue_tags") or []:
            issue_counts[tag] = issue_counts.get(tag, 0) + 1
        score = precheck.get("auto_precheck_score")
        if score is not None:
            category_scores.setdefault(record["category"], []).append(int(score))
            language_scores.setdefault(record["language"], []).append(int(score))
        dimension_audits = docent_qa_dimensions.audit_record_dimensions(record)
        manual = (manual_notes.get("places") or {}).get(record["place_id"]) or {}
        out_records.append(
            {
                "place_id": record["place_id"],
                "place_name": record.get("place_name"),
                "category": record["category"],
                "region": record.get("region"),
                "language": record["language"],
                "expectation": record.get("expectation"),
                "http_status": record.get("http_status"),
                "error_code": record.get("error_code"),
                "source": record.get("source"),
                "grounding_count": record.get("grounding_count"),
                "script_chars": record.get("script_chars"),
                "auto_precheck_score": score,
                "blocker": precheck.get("blocker"),
                "issue_tags": precheck.get("issue_tags"),
                "dimension_verdicts": {
                    dimension: audit.to_public_dict()
                    for dimension, audit in dimension_audits.items()
                },
                "manual_scores": manual.get("scores"),
                "manual_verdict": manual.get("verdict"),
                "manual_notes": sanitize_text(str(manual.get("notes") or ""), 300),
                "script_excerpt": sanitize_text(str(record.get("script") or ""), 240),
            }
        )

    def avg(values: list[int]) -> float | None:
        return round(sum(values) / len(values), 2) if values else None

    return {
        "generated_at": report.get("generated_at"),
        "base_url": report.get("base_url"),
        "run_caps": report.get("run_caps"),
        "counters": report.get("counters"),
        "token_counters": report.get("token_counters"),
        "estimated_cost_usd": report.get("estimated_cost_usd"),
        "place_count": report.get("place_count"),
        "summary": {
            "record_count": len(records),
            "average_auto_precheck_score": avg(
                [
                    int(r["auto_precheck"]["auto_precheck_score"])
                    for r in records
                    if (r.get("auto_precheck") or {}).get("auto_precheck_score") is not None
                ]
            ),
            "category_average": {k: avg(v) for k, v in sorted(category_scores.items())},
            "language_average": {k: avg(v) for k, v in sorted(language_scores.items())},
            "issue_counts": dict(sorted(issue_counts.items())),
            "dimension_flags": docent_qa_dimensions.summarize_dimension_audits(records),
        },
        "records": out_records,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", help="Path to the raw live QA run report JSON.")
    parser.add_argument(
        "--manual-notes",
        default=str(
            _REPO_ROOT / "output" / "local" / "docent-qa-lane-c" / "manual_review_notes.json"
        ),
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output markdown path (default: sanitized-report.md next to the report).",
    )
    args = parser.parse_args(argv)

    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    notes_path = Path(args.manual_notes)
    manual_notes = json.loads(notes_path.read_text(encoding="utf-8")) if notes_path.exists() else {}

    sanitized = build_sanitized_report(report, manual_notes)
    summary = sanitized["summary"]

    lines = [
        "# Lane C — Live Docent QA (Sanitized)",
        "",
        f"- Generated at: `{sanitized['generated_at']}`",
        f"- Base URL: `{sanitized['base_url']}`",
        f"- Places: `{sanitized['place_count']}` — records: `{summary['record_count']}`",
        f"- Run caps: `{json.dumps(sanitized['run_caps'], sort_keys=True)}`",
        f"- Counters: `{json.dumps(sanitized['counters'], sort_keys=True)}`",
        f"- Token counters: `{json.dumps(sanitized['token_counters'], sort_keys=True)}`",
        f"- Estimated cost: `${sanitized['estimated_cost_usd']}` (stop-loss estimate, not billing)",
        f"- Average auto precheck: `{summary['average_auto_precheck_score']}`",
        f"- Category averages: `{json.dumps(summary['category_average'], ensure_ascii=False)}`",
        f"- Language averages: `{json.dumps(summary['language_average'], ensure_ascii=False)}`",
        f"- Issue counts: `{json.dumps(summary['issue_counts'], ensure_ascii=False)}`",
        "",
        "## Dimension flags (deterministic audits)",
        "",
        "| Dimension | Pass | Flagged | Not applicable |",
        "|---|---:|---:|---:|",
    ]
    for dim, flags in summary["dimension_flags"].items():
        lines.append(
            f"| {dim} | {flags['pass']} | {flags['flagged']} | {flags['not_applicable']} |"
        )

    lines.extend(["", "## Per-record results", ""])
    lines.append(
        "| Place | Cat | Region | Lang | Src | Ground | Score | Blocker | Issues | Manual |"
    )
    lines.append("|---|---|---|---|---|---|---:|---|---|---|")
    for r in sanitized["records"]:
        manual = r.get("manual_verdict") or "-"
        issues = ", ".join(r.get("issue_tags") or [])
        lines.append(
            "| {name} ({pid}) | {cat} | {reg} | {lang} | {src} | {g} | {score} | {blk} | {iss} | {manual} |".format(
                name=str(r.get("place_name"))[:18],
                pid=r["place_id"],
                cat=r["category"],
                reg=str(r.get("region") or "-"),
                lang=r["language"],
                src=str(r.get("source") or r.get("error_code") or "-"),
                g=r.get("grounding_count"),
                score=r.get("auto_precheck_score"),
                blk="yes" if r.get("blocker") else "no",
                iss=issues or "-",
                manual=manual,
            )
        )

    lines.extend(["", "## Evidence excerpts", ""])
    for r in sanitized["records"]:
        if not r.get("script_excerpt"):
            continue
        lines.append(
            f"### {r['place_name']} ({r['place_id']}, {r['language']}) — {r['category']}/{r['region']}"
        )
        lines.append("")
        lines.append(f"> {r['script_excerpt']}")
        lines.append("")

    output = Path(args.output) if args.output else Path(args.report).parent / "sanitized-report.md"
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    json_out = output.with_suffix(".json")
    json_out.write_text(json.dumps(sanitized, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"sanitized report: {output}")
    print(f"sanitized json:   {json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
