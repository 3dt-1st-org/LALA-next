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
- Request id, request duration, and secret-safe request logging tests.
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
Public smoke checks include `/healthz`, `/readyz`, and `/openapi.json`.
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
