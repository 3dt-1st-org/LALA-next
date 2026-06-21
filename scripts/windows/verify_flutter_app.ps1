param(
    [switch]$RequireFlutter
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$AppDir = Join-Path $RepoRoot "apps\flutter_app"

$FlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $FlutterCommand) {
    if ($RequireFlutter) {
        throw "Flutter SDK is required for Flutter app verification."
    }
    Write-Host "Flutter SDK is not available; skipping Flutter app analyze/test."
    exit 0
}

Push-Location $AppDir
try {
    Write-Host "Resolving Flutter app dependencies..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed."
    }

    Write-Host "Formatting Flutter app in check-only mode..."
    dart format --set-exit-if-changed lib/main.dart lib/kakao_map_models.dart lib/kakao_map_view.dart lib/kakao_map_view_stub.dart lib/kakao_map_view_web.dart test/widget_test.dart
    if ($LASTEXITCODE -ne 0) {
        throw "dart format check failed."
    }

    Write-Host "Analyzing Flutter app..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        throw "flutter analyze failed."
    }

    Write-Host "Running Flutter app widget tests..."
    flutter test
    if ($LASTEXITCODE -ne 0) {
        throw "flutter test failed."
    }

    Write-Host "Building Flutter web release bundle..."
    $buildArgs = @("build", "web", "--release", "--pwa-strategy=none")
    $KakaoJavascriptKey = [Environment]::GetEnvironmentVariable("KAKAO_JAVASCRIPT_KEY", "Process")
    if ($KakaoJavascriptKey) {
        $buildArgs += @("--dart-define", "KAKAO_JAVASCRIPT_KEY=$KakaoJavascriptKey")
    }
    flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build web failed."
    }
} finally {
    Pop-Location
}
