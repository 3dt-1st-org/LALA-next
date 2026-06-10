param(
    [switch]$SkipInstall,
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $RepoRoot
try {
    if (-not $SkipInstall) {
        Write-Host "Installing LALA-next API package with dev dependencies..."
        & $Python -m pip install -e ".[dev]"
    }

    Write-Host "Running FastAPI tests and safety contracts..."
    & $Python -m pytest apps/api/tests

    Write-Host "Checking PowerShell script syntax..."
    $parseErrors = @()
    Get-ChildItem -Path "scripts/windows" -Filter "*.ps1" | ForEach-Object {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        if ($errors) {
            $parseErrors += $errors
        }
    }

    if ($parseErrors.Count -gt 0) {
        $parseErrors | ForEach-Object { Write-Error $_.Message }
        throw "PowerShell script syntax check failed."
    }

    Write-Host "Repository verification completed."
} finally {
    Pop-Location
}
