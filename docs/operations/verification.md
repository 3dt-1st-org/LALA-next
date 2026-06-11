# Verification

This repository keeps Wave 1 verification lightweight and repeatable. The checks
are intentionally local-first so controller, implementation, and verification
sessions can run the same commands without requiring live Azure or database
dependencies.

## Local Verification

From `C:\Users\EL035\dataschool\LALA-next`:

```powershell
.\scripts\windows\verify_repo.ps1
```

The script uses `.venv\Scripts\python.exe` automatically when it exists. Use
`-Python <path-to-python.exe>` to override the interpreter.

If dependencies are already installed:

```powershell
.\scripts\windows\verify_repo.ps1 -SkipInstall
```

The script runs:

- FastAPI route tests.
- API-key and response-envelope contract tests.
- Request id, request duration, public metrics, and secret-safe request logging tests.
- Canonical SQL plan/apply guard tests.
- Worker/batch dry-run contract tests and smoke.
- In-process OpenAPI export tests and local handoff export.
- SQL and documentation secret-safety tests.
- PowerShell script parser checks.

## CI Verification

GitHub Actions runs the same test suite on every push to `main` and every pull
request:

- `python -m pip install -e ".[dev]"`
- `python -m pytest apps/api/tests`
- PowerShell parser checks for `scripts/windows/*.ps1`

CI does not require live Key Vault, Azure OpenAI, Azure Speech, or PostgreSQL.
Those dependencies are represented as `configured`, `missing`, `degraded`, or
`skipped` in `/readyz` and are smoke-tested manually when credentials are
available.

When `DB_DSN` is configured, `/readyz` connects to PostgreSQL and verifies the
canonical relations required by the API:

- `locallink.v_public_places`
- `locallink.realtime_weather_conditions`
- `locallink.docent_cache`

Without `DB_DSN`, DB readiness is `skipped` and DB-backed routes use their
skeleton fallback. If the connection works but those relations are absent,
DB readiness is `degraded` rather than `configured`.

For an explicit read-only canonical schema check against the configured DB,
run:

```powershell
.\scripts\windows\verify_db_schema.ps1
```

The script reads `DB_DSN` from the process, `.env`, or the configured
LALA-next Key Vault. It checks required extensions, schemas, tables, and views
without applying migrations or printing the DSN. A missing `DB_DSN`, connection
failure, or missing canonical object returns a non-zero exit code so operators
can stop before handing the DB to Flutter/API smoke testers.
Use `-Json` when another tool needs machine-readable output; in that mode the
PowerShell wrapper suppresses human-readable preamble text.

To review the exact canonical SQL files before any DB rollout, run:

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Default mode is dry-run plan only. It lists canonical files, statement counts,
and SHA-256 hashes without connecting to PostgreSQL. Applying the plan requires
all three explicit controls:

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

The apply path reads `DB_DSN` from the process, `.env`, or LALA-next Key Vault,
runs `sql/canonical/*.sql` in sorted order inside one transaction, and does not
print the DSN. Use it only for an approved dev/shared target after the plan has
been reviewed.

To verify worker and batch boundaries without external reads or writes, run:

```powershell
.\scripts\windows\smoke_workers.ps1
```

This command lists worker contracts and dry-runs each job. It is safe without
`DB_DSN`, Key Vault access, Event Hub access, or live Azure Functions.

To export the Flutter handoff schema without running a server, run:

```powershell
.\scripts\windows\export_openapi.ps1 -InProcess
```

The schema is written under `artifacts/openapi/`, which is a local handoff
artifact path and is ignored by git. Omit `-Python` locally unless you need to
override the interpreter; the wrapper prefers `.venv\Scripts\python.exe` when it
exists.

Before any live DB apply, verify Azure-side database readiness:

```powershell
.\scripts\windows\verify_db_resources.ps1
```

The strict form uses `-RequireDatabase` and fails when the PostgreSQL Flexible
Server, database, required extension allowlist, or Key Vault `db-dsn` secret
name is missing.

`docents/script` reads non-expired rows from `locallink.docent_cache` before
calling Azure OpenAI. Successful live Azure OpenAI scripts are written back to
that cache on a best-effort basis. A cache write failure should be logged in a
later observability wave, but it does not fail the Wave 1 API contract.

## Manual API Smoke

Start the API:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080
```

Smoke the public and authenticated routes:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
```

`smoke_api.ps1` can use `API_BEARER_TOKEN` or `IOS_API_KEY`. When
`KEY_VAULT_URL` is configured and Azure CLI is authenticated, it attempts to load
the migration API key and then the optional bearer token from Key Vault. It never
prints secret values.
Public smoke checks include `/healthz`, `/readyz`, `/metrics`, and
`/openapi.json`.
Without `-PaidDependency`, authenticated route checks are skipped when client
auth is not available.

## Azure Resource Verification

When the question is whether this repository is using the new LALA-next Azure
resources rather than the existing ONMU vault, run:

```powershell
.\scripts\windows\verify_azure_resources.ps1
```

This check is intentionally separate from local and CI verification because it
requires Azure CLI login and live Azure read access. It prints resource names,
deployment metadata, and secret names only; it does not print secret values.

## Paid Dependency Checks

Live Azure OpenAI and Azure Speech checks are kept opt-in. Use them only when a
small paid smoke request is acceptable:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -EnableLiveAI -EnableLiveSpeech
```

In another terminal:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -PaidDependency
```

The paid smoke checks verify that `docents/script` is backed by Azure OpenAI and
that `docents/audio` returns `audio/mpeg` bytes. They do not print secret values
or generated audio content. With `-PaidDependency`, missing client auth is a
failure rather than a skipped check.

The latest controller-session live smoke evidence is recorded in
[live-azure-smoke-2026-06-11.md](live-azure-smoke-2026-06-11.md).
