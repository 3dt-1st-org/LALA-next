# Legacy Flask Retirement Plan

Wave 1 does not remove the legacy Flask application. The safe path is to keep
the Flutter/FastAPI contract moving while legacy web, dashboard, settings, and
action-log consumers are inventoried.

Generate the non-mutating plan:

```bash
scripts/unix/plan_legacy_retirement.sh
```

```powershell
.\scripts\windows\plan_legacy_retirement.ps1
```

The plan does not delete Flask routes, change deployments, edit Key Vault, apply
SQL, or print secrets. It maps legacy mobile routes to the new `/api/v1/*`
contract, identifies web/dashboard surfaces that have no Wave 1 replacement, and
lists approval gates before any deprecation or removal.

## Route Families

| Legacy family | Wave 1 destination | Status |
|---|---|---|
| `/api/places`, `/api/ios/v1/places` | `/api/v1/places` | FastAPI route implemented |
| `/api/weather`, `/api/ios/v1/weather` | `/api/v1/weather` | FastAPI route implemented |
| `/api/docent/script`, `/api/ios/v1/docent/script` | `/api/v1/docents/script` | FastAPI route implemented |
| `/api/docent/audio`, `/api/ios/v1/docent/audio` | `/api/v1/docents/audio` | FastAPI route implemented |
| `/api/planner/daily-plan` | `/api/v1/plans/daily` | FastAPI route implemented |
| `/api/planner/intervention` | `/api/v1/plans/intervention` | FastAPI route implemented |
| `/api/health` | `/healthz`, `/readyz` | Operational split implemented |
| `/map`, `/dashboard`, `/settings` | none in Wave 1 | Keep, rebuild, or remove later |
| action-log routes | none in Wave 1 | Assign analytics/ops ownership first |

## Decision Options

- `keep_legacy_admin`: keep Flask only for internal/admin web surfaces while
  Flutter uses FastAPI.
- `migrate_web_frontend`: rebuild map, dashboard, and settings surfaces before
  retiring Flask.
- `remove_flask`: remove Flask only after mobile, web, dashboard, and action-log
  consumers are proven gone.

## Approval Gates

- Do not import Flask route internals into FastAPI.
- Do not remove Flask web/dashboard before owner and traffic inventory.
- Do not retire static auth until Flutter token acquisition is verified.
- Do not treat Windows hosting as a replacement for Azure Functions, Event Hub,
  or Power BI.
- Do not delete legacy routes before a monitored deprecation window and rollback
  approval.
