param(
    [switch]$RequireFlutter,
    [switch]$RequireBrowser,
    [switch]$FailOnConsoleError,
    [switch]$StartApi,
    [int]$Port = 8099,
    [int]$ApiPort = 18080,
    [string]$ApiBaseUrl = "http://127.0.0.1:8080",
    [string]$WebUrl = "",
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
$TargetUrl = "$WebOrigin/"
$ApiBaseWasExplicit = $PSBoundParameters.ContainsKey("ApiBaseUrl")
$WebUrlWasExplicit = $PSBoundParameters.ContainsKey("WebUrl") -and $WebUrl
$SmokeApiKey = "lala-web-smoke-key"
$SmokeLat = "37.5665"
$SmokeLng = "126.9780"
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
    if ($WebUrlWasExplicit) {
        if ($StartApi -or $ApiBaseWasExplicit) {
            throw "-WebUrl opens an already-built site; do not combine it with -StartApi or -ApiBaseUrl."
        }
        $parsedWebUrl = [System.Uri]::new($WebUrl)
        if (-not $parsedWebUrl.IsAbsoluteUri) {
            throw "-WebUrl must be an absolute URL."
        }
        $WebOrigin = "$($parsedWebUrl.Scheme)://$($parsedWebUrl.Authority)"
        $TargetUrl = $WebUrl
    }

    $FlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $FlutterCommand -and -not $WebUrlWasExplicit) {
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

    if (-not $WebUrlWasExplicit -and (Test-LoopbackPortInUse $Port)) {
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

    if ($WebUrlWasExplicit) {
        Write-Host "Opening deployed Flutter web site at $TargetUrl ..."
    } else {
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
        $KakaoJavascriptKey = [Environment]::GetEnvironmentVariable("KAKAO_JAVASCRIPT_KEY", "Process")
        if ($KakaoJavascriptKey) {
            $buildArgs += @("--dart-define", "KAKAO_JAVASCRIPT_KEY=$KakaoJavascriptKey")
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
    }

    Invoke-PlaywrightCli -CliArgs @("open", "$TargetUrl")
    if ($WebUrlWasExplicit) {
        Invoke-PlaywrightCli -CliArgs @("resize", "390", "844")
    } else {
        Invoke-PlaywrightCli -CliArgs @("resize", "1280", "900")
    }

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
    if ($state.title -ne "LALA") {
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

    $RunLocationFlow = $StartApi -or $ApiBaseWasExplicit -or $WebUrlWasExplicit
    $ExpectDocentScript = $ApiBaseWasExplicit -or $WebUrlWasExplicit
    if ($RunLocationFlow) {
        Write-Host "Driving Flutter web location flow with test geolocation..."
        $locationFlowCode = @"
async (page) => {
  await page.context().grantPermissions(['geolocation'], { origin: '$WebOrigin' });
  await page.context().setGeolocation({ latitude: $SmokeLat, longitude: $SmokeLng });
  await page.reload({ waitUntil: 'domcontentloaded' });
  const selector = 'flutter-view, flt-glass-pane, flt-scene-host';
  for (let index = 0; index < 80; index += 1) {
    if (await page.locator(selector).count()) {
      break;
    }
    await page.waitForTimeout(250);
  }
  await page.waitForTimeout(15000);
  return { url: page.url(), viewport: page.viewportSize() || { width: 1280, height: 900 } };
}
"@
        Invoke-PlaywrightCli -CliArgs @("run-code", $locationFlowCode) |
            Set-Content -Path (Join-Path $OutputDir "flutter-web-location-flow.txt") -Encoding UTF8

        $requestLogPath = Join-Path $OutputDir "flutter-web-requests.txt"
        $requestLog = ""
        $requiredFlowPaths = @(
            "/api/v1/places",
            "/api/v1/weather",
            "/api/v1/plans/intervention",
            "/api/v1/plans/daily"
        )
        if ($ExpectDocentScript) {
            $requiredFlowPaths += "/api/v1/docents/script"
        }
        for ($index = 0; $index -lt 60; $index++) {
            $requestLog = Invoke-PlaywrightCli -CliArgs @("requests") | Out-String
            Set-Content -Path $requestLogPath -Value $requestLog -Encoding UTF8
            $missingFlowPaths = @($requiredFlowPaths | Where-Object {
                $requestLog -notmatch ([regex]::Escape($_) + ".*=> \[200\]")
            })
            $hasGrantedLocation = $requestLog -like "*lat=37.5665*" -and $requestLog -like "*lng=126.978*"
            if ($missingFlowPaths.Count -eq 0 -and $hasGrantedLocation) {
                break
            }
            Start-Sleep -Milliseconds 500
        }
        $missingFlowPaths = @($requiredFlowPaths | Where-Object {
            $requestLog -notmatch ([regex]::Escape($_) + ".*=> \[200\]")
        })
        if ($missingFlowPaths.Count -gt 0) {
            throw "Flutter location flow did not observe successful expected API requests: $($missingFlowPaths -join ', ')"
        }
        if (-not ($requestLog -like "*lat=37.5665*" -and $requestLog -like "*lng=126.978*")) {
            throw "Flutter location flow did not use the granted test geolocation."
        }
        $lowerRequestLog = $requestLog.ToLowerInvariant()
        if ($lowerRequestLog.Contains("mock://") -or
            $lowerRequestLog.Contains("placeholder://") -or
            $lowerRequestLog.Contains("dummy://")) {
            throw "Flutter location flow request log contained mock-like URLs."
        }
        Invoke-PlaywrightCli -CliArgs @("console") |
            Set-Content -Path (Join-Path $OutputDir "flutter-web-console.txt") -Encoding UTF8
    }

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
            "/api/v1/plans/daily"
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
    if ($RunLocationFlow) {
        Write-Host "Artifacts: $OutputDir\flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt, flutter-web-requests.txt"
    } else {
        Write-Host "Artifacts: $OutputDir\flutter-web-snapshot.txt, flutter-web-screenshot.txt, flutter-web-console.txt"
    }
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
