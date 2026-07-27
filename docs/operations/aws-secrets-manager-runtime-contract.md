# AWS Secrets Manager runtime contract

This contract is the runtime boundary for LALA-next API and worker entrypoints.
It is separate from PR #76's team handoff and local synchronization/build
helpers: those documents describe operator preparation, while this document
defines what a running process is allowed to read.

## Profiles

`LALA_RUNTIME_PROFILE` is one of `local`, `ci`, `api`, or `worker`.

- `api` and `worker` use the process IAM role and AWS Secrets Manager only.
  They do not use dotenv, process-provided secret values, or the legacy Azure
  Key Vault path. Lookup errors fail the required startup/readiness/batch
  contract.
- `ci` reads only explicit test environment variables. It never calls AWS or
  loads dotenv.
- `local` is the only profile allowed to load an explicit local dotenv file.
  AWS use is opt-in with `LALA_LOCAL_USE_AWS_SECRETS`; the legacy Key Vault
  callback remains a local compatibility seam only.

The central registry is `apps/api/app/core/runtime_secrets.py`. It maps each
logical environment name to its AWS secret name. Required values are selected
by enabled capabilities: API database and authentication, live AI, live
speech, and worker job inputs. Empty or obvious placeholder values fail the
operational contract.

## Entry points and failure behavior

- API: `scripts/unix/start_api.sh`, `scripts/windows/start_api.ps1`, the API
  systemd unit, and the container image select `api`.
- Worker: the worker systemd units select `worker`; worker batch tools use the
  same resolver and fail closed for required secrets.
- CI: the workflow selects `ci`, so contract tests remain offline.

The readiness payload may expose profile, status, and logical secret names
only. It must never expose a secret value, full ARN, token, DSN, or provider
error payload. Dry-run workers remain external-free and never resolve AWS.

No AWS request, database migration, deployment, live AI/translation call, or
external collection is part of this PR. IAM policy attachment, secret
inventory, rotation/retention, and production rollout require an external
operations decision.
