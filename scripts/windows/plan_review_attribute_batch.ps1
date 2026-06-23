param(
    [string]$Python = "",
    [string]$KeyVaultUrl = "",
    [switch]$Preview,
    [switch]$DryRunAi,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$Category = "all",
    [int]$Limit = 50,
    [int]$MinOrganic = 3,
    [int]$BatchSize = 10,
    [int]$RetryAttempts = 3,
    [double]$RetryDelaySec = 5.0,
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
        Write-Host "Planning LALA-next review attribute batch."
        Write-Host "Default mode is dry-run plan only."
        Write-Host "Preview mode reads review mentions and computes deterministic attributes without mutating DB."
        Write-Host "Dry-run AI mode calls Azure OpenAI but does not mutate DB."
        Write-Host "Apply mode requires ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1."
        Write-Host "AZURE_OPENAI_KEY and DB_DSN values are never printed by this script."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.run_review_attribute_batch",
        "--category",
        $Category,
        "--limit",
        "$Limit",
        "--min-organic",
        "$MinOrganic",
        "--batch-size",
        "$BatchSize",
        "--retry-attempts",
        "$RetryAttempts",
        "--retry-delay-sec",
        "$RetryDelaySec",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($Preview) {
        $toolArgs += "--preview"
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
        throw "Review attribute batch command failed."
    }
} finally {
    Pop-Location
}
