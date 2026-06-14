param(
    [string]$Python = "",
    [int]$ApiPort = 0,
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
        Write-Host "Running local OAuth/JWT smoke."
        Write-Host "This script creates only local test keys, a local JWKS server, and a temporary local API process."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.smoke_oauth_jwt",
        "--api-port",
        "$ApiPort"
    )
    if ($Json) {
        $toolArgs += "--json"
    }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Local OAuth/JWT smoke failed."
    }
} finally {
    Pop-Location
}
