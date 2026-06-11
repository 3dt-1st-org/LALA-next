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

## Manual API Smoke

Start the API:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080
```

Smoke the public and authenticated routes:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
```

`smoke_api.ps1` can load `IOS_API_KEY` from Key Vault when `KEY_VAULT_URL` is
configured and Azure CLI is authenticated. It never prints the key value.
Without `-PaidDependency`, authenticated route checks are skipped when an API key
is not available.

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
or generated audio content. With `-PaidDependency`, a missing `IOS_API_KEY` is a
failure rather than a skipped check.
