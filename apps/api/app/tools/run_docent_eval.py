"""CLI harness for the offline docent QA eval (V4-C).

Loads the committed synthetic fixture, runs :mod:`docent_eval` with the OpenAI client mocked
at the boundary (no network, no DB, ``LALA_ENABLE_LIVE_AI`` off), asserts category coverage +
per-place expectations + the honest-empty path, writes a deterministic JSON report to
``output/local/docent-eval/report.json`` (gitignored), prints a pass/fail summary, and exits 0
on all-pass / non-zero otherwise.

Runnable as ``python -m apps.api.app.tools.run_docent_eval`` (from repo root) or
``python -m app.tools.run_docent_eval`` (from ``apps/api``).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# Bootstrap repo root onto sys.path so the absolute ``apps.api...`` imports resolve regardless
# of the invocation directory (matches the established apps.api.app.tools import style).
_REPO_ROOT = Path(__file__).resolve().parents[4]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from apps.api.app.services import docent_eval, docent_judge  # noqa: E402

REPORT_PATH = _REPO_ROOT / "output" / "local" / "docent-eval" / "report.json"


def _summary(report: dict[str, Any]) -> str:
    counts = report["category_counts"]
    parts = [f"{category}={counts[category]}" for category in docent_eval.CATEGORIES]
    language_counts = report.get("language_case_counts") or {}
    language_parts = ",".join(
        f"{language}={language_counts.get(language, 0)}" for language in docent_eval.LANGUAGES
    )
    honest = ", ".join(report["honest_empty_place_ids"]) or "none"
    flagged = sum(
        dimension.get("flagged", 0)
        for dimension in (report.get("dimension_summary") or {}).values()
    )
    judge_status = (report.get("judge_gate") or {}).get("status", "NOT_RUN")
    return (
        f"places={report['total_places']} "
        f"language_cases={report.get('total_language_cases', 0)}({language_parts}) "
        f"categories({', '.join(parts)}) "
        f"honest_empty=[{honest}] "
        f"live_client_constructions={report['live_client_constructions']} "
        f"dimension_flagged={flagged} "
        f"judge_gate={judge_status} "
        f"passed={report['passed']}"
    )


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="Run the offline docent QA eval over the committed synthetic fixture."
    )
    parser.add_argument(
        "--fixture",
        default=str(docent_eval.FIXTURE_DEFAULT),
        help="Path to the docent eval fixture JSON (default: committed fixture).",
    )
    parser.add_argument(
        "--output",
        default=str(REPORT_PATH),
        help="Path to write the deterministic JSON report (default: output/local/...).",
    )
    parser.add_argument(
        "--judge-fake",
        action="store_true",
        help=(
            "Run the optional P6B model-judge gate with an injected offline fake "
            "provider (zero network/paid calls). Default: judge gate reports NOT_RUN."
        ),
    )
    args = parser.parse_args(argv)

    places = docent_eval.load_fixture(args.fixture)
    with docent_eval.offline_openai_guard():
        report = docent_eval.evaluate_docent(places)
    report_dict = report.to_dict()
    # The judge gate is a separate optional gate on the report. It never
    # modifies the deterministic P6A results or the exit code; when no judge
    # ran it reports NOT_RUN — never PASS.
    if args.judge_fake:
        judge_records = [
            {
                "place_id": place_result.place_id,
                "category": place_result.category,
                "language": language_result.language,
                "script": language_result.script,
            }
            for place_result in report.place_results
            for language_result in place_result.languages
        ]
        judge_run = docent_judge.run_judge_batch(
            judge_records,
            provider=docent_judge.FakeJudgeProvider(),
            policy=docent_judge.JudgeBatchPolicy(),
        )
        report_dict["judge_gate"] = docent_judge.judge_gate_section(judge_run)
    else:
        report_dict["judge_gate"] = docent_judge.judge_gate_section(None)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(report_dict, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(f"docent-eval: {_summary(report_dict)}")
    print(f"report: {output_path}")
    if not report.passed:
        print("FAILURES:")
        for failure in report.failures:
            print(f"  - {failure}")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
