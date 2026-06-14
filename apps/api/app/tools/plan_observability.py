from __future__ import annotations

import argparse
import json
import sys

from apps.api.app.services.observability_plan import build_observability_plan


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan LALA-next observability alerts and dashboards without applying changes."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    args = parser.parse_args(argv)

    plan = build_observability_plan(base_url=args.base_url)
    payload = plan.to_dict()
    _write(args, payload)
    return 0


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next observability plan")
    print("mode=plan")
    print("applies_changes=false")
    print(f"scrape_endpoint={payload.get('scrape_endpoint')}")
    print(f"metric_count={len(payload.get('metrics') or [])}")
    print(f"alert_rule_count={len(payload.get('alert_rules') or [])}")
    print(f"dashboard_panel_count={len(payload.get('dashboard_panels') or [])}")
    for rule in payload.get("alert_rules") or []:
        print(f"alert={rule['name']} severity={rule['severity']} window={rule['window']}")


if __name__ == "__main__":
    sys.exit(main())
