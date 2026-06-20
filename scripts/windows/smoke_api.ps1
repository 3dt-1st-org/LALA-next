param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$KeyVaultUrl = "",
    [string]$CorsOrigin = "",
    [switch]$PaidDependency
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
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

function Get-VaultNameFromUrl {
    param([string]$VaultUrl)
    if (-not $VaultUrl) {
        return ""
    }
    $uri = [Uri]$VaultUrl
    $hostName = $uri.Host.ToLowerInvariant().TrimEnd(".")
    if (
        $uri.Scheme -ne "https" -or
        -not $uri.IsDefaultPort -or
        -not $hostName.EndsWith(".vault.azure.net") -or
        $hostName.Contains("onmu")
    ) {
        throw "Unsupported Key Vault URL for LALA-next: $VaultUrl"
    }
    $allowedHosts = [Environment]::GetEnvironmentVariable("LALA_ALLOWED_KEY_VAULT_HOSTS", "Process")
    if ($allowedHosts) {
        $allowed = $allowedHosts.Split(",") | ForEach-Object {
            $candidate = $_.Trim()
            if ($candidate.StartsWith("https://")) {
                ([Uri]$candidate).Host.ToLowerInvariant().TrimEnd(".")
            } else {
                $candidate.Split("/")[0].ToLowerInvariant().TrimEnd(".")
            }
        }
        if ($allowed -notcontains $hostName) {
            throw "Key Vault host is not in LALA_ALLOWED_KEY_VAULT_HOSTS: $hostName"
        }
    }
    return $uri.Host.Split(".")[0]
}

function Invoke-SmokeGet {
    param(
        [string]$Path,
        [hashtable]$Headers = @{}
    )
    $url = "$BaseUrl$Path"
    Write-Host "GET $Path"
    Invoke-RestMethod -Method Get -Uri $url -Headers $Headers | Out-Null
}

function Invoke-SmokeReadyz {
    $url = "$BaseUrl/readyz"
    Write-Host "GET /readyz"
    $payload = Invoke-RestMethod -Method Get -Uri $url
    $script:ReadyzChecks = $payload.data.checks
    if (-not $payload.data -or -not $payload.data.mode) {
        throw "/readyz is missing runtime mode."
    }
    $mode = $payload.data.mode
    foreach ($name in @("overall", "data", "ai", "speech", "worker")) {
        if (-not ($mode.PSObject.Properties.Name -contains $name) -or -not $mode.$name) {
            throw "/readyz is missing runtime mode field: $name"
        }
    }
    Write-Host "runtime_mode=$($mode.overall) data=$($mode.data) ai=$($mode.ai) speech=$($mode.speech) worker=$($mode.worker)"
    $checks = $payload.data.checks
    foreach ($name in @("client_identity", "jwt_validation")) {
        if (-not $checks -or -not ($checks.PSObject.Properties.Name -contains $name)) {
            throw "/readyz is missing identity check: $name"
        }
    }
    Write-Host "identity=$($checks.client_identity) jwt_validation=$($checks.jwt_validation)"
}

function Invoke-SmokePost {
    param(
        [string]$Path,
        [object]$Body,
        [hashtable]$Headers = @{}
    )
    $url = "$BaseUrl$Path"
    Write-Host "POST $Path"
    $json = $Body | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Invoke-RestMethod -Method Post -Uri $url -Headers $Headers -Body $bytes -ContentType "application/json; charset=utf-8"
}

function Invoke-SmokeAudioPost {
    param(
        [string]$Path,
        [object]$Body,
        [hashtable]$Headers = @{}
    )
    $url = "$BaseUrl$Path"
    Write-Host "POST $Path"
    $json = $Body | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.Method = "POST"
    $request.ContentType = "application/json; charset=utf-8"
    $request.ContentLength = $bytes.Length
    foreach ($key in $Headers.Keys) {
        $request.Headers[$key] = [string]$Headers[$key]
    }

    $requestStream = $request.GetRequestStream()
    try {
        $requestStream.Write($bytes, 0, $bytes.Length)
    } finally {
        $requestStream.Dispose()
    }

    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $errorResponse = [System.Net.HttpWebResponse]$_.Exception.Response
            throw "Audio smoke failed with HTTP $([int]$errorResponse.StatusCode)."
        }
        throw
    }

    try {
        $statusCode = [int]$response.StatusCode
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            throw "Audio smoke failed with HTTP $statusCode."
        }
        $contentType = $response.ContentType
        if (-not $contentType -or -not $contentType.ToString().StartsWith("audio/mpeg")) {
            throw "Audio smoke returned unexpected content type: $contentType"
        }

        $buffer = New-Object byte[] 8192
        $totalBytes = 0
        $responseStream = $response.GetResponseStream()
        try {
            do {
                $read = $responseStream.Read($buffer, 0, $buffer.Length)
                $totalBytes += $read
            } while ($read -gt 0)
        } finally {
            $responseStream.Dispose()
        }

        if ($totalBytes -le 0) {
            throw "Audio smoke returned an empty audio response."
        }
        Write-Host "Audio smoke returned audio/mpeg bytes."
    } finally {
        $response.Dispose()
    }
}

