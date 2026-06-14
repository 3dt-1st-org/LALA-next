param(
    [string]$Python = "",
    [string]$KeyVaultUrl = "",
    [switch]$Preview,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$Stdate = "",
    [string]$Eddate = "",
    [string]$Signgucode = "41",
    [string]$Signgucodesub = "",
    [string]$Prfstate = "",
    [int]$Rows = 20,
    [int]$PageSize = 10,
    [int]$Timeout = 10,
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
        Write-Host "Planning LALA-next KOPIS performance ingestion."
        Write-Host "Default mode is dry-run plan only."
        Write-Host "Preview mode calls KOPIS but does not mutate DB."
        Write-Host "Apply mode requires ALLOW_KOPIS_INGEST_APPLY=1."
        Write-Host "KOPIS_API_KEY and DB_DSN values are never printed by this script."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.run_kopis_ingest",
        "--signgucode",
        $Signgucode,
        "--signgucodesub",
        $Signgucodesub,
        "--prfstate",
        $Prfstate,
        "--rows",
        "$Rows",
        "--page-size",
        "$PageSize",
        "--timeout",
        "$Timeout",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    if ($Stdate) {
        $toolArgs += @("--stdate", $Stdate)
    }
    if ($Eddate) {
        $toolArgs += @("--eddate", $Eddate)
    }
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
        throw "KOPIS performance ingest command failed."
    }
} finally {
    Pop-Location
}
