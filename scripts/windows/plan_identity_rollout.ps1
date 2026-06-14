param(
    [string]$Python = "",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [switch]$Json,
    [string]$KeyVaultName = "",
    [string]$ApiAppName = "",
    [string]$FlutterAppName = "",
    [string]$ApiAppIdUri = "",
    [string[]]$RequiredScope = @()
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
        Write-Host "Planning LALA-next OAuth/Entra identity rollout."
        Write-Host "This script does not create Entra apps, Key Vault secrets, token validators, or print secrets."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.plan_identity_rollout",
        "--base-url",
        $BaseUrl
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($KeyVaultName) { $toolArgs += @("--key-vault-name", $KeyVaultName) }
    if ($ApiAppName) { $toolArgs += @("--api-app-name", $ApiAppName) }
    if ($FlutterAppName) { $toolArgs += @("--flutter-app-name", $FlutterAppName) }
    if ($ApiAppIdUri) { $toolArgs += @("--api-app-id-uri", $ApiAppIdUri) }
    foreach ($scope in $RequiredScope) {
        if ($scope) {
            $toolArgs += @("--required-scope", $scope)
        }
    }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Identity rollout plan command failed."
    }
} finally {
    Pop-Location
}
