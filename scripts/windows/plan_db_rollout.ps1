param(
    [string]$Python = "",
    [switch]$Json,
    [string]$SubscriptionId = "",
    [string]$ResourceGroup = "",
    [string]$Location = "",
    [string]$KeyVaultName = "",
    [string]$PostgresServerName = "",
    [string]$DatabaseName = "",
    [string]$AdminUser = "",
    [string]$SkuName = "",
    [string]$Tier = "",
    [int]$StorageSizeGb = 0,
    [string]$PublicAccess = ""
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
        Write-Host "Planning LALA-next PostgreSQL rollout."
        Write-Host "This script does not create Azure resources, apply SQL, or print secrets."
    }

    $toolArgs = @("-m", "apps.api.app.tools.plan_db_rollout")
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($SubscriptionId) { $toolArgs += @("--subscription-id", $SubscriptionId) }
    if ($ResourceGroup) { $toolArgs += @("--resource-group", $ResourceGroup) }
    if ($Location) { $toolArgs += @("--location", $Location) }
    if ($KeyVaultName) { $toolArgs += @("--key-vault-name", $KeyVaultName) }
    if ($PostgresServerName) { $toolArgs += @("--postgres-server-name", $PostgresServerName) }
    if ($DatabaseName) { $toolArgs += @("--database-name", $DatabaseName) }
    if ($AdminUser) { $toolArgs += @("--admin-user", $AdminUser) }
    if ($SkuName) { $toolArgs += @("--sku-name", $SkuName) }
    if ($Tier) { $toolArgs += @("--tier", $Tier) }
    if ($StorageSizeGb -gt 0) { $toolArgs += @("--storage-size-gb", "$StorageSizeGb") }
    if ($PublicAccess) { $toolArgs += @("--public-access", $PublicAccess) }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "DB rollout plan command failed."
    }
} finally {
    Pop-Location
}
