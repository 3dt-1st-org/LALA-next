param(
    [string]$JobId = "",
    [string]$Python = ""
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

    Write-Host "Listing LALA-next worker contracts..."
    $listOutput = & $Python -m apps.workers.app.cli list --json
    if ($LASTEXITCODE -ne 0) {
        throw "Worker contract list failed."
    }
    $listPayload = $listOutput | ConvertFrom-Json

    Write-Host "Evaluating worker live preflight..."
    $preflightArgs = @("-m", "apps.workers.app.cli", "preflight", "--json")
    if ($JobId) {
        $preflightArgs += @("--job-id", $JobId)
    }
    $preflightOutput = & $Python @preflightArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Worker live preflight failed."
    }
    $preflightPayload = $preflightOutput | ConvertFrom-Json
    if (-not $preflightPayload.ok -or $preflightPayload.mode -ne "live_preflight") {
        throw "Worker preflight returned an unexpected payload."
    }
    if ($preflightPayload.ready -ne $false) {
        throw "Worker live preflight should remain blocked in Wave 1."
    }

    if ($JobId) {
        $jobIds = @($JobId)
    } else {
        $jobIds = @($listPayload.jobs | ForEach-Object { $_.job_id })
    }

    foreach ($id in $jobIds) {
        Write-Host "Dry-run worker job $id"
        $runOutput = & $Python -m apps.workers.app.cli run $id --dry-run --json
        if ($LASTEXITCODE -ne 0) {
            throw "Worker dry-run failed for $id."
        }
        $runPayload = $runOutput | ConvertFrom-Json
        if (-not $runPayload.ok -or $runPayload.mode -ne "dry_run") {
            throw "Worker dry-run returned an unexpected payload for $id."
        }
    }

    Write-Host "LALA-next worker smoke completed."
    Write-Host "Worker smoke uses dry-run only and never prints secret values."
} finally {
    Pop-Location
}
