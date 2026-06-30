param(
    [string]$HostName = "0.0.0.0",
    [int]$Port = 8080,
    [string]$Python = "",
    [string]$EnvFile = "",
    [string]$KeyVaultUrl = "",
    [string]$AccessLogPath = "",
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

if ($KeyVaultUrl) {
    [Environment]::SetEnvironmentVariable("KEY_VAULT_URL", $KeyVaultUrl, "Process")
}

if (-not $EnvFile) {
    $EnvFile = Join-Path $RepoRoot ".env"
}
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

if ($AccessLogPath) {
    [Environment]::SetEnvironmentVariable("LALA_ACCESS_LOG_PATH", $AccessLogPath, "Process")
}

function Get-LalaVaultNameFromUrl {
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

function Set-SecretEnvIfMissing {
    param(
        [string]$VaultName,
        [string]$EnvName,
        [string]$SecretName
    )
    if ([Environment]::GetEnvironmentVariable($EnvName, "Process")) {
        return
    }
    try {
        $value = az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) {
            [Environment]::SetEnvironmentVariable($EnvName, $value, "Process")
        }
    } catch {
        return
    }
}

function Get-EnvStatus {
    param([string]$EnvName)
    if ([Environment]::GetEnvironmentVariable($EnvName, "Process")) {
        return "configured"
    }
    return "missing"
}

$EffectiveKeyVaultUrl = [Environment]::GetEnvironmentVariable("KEY_VAULT_URL", "Process")
if ($EffectiveKeyVaultUrl) {
    $VaultName = Get-LalaVaultNameFromUrl $EffectiveKeyVaultUrl
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "IOS_API_KEY" -SecretName "ios-api-key"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "API_BEARER_TOKEN" -SecretName "api-bearer-token"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "OAUTH_ISSUER" -SecretName "oauth-issuer"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "OAUTH_AUDIENCE" -SecretName "oauth-audience"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "OAUTH_JWKS_URL" -SecretName "oauth-jwks-url"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "OAUTH_CLIENT_ID" -SecretName "oauth-client-id"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "OAUTH_REQUIRED_SCOPES" -SecretName "oauth-required-scopes"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_OPENAI_ENDPOINT" -SecretName "azure-openai-endpoint"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_OPENAI_KEY" -SecretName "azure-openai-key"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_OPENAI_DEPLOYMENT" -SecretName "azure-openai-deployment"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_OPENAI_API_VERSION" -SecretName "azure-openai-api-version"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_SPEECH_KEY" -SecretName "azure-speech-key"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_SPEECH_REGION" -SecretName "azure-speech-region"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "AZURE_SPEECH_ENDPOINT" -SecretName "azure-speech-endpoint"
    Set-SecretEnvIfMissing -VaultName $VaultName -EnvName "CORS_ALLOW_ORIGINS" -SecretName "cors-allow-origins"
    Write-Host "Key Vault secret preload: api_key=$(Get-EnvStatus 'IOS_API_KEY'), bearer_token=$(Get-EnvStatus 'API_BEARER_TOKEN'), oauth_issuer=$(Get-EnvStatus 'OAUTH_ISSUER'), oauth_client_id=$(Get-EnvStatus 'OAUTH_CLIENT_ID'), openai_key=$(Get-EnvStatus 'AZURE_OPENAI_KEY'), speech_key=$(Get-EnvStatus 'AZURE_SPEECH_KEY'), cors_origins=$(Get-EnvStatus 'CORS_ALLOW_ORIGINS')"
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
Write-Host "JSONL access log: $(Get-EnvStatus 'LALA_ACCESS_LOG_PATH')"
if ($EnableLiveAI) {
    Write-Host "Live Azure OpenAI generation: enabled"
}
if ($EnableLiveSpeech) {
    Write-Host "Live Azure Speech synthesis: enabled"
}

& $Python -m uvicorn apps.api.app.main:app --host $HostName --port $Port --no-access-log
if ($LASTEXITCODE -ne 0) {
    throw "uvicorn exited with code $LASTEXITCODE."
}
