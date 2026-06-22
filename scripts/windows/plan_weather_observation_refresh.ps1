param(
    [string]$Python = "",
    [string]$KeyVaultUrl = "",
    [switch]$Preview,
    [switch]$Apply,
    [string]$Confirm = "",
    [string[]]$Target = @(),
    [switch]$DbRegions,
    [int]$Limit = 50,
    [int]$ConnectTimeout = 5,
    [switch]$Force,
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
        Write-Host "Planning LALA-next weather observation refresh."
        Write-Host "Default mode is dry-run plan only."
        Write-Host "Preview mode calls KMA/AirKorea but does not mutate DB."
        Write-Host "Apply mode requires ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1."
        Write-Host "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.run_weather_observation_refresh",
        "--limit",
        "$Limit",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    foreach ($item in $Target) {
        $toolArgs += @("--target", $item)
    }
    if ($DbRegions) {
        $toolArgs += "--db-regions"
    }
    if ($Force) {
        $toolArgs += "--force"
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
        throw "Weather observation refresh command failed."
    }
} finally {
    Pop-Location
}
