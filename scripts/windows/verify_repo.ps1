param(
    [switch]$SkipInstall,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $RepoRoot
try {
    if (-not $Python) {
        $VenvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
        if (Test-Path $VenvPython) {
            $Python = $VenvPython
        } else {
            $Python = "python"
        }
    }

    if (-not $SkipInstall) {
        Write-Host "Installing LALA-next API package with dev dependencies..."
        & $Python -m pip install -e ".[dev]"
        if ($LASTEXITCODE -ne 0) {
            throw "Dependency installation failed."
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

    Write-Host "Exporting OpenAPI schema in-process..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\export_openapi.ps1" -InProcess -Python $Python
    if ($LASTEXITCODE -ne 0) {
        throw "OpenAPI schema export failed."
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
