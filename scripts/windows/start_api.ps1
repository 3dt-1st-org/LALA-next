param(
    [string]$HostName = "0.0.0.0",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $RepoRoot

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

Write-Host "Starting LALA-next API on $HostName`:$Port"
Write-Host "Health endpoint: http://127.0.0.1:$Port/healthz"

python -m uvicorn apps.api.app.main:app --host $HostName --port $Port

