param(
    [string]$Python = "",
    [string]$KeyVaultUrl = "",
    [switch]$DryRunAi,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$Category = "all",
    [int]$Limit = 50,
    [int]$BatchSize = 20,
    [int]$ConnectTimeout = 5,
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

    if ($KeyVaultUrl) {
        [Environment]::SetEnvironmentVariable("KEY_VAULT_URL", $KeyVaultUrl, "Process")
    }

    $EnvFile = Join-Path $RepoRoot ".env"
    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | ForEach-Object {
            $line = $_.Trim()
            if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
                return
            }
            $name, $value = $line.Split("=", 2)
            $name = $name.Trim()
            $value = $value.Trim().Trim('"').Trim("'")
            if ($name -and -not [Environment]::GetEnvironmentVariable($name, "Process")) {
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }

    if (-not $Json) {
        Write-Host "Planning LALA-next place AI enrichment."
        Write-Host "Default mode is plan only and does not call Azure OpenAI."
        Write-Host "Dry-run AI mode reads DB and calls Azure OpenAI but does not update rows."
        Write-Host "Apply mode requires ALLOW_AI_PLACE_ENRICHMENT_APPLY=1."
        Write-Host "AZURE_OPENAI_KEY and DB_DSN values are never printed by this script."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.enrich_place_ai_columns",
        "--category",
        $Category,
        "--limit",
        "$Limit",
        "--batch-size",
        "$BatchSize",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($DryRunAi) {
        $toolArgs += "--dry-run-ai"
    }
    if ($Apply) {
        $toolArgs += "--apply"
    }
    if ($Confirm) {
        $toolArgs += @("--confirm", $Confirm)
    }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Place AI enrichment command failed."
    }
} finally {
    Pop-Location
}
