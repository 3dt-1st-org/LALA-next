param(
    [string]$Python = "",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [switch]$Json,
    [string]$LegacyAppLabel = "",
    [string]$FastApiAppLabel = ""
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

    if (-not $Json) {
        Write-Host "Planning LALA-next legacy Flask replacement or retirement."
        Write-Host "This script does not delete routes, change deployments, edit Key Vault, or print secrets."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.plan_legacy_retirement",
        "--base-url",
        $BaseUrl
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($LegacyAppLabel) { $toolArgs += @("--legacy-app-label", $LegacyAppLabel) }
    if ($FastApiAppLabel) { $toolArgs += @("--fastapi-app-label", $FastApiAppLabel) }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Legacy Flask retirement plan command failed."
    }
} finally {
    Pop-Location
}
