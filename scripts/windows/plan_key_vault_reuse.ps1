param(
    [string]$Python = "",
    [switch]$Json,
    [string]$SourceVaultName = "",
    [string]$TargetVaultName = ""
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
        Write-Host "Planning safe ONMU Key Vault reuse for LALA-next."
        Write-Host "This script does not read or print secret values, copy secrets, set secrets, or change Azure resources."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.plan_key_vault_reuse"
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($SourceVaultName) { $toolArgs += @("--source-vault-name", $SourceVaultName) }
    if ($TargetVaultName) { $toolArgs += @("--target-vault-name", $TargetVaultName) }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Key Vault reuse plan command failed."
    }
} finally {
    Pop-Location
}
