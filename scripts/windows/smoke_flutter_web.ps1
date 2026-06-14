param(
    [switch]$RequireFlutter,
    [switch]$RequireBrowser,
    [switch]$FailOnConsoleError,
    [switch]$StartApi,
    [int]$Port = 8099,
    [int]$ApiPort = 18080,
    [string]$ApiBaseUrl = "http://127.0.0.1:8080",
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$AppDir = Join-Path $RepoRoot "apps\flutter_app"
$BuildDir = Join-Path $AppDir "build\web"
$OutputDir = Join-Path $RepoRoot "output\playwright"
$HostName = "127.0.0.1"
$WebOrigin = "http://$HostName`:$Port"
$ApiBaseWasExplicit = $PSBoundParameters.ContainsKey("ApiBaseUrl")
$SmokeApiKey = "lala-web-smoke-key"
$SessionName = "lala-flutter-web-smoke-$PID"
$TempDir = [System.IO.Path]::GetTempPath()
$ApiOutLog = Join-Path $TempDir "lala-next-flutter-web-api-smoke-$Port-$ApiPort.out.log"
$ApiErrLog = Join-Path $TempDir "lala-next-flutter-web-api-smoke-$Port-$ApiPort.err.log"
$WebOutLog = Join-Path $TempDir "lala-next-flutter-web-smoke-$Port.out.log"
$WebErrLog = Join-Path $TempDir "lala-next-flutter-web-smoke-$Port.err.log"
$ApiProcess = $null
$WebProcess = $null

function Get-SelectedPython {
    param([string]$Requested)
    if ($Requested) {
        return $Requested
    }
    $venvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        return $venvPython
    }
    return "python"
}

function Test-LoopbackPortInUse {
    param([int]$PortToCheck)
    $listener = $null
    try {
        $address = [System.Net.IPAddress]::Parse("127.0.0.1")
        $listener = [System.Net.Sockets.TcpListener]::new($address, $PortToCheck)
        $listener.Start()
        return $false
    } catch {
        return $true
    } finally {
        if ($listener) {
            $listener.Stop()
        }
    }
}

function Test-HttpOk {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
    } catch {
        return $false
    }
}

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$Attempts = 80
    )
    for ($index = 0; $index -lt $Attempts; $index++) {
        if (Test-HttpOk $Url) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Timed out waiting for $Url."
}

function Invoke-PlaywrightCli {
    param([string[]]$CliArgs)
    & npx --yes --package "@playwright/cli" playwright-cli "-s=$SessionName" @CliArgs
    if ($LASTEXITCODE -ne 0) {
        throw "playwright-cli $($CliArgs -join ' ') failed."
    }
}

function Get-CombinedApiLog {
    $parts = @()
    if (Test-Path $ApiOutLog) {
        $parts += Get-Content $ApiOutLog -Raw
    }
    if (Test-Path $ApiErrLog) {
        $parts += Get-Content $ApiErrLog -Raw
    }
    return ($parts -join "`n")
}

function Set-ProcessEnvironmentForApiSmoke {
    [Environment]::SetEnvironmentVariable("KEY_VAULT_URL", "", "Process")
    [Environment]::SetEnvironmentVariable("DB_DSN", "", "Process")
    [Environment]::SetEnvironmentVariable("IOS_API_KEY", $SmokeApiKey, "Process")
    [Environment]::SetEnvironmentVariable("API_BEARER_TOKEN", "", "Process")
    [Environment]::SetEnvironmentVariable("LALA_ENABLE_LIVE_AI", "false", "Process")
    [Environment]::SetEnvironmentVariable("LALA_ENABLE_LIVE_SPEECH", "false", "Process")
    [Environment]::SetEnvironmentVariable("CORS_ALLOW_ORIGINS", $WebOrigin, "Process")
    [Environment]::SetEnvironmentVariable("LOG_LEVEL", "INFO", "Process")
}

