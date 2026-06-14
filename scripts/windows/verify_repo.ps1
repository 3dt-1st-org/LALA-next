param(
    [switch]$SkipInstall,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $RepoRoot
try {
    if (-not $SkipInstall) {
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            throw "uv is required. Install uv first, then rerun this script."
        }
        Write-Host "Syncing LALA-next API package with uv dev dependencies..."
        & uv sync --extra dev
        if ($LASTEXITCODE -ne 0) {
            throw "Dependency sync failed."
        }
    }

    if (-not $Python) {
        $VenvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
        if (Test-Path $VenvPython) {
            $Python = $VenvPython
        } else {
            $Python = "python"
        }
    }

    Write-Host "Running FastAPI tests and safety contracts..."
    & $Python -m pytest apps/api/tests
    if ($LASTEXITCODE -ne 0) {
        throw "FastAPI tests or safety contracts failed."
    }

    Write-Host "Running worker dry-run smoke..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\smoke_workers.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Worker dry-run smoke failed."
    }

    Write-Host "Planning worker/batch live rollout gates..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_worker_rollout.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Worker rollout plan failed."
    }

    Write-Host "Exporting OpenAPI schema in-process..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\export_openapi.ps1" -InProcess -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "OpenAPI schema export failed."
    }

    Write-Host "Checking Flutter reference client contract..."
    & $Python -m apps.api.app.tools.check_flutter_client_contract
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter reference client contract check failed."
    }

    Write-Host "Checking Flutter reference client Dart package when Dart is available..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\verify_flutter_client.ps1"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter reference client Dart verification failed."
    }

    Write-Host "Checking Flutter app shell when Flutter is available..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\verify_flutter_app.ps1"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter app verification failed."
    }

    Write-Host "Running local OAuth/JWT smoke..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\smoke_oauth_jwt.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Local OAuth/JWT smoke failed."
    }

    Write-Host "Planning approved DB rollout sequence..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_db_rollout.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "DB rollout plan failed."
    }

    Write-Host "Planning observability alerts and dashboards..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_observability.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Observability plan failed."
    }

    Write-Host "Planning OAuth/Entra identity rollout..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_identity_rollout.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Identity rollout plan failed."
    }

    Write-Host "Planning safe ONMU Key Vault reuse..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_key_vault_reuse.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Key Vault reuse plan failed."
    }

    Write-Host "Planning local-value place score batch..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_place_score_batch.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Place score batch plan failed."
    }

    Write-Host "Planning TourAPI place ingestion..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_tour_api_ingest.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "TourAPI ingest plan failed."
    }

    Write-Host "Planning card spending file ingestion..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_card_spending_file_ingest.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Card spending file ingest plan failed."
    }

    Write-Host "Planning legacy Flask replacement or retirement..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_legacy_retirement.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Legacy Flask retirement plan failed."
    }

    Write-Host "Planning local-only dev seed/reset SQL..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\plan_dev_reset.ps1" -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "Dev seed/reset SQL plan failed."
    }

    Write-Host "Checking PowerShell script syntax..."
    $parseErrors = @()
    Get-ChildItem -Path "scripts/windows" -Filter "*.ps1" | ForEach-Object {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        if ($errors) {
            $parseErrors += $errors
        }
    }

    if ($parseErrors.Count -gt 0) {
        $parseErrors | ForEach-Object { Write-Error $_.Message }
        throw "PowerShell script syntax check failed."
    }

    Write-Host "Repository verification completed."
    Write-Host "Live Azure checks are intentionally excluded. Use smoke_api.ps1 -PaidDependency against a live-enabled API process when needed."
} finally {
    Pop-Location
}
