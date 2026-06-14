param(
    [switch]$RequireDart
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ClientDir = Join-Path $RepoRoot "clients\flutter"

$DartCommand = Get-Command dart -ErrorAction SilentlyContinue
if (-not $DartCommand) {
    if ($RequireDart) {
        throw "Dart SDK is required for Flutter client verification."
    }
    Write-Host "Dart SDK is not available; skipping Flutter client Dart analyze/test."
    Write-Host "Python OpenAPI/client contract check still runs in verify_repo."
    exit 0
}

Push-Location $ClientDir
try {
    Write-Host "Resolving Flutter reference client dependencies..."
    dart pub get
    if ($LASTEXITCODE -ne 0) {
        throw "dart pub get failed."
    }

    Write-Host "Formatting Flutter reference client in check-only mode..."
    dart format --set-exit-if-changed lib/lala_api_client.dart test/lala_api_client_test.dart
    if ($LASTEXITCODE -ne 0) {
        throw "dart format check failed."
    }

    Write-Host "Analyzing Flutter reference client..."
    dart analyze lib/lala_api_client.dart test/lala_api_client_test.dart
    if ($LASTEXITCODE -ne 0) {
        throw "dart analyze failed."
    }

    Write-Host "Running Flutter reference client tests..."
    dart test
    if ($LASTEXITCODE -ne 0) {
        throw "dart test failed."
    }
} finally {
    Pop-Location
}
