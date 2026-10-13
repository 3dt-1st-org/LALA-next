targetScope = 'resourceGroup'

@description('Short product name used in resource names.')
@minLength(2)
@maxLength(12)
param appName string = 'lala'

@description('New managed environment; independent from the retired dev tenant.')
@allowed(['staging', 'prod'])
param environmentName string = 'staging'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Keep false for infrastructure bootstrap. Enable only after DB roles, schema, auth and image checks.')
param deployApi bool = false

@description('Reviewed immutable ACR image (registry/lala-api@sha256:digest). Never use a demo image.')
param containerImage string = ''

@description('Comma-separated frontend origins allowed by the FastAPI CORS layer.')
param corsAllowOrigins string = 'https://lala-next.cloud,https://www.lala-next.cloud'

@description('Temporary contest access switch for public API reads without client auth. Keep true only while the contest review build must be accessible without login.')
param publicContestAccess bool = false

@description('Switch for unauthenticated static snapshot fallback. Keep false for Azure dev/prod/review runtimes.')
param staticSnapshotFallback bool = false

@description('Enable OpenAI-backed docent generation only after separate paid-use approval.')
param enableLiveAI bool = false

@description('Enable Azure Speech MP3 generation when Speech secrets are present in the LALA Key Vault. Keep false unless paid speech smoke is intended.')
param enableLiveSpeech bool = false

@description('Object id of the GitHub OIDC service principal. Used for ACR push only; secret bootstrap is a separate operator responsibility.')
param deploymentPrincipalObjectId string = ''

@description('Create RBAC role assignments. Use true for the first local deployment by an owner; use false from GitHub OIDC if role assignment write is not delegated.')
param enableRoleAssignments bool = true

@description('PostgreSQL administrator login for bootstrap only; never used by the API.')
param postgresAdminLogin string = 'lalaadmin'

@secure()
@description('PostgreSQL administrator password. Keep outside command arguments and source files.')
param postgresAdminPassword string

@description('Separate least-privilege application database login; create this role before API rollout.')
param postgresAppLogin string = 'lala_api'

@secure()
@description('Application password. Keep outside command arguments and source files.')
param postgresAppPassword string

@description('Match the source major version for initial migration; upgrade separately.')
param postgresVersion string = '15'

@description('Non-overlapping VNet prefix; confirm against existing networks before applying.')
param vnetPrefix string = '10.90.0.0/16'
param containerAppsSubnetPrefix string = '10.90.0.0/23'
param postgresSubnetPrefix string = '10.90.2.0/24'

@minValue(7)
@maxValue(35)
param backupRetentionDays int = 14

@minValue(0)
@maxValue(10)
param apiMinReplicas int = 1
@minValue(1)
@maxValue(10)
param apiMaxReplicas int = 3

@secure()
@description('Static transition bearer token for API client authentication. Keep outside command arguments and source files.')
param apiBearerToken string = ''

@description('Optional API custom domain hostname. Leave empty for local/ephemeral deployments.')
param apiCustomDomainName string = ''

@description('Optional Azure Container Apps managed certificate resource id for the API custom domain.')
param apiCustomDomainCertificateId string = ''

@description('Application database name.')
param postgresDatabaseName string = 'lala'

@description('PostgreSQL Flexible Server SKU for the shared dev database.')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL Flexible Server SKU tier.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param postgresSkuTier string = 'Burstable'

@description('PostgreSQL storage size in GiB.')
@minValue(32)
param postgresStorageSizeGB int = 32

@description('Resource tags applied to deployable Azure resources.')
param tags object = {}

@description('Globally unique Azure Container Registry name. Must use only letters and digits.')
@minLength(5)
@maxLength(50)
param containerRegistryName string = toLower(replace('lala${environmentName}${uniqueString(resourceGroup().id, appName, environmentName)}', '-', ''))

var suffix = toLower(uniqueString(resourceGroup().id, appName, environmentName))
var baseName = '${appName}-${environmentName}-${suffix}'
var logAnalyticsName = '${baseName}-logs'
var appInsightsName = '${baseName}-appi'
var managedEnvironmentName = '${baseName}-cae'
var apiIdentityName = '${baseName}-api-id'
var apiContainerAppName = '${baseName}-api'
var keyVaultName = take('${appName}-${environmentName}-kv-${suffix}', 24)
var postgresServerName = take('${appName}-${environmentName}-pg-${suffix}', 63)
var keyVaultHost = replace(replace(keyVault.properties.vaultUri, 'https://', ''), '/', '')
var dbScheme = 'postgresql://'
var encodedPostgresAppPassword = uriComponent(postgresAppPassword)
var dbDsn = '${dbScheme}${postgresAppLogin}:${encodedPostgresAppPassword}@${postgres.properties.fullyQualifiedDomainName}:5432/${postgresDatabaseName}?sslmode=require'
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var acrPushRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var apiIngressBase = {
  external: true
  allowInsecure: false
  targetPort: 8000
  transport: 'auto'
}
var apiCustomDomains = empty(apiCustomDomainName) ? [] : (empty(apiCustomDomainCertificateId) ? [
  {
    name: apiCustomDomainName
    bindingType: 'Disabled'
  }
] : [
  {
    name: apiCustomDomainName
    bindingType: 'SniEnabled'
    certificateId: apiCustomDomainCertificateId
  }
])
var apiIngressCustomDomain = empty(apiCustomDomainName) ? {} : {
  customDomains: apiCustomDomains
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  tags: tags
  properties: {
    adminUserEnabled: false
  }
}

resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: apiIdentityName
  location: location
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

resource kvSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRoleAssignments) {
  name: guid(keyVault.id, apiIdentity.id, 'key-vault-secrets-user')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${baseName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetPrefix]
    }
    subnets: [
      {
        name: 'containerapps'
        properties: {
          addressPrefix: containerAppsSubnetPrefix
          delegations: [{name: 'containerapps', properties: {serviceName: 'Microsoft.App/environments'}}]
        }
      }
      {
        name: 'postgres'
        properties: {
          addressPrefix: postgresSubnetPrefix
          delegations: [{name: 'postgres', properties: {serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'}}]
        }
      }
    ]
  }
}

resource privateDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${baseName}.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDns
  name: '${baseName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {id: vnet.id}
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: postgresSkuName
    tier: postgresSkuTier
  }
  properties: {
    version: postgresVersion
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    storage: {
      storageSizeGB: postgresStorageSizeGB
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    network: {
      publicNetworkAccess: 'Disabled'
      delegatedSubnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'postgres')
      privateDnsZoneArmResourceId: privateDns.id
    }
  }
  dependsOn: [privateDnsLink]
}

resource postgresExtensions 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgres
  name: 'azure.extensions'
  properties: {
    value: 'POSTGIS,VECTOR,PGCRYPTO'
    source: 'user-override'
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgres
  name: postgresDatabaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
  dependsOn: [
    postgresExtensions
  ]
}

resource dbDsnSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-dsn'
  properties: {
    value: dbDsn
  }
  dependsOn: [
    postgresDatabase
  ]
}

resource corsSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cors-allow-origins'
  properties: {
    value: corsAllowOrigins
  }
}

resource apiBearerTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(apiBearerToken)) {
  parent: keyVault
  name: 'api-bearer-token'
  properties: {
    value: apiBearerToken
  }
}

resource apiAcrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRoleAssignments) {
  name: guid(acr.id, apiIdentity.id, 'acr-pull')
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deployAcrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRoleAssignments && !empty(deploymentPrincipalObjectId)) {
  name: guid(acr.id, deploymentPrincipalObjectId, 'deploy-acr-push')
  scope: acr
  properties: {
    roleDefinitionId: acrPushRoleDefinitionId
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: managedEnvironmentName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'containerapps')
      internal: false
    }
    workloadProfiles: [{name: 'Consumption', workloadProfileType: 'Consumption'}]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource apiContainerApp 'Microsoft.App/containerApps@2024-03-01' = if (deployApi) {
  name: apiContainerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${apiIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: union(apiIngressBase, apiIngressCustomDomain)
      registries: [
        {
          server: acr.properties.loginServer
          identity: apiIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          env: [
            {
              name: 'LALA_RUNTIME_PROFILE'
              value: 'api'
            }
            {
              name: 'LALA_SECRET_BACKEND'
              value: 'azure'
            }
            {
              name: 'PORT'
              value: '8000'
            }
            {
              name: 'KEY_VAULT_URL'
              value: keyVault.properties.vaultUri
            }
            {
              name: 'LALA_ALLOWED_KEY_VAULT_HOSTS'
              value: keyVaultHost
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: apiIdentity.properties.clientId
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
            {
              name: 'LALA_PUBLIC_CONTEST_ACCESS'
              value: string(publicContestAccess)
            }
            {
              name: 'LALA_STATIC_SNAPSHOT_FALLBACK'
              value: string(staticSnapshotFallback)
            }
            {
              name: 'LALA_ENABLE_LIVE_AI'
              value: string(enableLiveAI)
            }
            {
              name: 'LALA_ENABLE_LIVE_SPEECH'
              value: string(enableLiveSpeech)
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {path: '/healthz', port: 8000}
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {path: '/healthz', port: 8000}
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {path: '/readyz', port: 8000}
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 6
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: apiMinReplicas
        maxReplicas: apiMaxReplicas
        rules: [
          {
            name: 'http-scale'
            http: {
              metadata: {
                concurrentRequests: '25'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    apiAcrPullRoleAssignment
    corsSecret
    dbDsnSecret
    deployAcrPushRoleAssignment
    kvSecretsUserRoleAssignment
  ]
}

output apiContainerAppName string = apiContainerAppName
output apiFqdn string = deployApi ? apiContainerApp!.properties.configuration.ingress.fqdn : ''
output containerRegistryName string = acr.name
output containerRegistryLoginServer string = acr.properties.loginServer
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output postgresServerName string = postgres.name
output postgresFqdn string = postgres.properties.fullyQualifiedDomainName
output postgresDatabaseName string = postgresDatabase.name
