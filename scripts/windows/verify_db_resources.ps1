param(
    [string]$SubscriptionId = $(if ($env:LALA_AZURE_SUBSCRIPTION_ID) { $env:LALA_AZURE_SUBSCRIPTION_ID } else { "00000000-0000-0000-0000-000000000000" }),
    [string]$ResourceGroup = $(if ($env:LALA_AZURE_RESOURCE_GROUP) { $env:LALA_AZURE_RESOURCE_GROUP } else { "lala-resource-group" }),
    [string]$KeyVaultName = $(if ($env:LALA_KEY_VAULT_NAME) { $env:LALA_KEY_VAULT_NAME } else { "lala-key-vault" }),
    [string]$PostgresServerName = "",
    [string]$DatabaseName = "lala",
    [switch]$RequireDatabase
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-AzJson {
    param([string[]]$Arguments)

    $az = Get-Command az -ErrorAction SilentlyContinue
    if (-not $az) {
        throw "Azure CLI is required. Install az CLI and run az login."
    }
    $azCommand = if ($az.Source) { $az.Source } else { $az.Name }

    $errorFile = New-TemporaryFile
    try {
        $raw = & $azCommand @Arguments -o json 2>$errorFile
        $exitCode = $LASTEXITCODE
        $stderr = Get-Content $errorFile -Raw
        if ($exitCode -ne 0) {
            throw "az $($Arguments -join ' ') failed. $stderr"
        }
        if (-not $raw) {
            return $null
        }
        return ($raw | Out-String | ConvertFrom-Json)
    } finally {
        Remove-Item $errorFile -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Ready {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition -and $RequireDatabase) {
        throw $Message
    }
    if (-not $Condition) {
        Write-Host "DB rollout not ready: $Message"
    }
}

Write-Host "Verifying LALA-next PostgreSQL rollout readiness in resource group '$ResourceGroup'."
Write-Host "Secret values are never printed by this script."

$account = Invoke-AzJson -Arguments @("account", "show", "--query", "{id:id,name:name,user:user.name}")
if ($account.id -ne $SubscriptionId) {
    Write-Host "Current Azure CLI subscription is '$($account.id)'; resource checks are scoped to '$SubscriptionId'."
}

$vault = Invoke-AzJson -Arguments @(
    "keyvault", "show",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroup,
    "--name", $KeyVaultName,
    "--query", "{name:name,resourceGroup:resourceGroup,vaultUri:properties.vaultUri}"
)
if ($vault.name -ne $KeyVaultName) {
    throw "Expected LALA-next Key Vault '$KeyVaultName' but got '$($vault.name)'."
}
Write-Host "Key Vault verified: $($vault.name) ($($vault.vaultUri))"

$secretNames = @(
    Invoke-AzJson -Arguments @(
        "keyvault", "secret", "list",
        "--subscription", $SubscriptionId,
        "--vault-name", $KeyVaultName,
        "--query", "[].name"
    )
)
$hasDbDsn = $secretNames -contains "db-dsn"
if ($hasDbDsn) {
    Write-Host "Key Vault secret name verified: db-dsn"
} else {
    Assert-Ready -Condition $false -Message "Key Vault '$KeyVaultName' is missing secret name 'db-dsn'."
}

$servers = @(
    Invoke-AzJson -Arguments @(
        "postgres", "flexible-server", "list",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--query", "[].{name:name,resourceGroup:resourceGroup,location:location,state:state,fullyQualifiedDomainName:fullyQualifiedDomainName}"
    )
)
if ($servers.Count -eq 0) {
    Assert-Ready -Condition $false -Message "No PostgreSQL Flexible Server exists in resource group '$ResourceGroup'."
    Write-Host "LALA-next PostgreSQL rollout readiness completed."
    exit 0
}

$server = $null
if ($PostgresServerName) {
    $server = $servers | Where-Object { $_.name -eq $PostgresServerName } | Select-Object -First 1
    Assert-Ready -Condition ($null -ne $server) -Message "PostgreSQL server '$PostgresServerName' was not found."
} elseif ($servers.Count -eq 1) {
    $server = $servers | Select-Object -First 1
} else {
    $serverNames = ($servers | ForEach-Object { $_.name }) -join ", "
    Assert-Ready -Condition $false -Message "Multiple PostgreSQL servers found; pass -PostgresServerName. Found: $serverNames"
}

if ($null -eq $server) {
    Write-Host "LALA-next PostgreSQL rollout readiness completed."
    exit 0
}

Write-Host "PostgreSQL server verified: $($server.name) state=$($server.state) fqdn=$($server.fullyQualifiedDomainName)"
Assert-Ready -Condition ($server.state -eq "Ready") -Message "PostgreSQL server '$($server.name)' is not Ready; state=$($server.state)."

$databases = @(
    Invoke-AzJson -Arguments @(
        "postgres", "flexible-server", "db", "list",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--server-name", $server.name,
        "--query", "[].name"
    )
)
$hasDatabase = $databases -contains $DatabaseName
if ($hasDatabase) {
    Write-Host "PostgreSQL database verified: $DatabaseName"
} else {
    Assert-Ready -Condition $false -Message "Database '$DatabaseName' was not found on server '$($server.name)'."
}

try {
    $extensionParameter = Invoke-AzJson -Arguments @(
        "postgres", "flexible-server", "parameter", "show",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--server-name", $server.name,
        "--name", "azure.extensions",
        "--query", "{name:name,value:value}"
    )
    $extensionValue = [string]$extensionParameter.value
    Write-Host "PostgreSQL azure.extensions allowlist: $extensionValue"
    foreach ($extension in @("POSTGIS", "VECTOR", "PGCRYPTO")) {
        Assert-Ready -Condition ($extensionValue.ToUpperInvariant().Contains($extension)) -Message "Server '$($server.name)' azure.extensions does not include '$extension'."
    }
} catch {
    Assert-Ready -Condition $false -Message "Could not verify azure.extensions on server '$($server.name)': $($_.Exception.Message)"
}

if ($RequireDatabase) {
    Write-Host "LALA-next PostgreSQL rollout readiness passed."
} else {
    Write-Host "LALA-next PostgreSQL rollout readiness completed."
}
