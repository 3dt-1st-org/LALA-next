param(
    [string]$Python = "",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [switch]$Json,
    [string]$SubscriptionId = "",
    [string]$ResourceGroup = "",
    [string]$Location = "",
    [string]$KeyVaultName = "",
    [string]$FunctionAppName = "",
    [string]$StorageAccountName = "",
    [string]$EventHubNamespace = "",
    [string]$EventHubName = ""
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
        Write-Host "Planning LALA-next worker/batch live rollout gates."
        Write-Host "This script does not create Azure resources, bind queues, enable mutation, or print secrets."
    }

    $toolArgs = @(
        "-m",
        "apps.workers.app.cli",
        "plan-rollout",
        "--base-url",
        $BaseUrl
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($SubscriptionId) { $toolArgs += @("--subscription-id", $SubscriptionId) }
    if ($ResourceGroup) { $toolArgs += @("--resource-group", $ResourceGroup) }
    if ($Location) { $toolArgs += @("--location", $Location) }
    if ($KeyVaultName) { $toolArgs += @("--key-vault-name", $KeyVaultName) }
    if ($FunctionAppName) { $toolArgs += @("--function-app-name", $FunctionAppName) }
    if ($StorageAccountName) { $toolArgs += @("--storage-account-name", $StorageAccountName) }
    if ($EventHubNamespace) { $toolArgs += @("--event-hub-namespace", $EventHubNamespace) }
    if ($EventHubName) { $toolArgs += @("--event-hub-name", $EventHubName) }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Worker rollout plan command failed."
    }
} finally {
    Pop-Location
}
