param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$Python = "",
    [string]$RequestId = "",
    [string]$RoutePath = "",
    [int]$Limit = 20,
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
        Write-Host "Inspecting a local LALA-next JSONL access log."
        Write-Host "This script is read-only and prints only bounded access-log fields."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.inspect_access_log",
        $Path,
        "--limit",
        "$Limit"
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($RequestId) { $toolArgs += @("--request-id", $RequestId) }
    if ($RoutePath) { $toolArgs += @("--route-path", $RoutePath) }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Access log inspection command failed."
    }
} finally {
    Pop-Location
}
