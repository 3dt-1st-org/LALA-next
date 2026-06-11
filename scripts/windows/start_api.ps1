param(
    [string]$HostName = "0.0.0.0",
    [int]$Port = 8080,
    [string]$Python = "",
    [switch]$EnableLiveAI,
    [switch]$EnableLiveSpeech
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

if (-not $Python) {
    $VenvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
    if (Test-Path $VenvPython) {
        $Python = $VenvPython
    } else {
        $Python = "python"
    }
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

if ($EnableLiveAI) {
    [Environment]::SetEnvironmentVariable("LALA_ENABLE_LIVE_AI", "true", "Process")
}

if ($EnableLiveSpeech) {
    [Environment]::SetEnvironmentVariable("LALA_ENABLE_LIVE_SPEECH", "true", "Process")
}

Write-Host "Starting LALA-next API on $HostName`:$Port"
Write-Host "Health endpoint: http://127.0.0.1:$Port/healthz"
Write-Host "Python executable: $Python"
if ($EnableLiveAI) {
    Write-Host "Live Azure OpenAI generation: enabled"
}
if ($EnableLiveSpeech) {
    Write-Host "Live Azure Speech synthesis: enabled"
}

& $Python -m uvicorn apps.api.app.main:app --host $HostName --port $Port
if ($LASTEXITCODE -ne 0) {
    throw "uvicorn exited with code $LASTEXITCODE."
}
