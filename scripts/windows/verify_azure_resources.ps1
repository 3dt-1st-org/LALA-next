param(
    [string]$SubscriptionId = $(if ($env:LALA_AZURE_SUBSCRIPTION_ID) { $env:LALA_AZURE_SUBSCRIPTION_ID } else { "00000000-0000-0000-0000-000000000000" }),
    [string]$ResourceGroup = $(if ($env:LALA_AZURE_RESOURCE_GROUP) { $env:LALA_AZURE_RESOURCE_GROUP } else { "lala-resource-group" }),
    [string]$KeyVaultName = $(if ($env:LALA_KEY_VAULT_NAME) { $env:LALA_KEY_VAULT_NAME } else { "lala-key-vault" }),
    [string]$OpenAIAccountName = $(if ($env:LALA_AZURE_OPENAI_ACCOUNT_NAME) { $env:LALA_AZURE_OPENAI_ACCOUNT_NAME } else { "lala-openai-account" }),
    [string]$OpenAIDeploymentName = "gpt-4o-mini",
    [string]$SpeechAccountName = $(if ($env:LALA_AZURE_SPEECH_ACCOUNT_NAME) { $env:LALA_AZURE_SPEECH_ACCOUNT_NAME } else { "lala-speech-account" }),
    [string]$OnmuVaultName = $(if ($env:ONMU_KEY_VAULT_NAME) { $env:ONMU_KEY_VAULT_NAME } else { "onmu-source-vault" })
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedSecretNames = @(
    "ios-api-key",
    "azure-openai-endpoint",
    "azure-openai-key",
    "azure-openai-deployment",
    "azure-openai-api-version",
    "azure-speech-key",
    "azure-speech-region",
    "azure-speech-endpoint"
)
$OptionalSecretNames = @(
    "api-bearer-token",
    "db-dsn",
    "cors-allow-origins",
    "oauth-issuer",
    "oauth-audience",
    "oauth-jwks-url",
    "oauth-client-id",
    "oauth-required-scopes",
    "kakao-rest-api-key",
    "kakao-javascript-key",
    "kakao-redirect-uri",
    "naver-client-id",
    "naver-client-secret",
    "kopis-api-key",
    "public-data-service-key",
    "gyeonggi-data-dream-api-key"
)

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

function Assert-Equal {
    param(
        [string]$Name,
        [string]$Actual,
        [string]$Expected
    )
    if ($Actual -ne $Expected) {
        throw "$Name expected '$Expected' but got '$Actual'."
    }
}

Write-Host "Verifying LALA-next Azure resources in resource group '$ResourceGroup'."
Write-Host "Secret values are never printed by this script."

$account = Invoke-AzJson -Arguments @("account", "show", "--query", "{id:id,name:name,user:user.name}")
if ($account.id -ne $SubscriptionId) {
    Write-Host "Current Azure CLI subscription is '$($account.id)'; resource checks are scoped to '$SubscriptionId'."
}

if ($KeyVaultName -eq $OnmuVaultName) {
    throw "LALA-next Key Vault name must not match the ONMU vault name."
}

$vault = Invoke-AzJson -Arguments @(
    "keyvault", "show",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroup,
    "--name", $KeyVaultName,
    "--query", "{name:name,resourceGroup:resourceGroup,location:location,vaultUri:properties.vaultUri,enableRbacAuthorization:properties.enableRbacAuthorization}"
)
Assert-Equal -Name "Key Vault name" -Actual $vault.name -Expected $KeyVaultName
Assert-Equal -Name "Key Vault resource group" -Actual $vault.resourceGroup -Expected $ResourceGroup
Write-Host "Key Vault verified: $($vault.name) ($($vault.vaultUri))"

$secretNames = @(
    Invoke-AzJson -Arguments @(
        "keyvault", "secret", "list",
        "--subscription", $SubscriptionId,
        "--vault-name", $KeyVaultName,
        "--query", "[].name"
    )
)
$missingSecrets = @($ExpectedSecretNames | Where-Object { $secretNames -notcontains $_ })
if ($missingSecrets.Count -gt 0) {
    throw "LALA-next Key Vault is missing expected secret names: $($missingSecrets -join ', ')"
}
Write-Host "Key Vault secret names verified: $($ExpectedSecretNames.Count) expected names present."
$presentOptionalSecrets = @($OptionalSecretNames | Where-Object { $secretNames -contains $_ })
if ($presentOptionalSecrets.Count -gt 0) {
    Write-Host "Optional Key Vault secret names present: $($presentOptionalSecrets -join ', ')"
} else {
    Write-Host "Optional Key Vault secret names are not present yet: $($OptionalSecretNames -join ', ')"
}

$openAI = Invoke-AzJson -Arguments @(
    "cognitiveservices", "account", "show",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroup,
    "--name", $OpenAIAccountName,
    "--query", "{name:name,kind:kind,sku:sku.name,location:location,endpoint:properties.endpoint}"
)
Assert-Equal -Name "Azure OpenAI account name" -Actual $openAI.name -Expected $OpenAIAccountName
Assert-Equal -Name "Azure OpenAI kind" -Actual $openAI.kind -Expected "OpenAI"
Write-Host "Azure OpenAI account verified: $($openAI.name) ($($openAI.endpoint))"

$deployments = @(
    Invoke-AzJson -Arguments @(
        "cognitiveservices", "account", "deployment", "list",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--name", $OpenAIAccountName,
        "--query", "[].{name:name,model:properties.model.name,version:properties.model.version,provisioningState:properties.provisioningState}"
    )
)
$deployment = $deployments | Where-Object { $_.name -eq $OpenAIDeploymentName } | Select-Object -First 1
if (-not $deployment) {
    throw "Azure OpenAI deployment '$OpenAIDeploymentName' was not found."
}
Assert-Equal -Name "Azure OpenAI deployment state" -Actual $deployment.provisioningState -Expected "Succeeded"
Write-Host "Azure OpenAI deployment verified: $($deployment.name) model=$($deployment.model) version=$($deployment.version)"

$speech = Invoke-AzJson -Arguments @(
    "cognitiveservices", "account", "show",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroup,
    "--name", $SpeechAccountName,
    "--query", "{name:name,kind:kind,sku:sku.name,location:location,endpoint:properties.endpoint}"
)
Assert-Equal -Name "Azure Speech account name" -Actual $speech.name -Expected $SpeechAccountName
Assert-Equal -Name "Azure Speech kind" -Actual $speech.kind -Expected "SpeechServices"
Write-Host "Azure Speech account verified: $($speech.name) ($($speech.endpoint))"

try {
    $onmuVault = Invoke-AzJson -Arguments @(
        "keyvault", "show",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--name", $OnmuVaultName,
        "--query", "{name:name,vaultUri:properties.vaultUri}"
    )
    Write-Host "ONMU vault also exists in this resource group, but is not used by LALA-next: $($onmuVault.name)"
} catch {
    Write-Host "ONMU vault comparison skipped: $($_.Exception.Message)"
}

Write-Host "LALA-next Azure resource verification completed."