try {
    $FlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $FlutterCommand) {
        if ($RequireFlutter) {
            throw "Flutter SDK is required for Flutter web smoke."
        }
        Write-Host "Flutter SDK is not available; skipping Flutter web smoke."
        exit 0
    }

    $NpxCommand = Get-Command npx -ErrorAction SilentlyContinue
    if (-not $NpxCommand) {
        if ($RequireBrowser) {
            throw "npx is required for Flutter web smoke."
        }
        Write-Host "npx is not available; skipping Flutter web smoke."
        exit 0
    }

    if (Test-LoopbackPortInUse $Port) {
        throw "Port $Port is already in use. Pass -Port with a free port."
    }
    if ($StartApi -and (Test-LoopbackPortInUse $ApiPort)) {
        throw "API port $ApiPort is already in use. Pass -ApiPort with a free port."
    }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $Python = Get-SelectedPython $Python

    if ($StartApi) {
        if (-not $ApiBaseWasExplicit) {
            $ApiBaseUrl = "http://$HostName`:$ApiPort"
        }

        Write-Host "Starting local skeleton API on $ApiBaseUrl for Flutter browser smoke..."
        Set-ProcessEnvironmentForApiSmoke
        $apiArgs = @(
            "-m",
            "uvicorn",
            "apps.api.app.main:app",
            "--host",
            $HostName,
            "--port",
            "$ApiPort",
            "--no-access-log"
        )
        $ApiProcess = Start-Process `
            -FilePath $Python `
            -ArgumentList $apiArgs `
            -WorkingDirectory $RepoRoot `
            -RedirectStandardOutput $ApiOutLog `
            -RedirectStandardError $ApiErrLog `
            -NoNewWindow `
            -PassThru
        Wait-HttpOk "$ApiBaseUrl/healthz"
    }

    Write-Host "Building Flutter web release bundle for browser smoke..."
    $buildArgs = @(
        "build",
        "web",
        "--release",
        "--no-wasm-dry-run",
        "--dart-define",
        "LALA_API_BASE_URL=$ApiBaseUrl"
    )
    if ($StartApi) {
        $buildArgs += @("--dart-define", "LALA_IOS_API_KEY=$SmokeApiKey")
    }
    Push-Location $AppDir
    try {
        & flutter @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build web failed."
        }
    } finally {
        Pop-Location
    }

    Write-Host "Serving Flutter web bundle on $WebOrigin ..."
    $webArgs = @("-m", "http.server", "$Port", "--bind", $HostName)
    $WebProcess = Start-Process `
        -FilePath $Python `
        -ArgumentList $webArgs `
        -WorkingDirectory $BuildDir `
        -RedirectStandardOutput $WebOutLog `
        -RedirectStandardError $WebErrLog `
        -NoNewWindow `
        -PassThru
    Wait-HttpOk "$WebOrigin/"

    Invoke-PlaywrightCli -CliArgs @("open", "$WebOrigin/")
    Invoke-PlaywrightCli -CliArgs @("resize", "1280", "900")

    $runtimeEval = @'
async () => {
  const selector = "flutter-view, flt-glass-pane, flt-scene-host";
  for (let index = 0; index < 80; index += 1) {
    if (document.querySelector(selector)) {
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return {
    title: document.title,
    hasFlutterEntrypoint: Boolean(document.querySelector(selector)),
    bodyLength: document.body ? document.body.innerHTML.length : 0,
    readyState: document.readyState
  };
}
'@
    $runtimeState = Invoke-PlaywrightCli -CliArgs @("eval", $runtimeEval, "--raw") | Out-String
    $runtimeStatePath = Join-Path $OutputDir "flutter-web-runtime.json"
    Set-Content -Path $runtimeStatePath -Value $runtimeState -Encoding UTF8
    $state = $runtimeState | ConvertFrom-Json
    if ($state.title -ne "LALA Next") {
        throw "Unexpected Flutter web title: $($state.title)"
    }
    if (-not $state.hasFlutterEntrypoint) {
        throw "Flutter web entrypoint was not present in the rendered DOM."
    }
    if ([int]$state.bodyLength -lt 100) {
        throw "Flutter web document body looked unexpectedly small."
    }

    Invoke-PlaywrightCli -CliArgs @("snapshot") |
        Set-Content -Path (Join-Path $OutputDir "flutter-web-snapshot.txt") -Encoding UTF8
    Invoke-PlaywrightCli -CliArgs @("screenshot") |
        Set-Content -Path (Join-Path $OutputDir "flutter-web-screenshot.txt") -Encoding UTF8
    Invoke-PlaywrightCli -CliArgs @("console") |
        Set-Content -Path (Join-Path $OutputDir "flutter-web-console.txt") -Encoding UTF8

    $consolePath = Join-Path $OutputDir "flutter-web-console.txt"
    if ($FailOnConsoleError -and (Select-String -Path $consolePath -Pattern "^(\[ERROR\]|error|pageerror|exception)" -Quiet)) {
        throw "Flutter web console reported an error. See $consolePath"
    }

    if ($StartApi) {
        $requiredPaths = @(
            "/healthz",
            "/readyz",
            "/api/v1/places",
            "/api/v1/weather",
            "/api/v1/plans/intervention",
            "/api/v1/plans/daily",
            "/api/v1/docents/script"
        )
        for ($index = 0; $index -lt 80; $index++) {
            $log = Get-CombinedApiLog
            $missing = @($requiredPaths | Where-Object { $log -notmatch [regex]::Escape("path=$_ ") })
            if ($missing.Count -eq 0) {
                break
            }
            Start-Sleep -Milliseconds 250
        }
        $log = Get-CombinedApiLog
        $missing = @($requiredPaths | Where-Object { $log -notmatch [regex]::Escape("path=$_ ") })
        if ($missing.Count -gt 0) {
            throw "Local API did not observe expected Flutter route hits: $($missing -join ', ')"
        }
    }

    Write-Host "Flutter web browser smoke completed."
    Write-Host "Artifacts: $OutputDir\flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt"
    if ($StartApi) {
        Write-Host "Local API logs: $ApiOutLog, $ApiErrLog"
    }
} finally {
    try {
        Invoke-PlaywrightCli -CliArgs @("close") | Out-Null
    } catch {
    }
    if ($WebProcess -and -not $WebProcess.HasExited) {
        Stop-Process -Id $WebProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($ApiProcess -and -not $ApiProcess.HasExited) {
        Stop-Process -Id $ApiProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
