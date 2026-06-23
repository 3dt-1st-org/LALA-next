param(
    [string]$Python = "",
    [string]$KeyVaultUrl = "",
    [switch]$Preview,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$Provider = "all",
    [int]$Limit = 500,
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
        Write-Host "Planning LALA-next review/mention preprocessing."
        Write-Host "Default mode is dry-run plan only."
        Write-Host "Preview mode reads approved community.posts and travel.places but does not mutate DB."
        Write-Host "Apply mode requires ALLOW_REVIEW_MENTION_INGEST_APPLY=1."
        Write-Host "DB_DSN value is never printed by this script."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.run_review_mention_ingest",
        "--provider",
        $Provider,
        "--limit",
        "$Limit",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($Preview) {
        $toolArgs += "--preview"
    }
    if ($Apply) {
        $toolArgs += "--apply"
    }
    if ($Confirm) {
        $toolArgs += @("--confirm", $Confirm)
    }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Review/mention preprocessing command failed."
    }
} finally {
    Pop-Location
}
