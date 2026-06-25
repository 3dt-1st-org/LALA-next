param(
    [string]$Python = "",
    [string]$EnvFile = "",
    [string]$KeyVaultUrl = "",
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

    if (-not $EnvFile) {
        $EnvFile = Join-Path $RepoRoot ".env"
    }
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
        Write-Host "Verifying LALA-next canonical DB schema."
        Write-Host "DB_DSN value is never printed by this script."
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.verify_db_schema",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    if ($Json) {
        $toolArgs += "--json"
    }
    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "DB schema verification failed."
    }
} finally {
    Pop-Location
}
