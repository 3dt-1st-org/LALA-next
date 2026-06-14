param(
    [string]$Python = "",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [switch]$Json
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
        Write-Host "Planning LALA-next observability."
        Write-Host "This script does not create dashboards, alerts, Azure resources, or log sinks."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.plan_observability",
        "--base-url",
        $BaseUrl
    )
    if ($Json) {
        $toolArgs += "--json"
    }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Observability plan command failed."
    }
} finally {
    Pop-Location
}
