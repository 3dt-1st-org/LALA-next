#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

ENV_FILE=""
HOSTNAME="api.lala-next.cloud"
REQUESTS_PER_PERIOD="30"
PERIOD_SECONDS="60"
MITIGATION_TIMEOUT_SECONDS="600"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --hostname) HOSTNAME="${2:-}"; shift 2 ;;
    --requests-per-period) REQUESTS_PER_PERIOD="${2:-}"; shift 2 ;;
    --period-seconds) PERIOD_SECONDS="${2:-}"; shift 2 ;;
    --mitigation-timeout-seconds) MITIGATION_TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/apply_cloudflare_edge_controls.sh --apply --confirm APPLY_CLOUDFLARE_EDGE_CONTROLS"
      echo "Creates the LALA paid-route Cloudflare rate limiting rule through the Rulesets API."
      echo "Requires CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID in process env or ignored env file."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
cd "$ROOT"

if [[ -z "$ENV_FILE" && -f "$ROOT/runtime/onprem-api.env" ]]; then
  ENV_FILE="$ROOT/runtime/onprem-api.env"
fi
if [[ -n "$ENV_FILE" ]]; then
  load_env_names_from_file "$ENV_FILE" CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID
fi

case "$REQUESTS_PER_PERIOD" in ''|*[!0-9]*) echo "--requests-per-period must be a positive integer." >&2; exit 2 ;; esac
case "$PERIOD_SECONDS" in ''|*[!0-9]*) echo "--period-seconds must be a positive integer." >&2; exit 2 ;; esac
case "$MITIGATION_TIMEOUT_SECONDS" in ''|*[!0-9]*) echo "--mitigation-timeout-seconds must be a positive integer." >&2; exit 2 ;; esac

echo "LALA Cloudflare edge controls"
echo "env_file=${ENV_FILE:-disabled}"
echo "hostname=$HOSTNAME"
echo "phase=http_ratelimit"
echo "route_scope=docent-paid-routes"
echo "requests_per_period=$REQUESTS_PER_PERIOD"
echo "period_seconds=$PERIOD_SECONDS"
echo "mitigation_timeout_seconds=$MITIGATION_TIMEOUT_SECONDS"
echo "cloudflare_token_configured=$([[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] && echo true || echo false)"
echo "cloudflare_zone_configured=$([[ -n "${CLOUDFLARE_ZONE_ID:-}" ]] && echo true || echo false)"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "APPLY_CLOUDFLARE_EDGE_CONTROLS" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm APPLY_CLOUDFLARE_EDGE_CONTROLS"
  exit 0
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  echo "CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID are required." >&2
  exit 2
fi

HOSTNAME="$HOSTNAME" \
REQUESTS_PER_PERIOD="$REQUESTS_PER_PERIOD" \
PERIOD_SECONDS="$PERIOD_SECONDS" \
MITIGATION_TIMEOUT_SECONDS="$MITIGATION_TIMEOUT_SECONDS" \
python3 - <<'PY'
from __future__ import annotations

import json
import os
import sys
from urllib import error, request

api_token = os.environ["CLOUDFLARE_API_TOKEN"]
zone_id = os.environ["CLOUDFLARE_ZONE_ID"]
hostname = os.environ["HOSTNAME"]
requests_per_period = int(os.environ["REQUESTS_PER_PERIOD"])
period_seconds = int(os.environ["PERIOD_SECONDS"])
mitigation_timeout_seconds = int(os.environ["MITIGATION_TIMEOUT_SECONDS"])

base = "https://api.cloudflare.com/client/v4"
phase = "http_ratelimit"
description = "LALA paid docent route rate limit"
expression = (
    f'(http.host eq "{hostname}" and http.request.method eq "POST" and '
    '(http.request.uri.path eq "/api/v1/docents/script" or '
    'http.request.uri.path eq "/api/v1/docents/audio"))'
)
rule = {
    "description": description,
    "expression": expression,
    "action": "block",
    "action_parameters": {
        "response": {
            "status_code": 429,
            "content": "Too many LALA docent requests. Please retry shortly.",
            "content_type": "text/plain",
        }
    },
    "ratelimit": {
        "characteristics": ["cf.colo.id", "ip.src"],
        "period": period_seconds,
        "requests_per_period": requests_per_period,
        "mitigation_timeout": mitigation_timeout_seconds,
        "requests_to_origin": True,
    },
}


def call(method: str, path: str, payload: dict | None = None, *, allow_404: bool = False) -> dict | None:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    req = request.Request(
        f"{base}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json",
            "User-Agent": "LALA-next-cloudflare-edge-controls/1.0",
        },
    )
    try:
        with request.urlopen(req, timeout=20) as response:
            raw = response.read()
    except error.HTTPError as exc:
        if exc.code == 404 and allow_404:
            return None
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"cloudflare_api_error_status={exc.code}", file=sys.stderr)
        print(detail[:1000], file=sys.stderr)
        raise SystemExit(1) from exc
    parsed = json.loads(raw.decode("utf-8"))
    if not parsed.get("success"):
        print("cloudflare_api_success=false", file=sys.stderr)
        print(json.dumps(parsed.get("errors", []), ensure_ascii=False)[:1000], file=sys.stderr)
        raise SystemExit(1)
    return parsed["result"]


entrypoint = call(
    "GET",
    f"/zones/{zone_id}/rulesets/phases/{phase}/entrypoint",
    allow_404=True,
)
if entrypoint is None:
    created = call(
        "POST",
        f"/zones/{zone_id}/rulesets",
        {
            "name": "LALA API rate limiting",
            "description": "Rate limits public contest paid API routes.",
            "kind": "zone",
            "phase": phase,
            "rules": [rule],
        },
    )
    print("cloudflare_rate_limit_ruleset=created")
    print(f"ruleset_id={created.get('id', '<unknown>')}")
    print("rule_action=created")
    raise SystemExit(0)

for existing in entrypoint.get("rules", []):
    if existing.get("description") == description:
        print("cloudflare_rate_limit_ruleset=existing")
        print(f"ruleset_id={entrypoint.get('id', '<unknown>')}")
        print("rule_action=already_present")
        raise SystemExit(0)

created_rule = call(
    "POST",
    f"/zones/{zone_id}/rulesets/{entrypoint['id']}/rules",
    rule,
)
print("cloudflare_rate_limit_ruleset=existing")
print(f"ruleset_id={entrypoint.get('id', '<unknown>')}")
print(f"rule_id={created_rule.get('id', '<unknown>')}")
print("rule_action=created")
PY
