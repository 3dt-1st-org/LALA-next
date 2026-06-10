param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [switch]$PaidDependency
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
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
    Invoke-RestMethod -Method Post -Uri $url -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 8) -ContentType "application/json" | Out-Null
}

Invoke-SmokeGet "/healthz"
Invoke-SmokeGet "/readyz"

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
}

if ($PaidDependency) {
    Write-Host "Paid dependency smoke is reserved for future Azure OpenAI/Speech live checks."
}

Write-Host "LALA-next API smoke completed."
