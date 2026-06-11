param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$KeyVaultUrl = "",
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
    if ($uri.Scheme -ne "https" -or $uri.Host.ToLowerInvariant() -ne "lala-next-kv-27db5e.vault.azure.net") {
        throw "Unsupported Key Vault URL for LALA-next: $VaultUrl"
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

Invoke-SmokeGet "/healthz"
Invoke-SmokeGet "/readyz"
Invoke-SmokeGet "/openapi.json"

if (-not $env:IOS_API_KEY) {
    $vaultName = Get-VaultNameFromUrl $env:KEY_VAULT_URL
    if ($vaultName) {
        try {
            $env:IOS_API_KEY = az keyvault secret show --vault-name $vaultName --name ios-api-key --query value -o tsv
        } catch {
            $env:IOS_API_KEY = ""
        }
    }
    if (-not $env:IOS_API_KEY) {
        if ($PaidDependency) {
            throw "IOS_API_KEY is required for paid dependency smoke. Set IOS_API_KEY or KEY_VAULT_URL with an authenticated Azure CLI session."
        }
        Write-Host "IOS_API_KEY is not available; authenticated /api/v1 smoke checks skipped."
        exit 0
    }
}

$headers = @{ "X-API-Key" = $env:IOS_API_KEY }

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