function Invoke-SmokeCorsPreflight {
    param([string]$Origin)

    $url = "$BaseUrl/api/v1/places"
    Write-Host "OPTIONS /api/v1/places (CORS)"
    $response = Invoke-WebRequest `
        -Method Options `
        -Uri $url `
        -Headers @{
            Origin = $Origin
            "Access-Control-Request-Method" = "GET"
            "Access-Control-Request-Headers" = "Authorization, X-API-Key"
        }
    $allowOrigin = $response.Headers["Access-Control-Allow-Origin"]
    if ($allowOrigin -ne $Origin) {
        throw "CORS preflight returned unexpected allow-origin."
    }
}

Invoke-SmokeGet "/healthz"
Invoke-SmokeReadyz
Invoke-SmokeGet "/metrics"
Invoke-SmokeGet "/openapi.json"
if ($CorsOrigin) {
    Invoke-SmokeCorsPreflight -Origin $CorsOrigin
}

$clientBearerToken = if ($env:LALA_SMOKE_BEARER_TOKEN) { $env:LALA_SMOKE_BEARER_TOKEN } elseif ($env:API_BEARER_TOKEN) { $env:API_BEARER_TOKEN } else { "" }
$clientApiKey = if ($env:LALA_SMOKE_API_KEY) { $env:LALA_SMOKE_API_KEY } elseif ($env:IOS_API_KEY) { $env:IOS_API_KEY } else { "" }

if (-not $clientApiKey -and -not $clientBearerToken) {
    $vaultName = Get-VaultNameFromUrl $env:KEY_VAULT_URL
    if ($vaultName) {
        try {
            $env:IOS_API_KEY = az keyvault secret show --vault-name $vaultName --name ios-api-key --query value -o tsv
            if (-not $clientApiKey -and $env:IOS_API_KEY) {
                $clientApiKey = $env:IOS_API_KEY
            }
        } catch {
            $env:IOS_API_KEY = ""
        }
        if (-not $clientBearerToken) {
            try {
                $env:API_BEARER_TOKEN = az keyvault secret show --vault-name $vaultName --name api-bearer-token --query value -o tsv
                if ($env:API_BEARER_TOKEN) {
                    $clientBearerToken = $env:API_BEARER_TOKEN
                }
            } catch {
                $env:API_BEARER_TOKEN = ""
            }
        }
    }
}

$headers = @{}
$serverApiKeyStatus = if ($script:ReadyzChecks -and ($script:ReadyzChecks.PSObject.Properties.Name -contains "api_key")) { $script:ReadyzChecks.api_key } else { "" }
$serverBearerStatus = if ($script:ReadyzChecks -and ($script:ReadyzChecks.PSObject.Properties.Name -contains "bearer_token")) { $script:ReadyzChecks.bearer_token } else { "" }

if ($serverBearerStatus -eq "configured" -and $clientBearerToken) {
    $headers["Authorization"] = "Bearer $clientBearerToken"
} elseif ($serverApiKeyStatus -eq "configured" -and $clientApiKey) {
    $headers["X-API-Key"] = $clientApiKey
} else {
    if ($PaidDependency) {
        throw "Matching client auth is required for paid dependency smoke. Set LALA_SMOKE_BEARER_TOKEN, LALA_SMOKE_API_KEY, IOS_API_KEY, API_BEARER_TOKEN, or KEY_VAULT_URL with credentials that match /readyz."
    }
    Write-Host "Matching client auth is not available; authenticated /api/v1 smoke checks skipped."
    exit 0
}

Invoke-SmokeGet "/api/v1/places?lat=37.2636&lng=127.0286&radius_m=1000" -Headers $headers
Invoke-SmokeGet "/api/v1/weather?lat=37.2636&lng=127.0286" -Headers $headers
Invoke-SmokeGet "/api/v1/plans/intervention?lat=37.2636&lng=127.0286&radius_m=1000" -Headers $headers
Invoke-SmokePost "/api/v1/docents/script" -Headers $headers -Body @{
    place_id = "skeleton-suwon-hwaseong"
    category = "attraction"
    language = "ko"
    mode = "brief"
} | Out-Null

if ($PaidDependency) {
    Write-Host "Paid dependency smoke requested. Start the API with -EnableLiveAI and -EnableLiveSpeech before running this check."
    $scriptResult = Invoke-SmokePost "/api/v1/docents/script" -Headers $headers -Body @{
        place_id = "paid-smoke-suwon"
        category = "attraction"
        language = "ko"
        mode = "brief"
    }
    if ($scriptResult.data.source -ne "azure_openai") {
        throw "Expected Azure OpenAI script source, got $($scriptResult.data.source)."
    }
    if (-not $scriptResult.data.script) {
        throw "Azure OpenAI script smoke returned an empty script."
    }
    Invoke-SmokeAudioPost "/api/v1/docents/audio" -Headers $headers -Body @{
        script = $scriptResult.data.script
        language = "ko"
    }
}

Write-Host "LALA-next API smoke completed."
