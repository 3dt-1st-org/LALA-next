# Azure Dev Deployment

LALA keeps the public Flutter Web app on its existing web hosting path for now,
while the shared backend and database move to Azure for team development.

## What Moves To Azure

- FastAPI backend: Azure Container Apps
- Shared PostgreSQL database: Azure Database for PostgreSQL Flexible Server
- Secret source: Azure Key Vault
- API image registry: Azure Container Registry
- Logs and telemetry: Log Analytics and Application Insights

## What Stays Outside Azure For Now

- Flutter Web public site deployment remains separate so the current
  `lala-next.cloud` flow can keep working while `api.lala-next.cloud` is moved.
- Mobile simulator and local development keep using local API overrides.
- Worker jobs remain dry-run contracts until the shared DB/API path is stable.

## Automatic Dev Deployment

The workflow at `.github/workflows/azure-dev-deploy.yml` deploys when commits
land on the `dev` branch. It uses GitHub OIDC with `azure/login@v2`, so no
long-lived Azure credential JSON should be stored in GitHub.

Required GitHub Environment: `dev`

Variables:

- `AZURE_CLIENT_ID`
- `AZURE_DEPLOY_PRINCIPAL_OBJECT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_LOCATION`
- `LALA_ENVIRONMENT_NAME`
- `POSTGRES_ADMIN_LOGIN`
- `CORS_ALLOW_ORIGINS`

Secret:

- `AZURE_POSTGRES_ADMIN_PASSWORD`

## Runtime Secret Flow

The Bicep deployment writes the generated PostgreSQL connection string to Key
Vault as `db-dsn`. The API container receives only:

- `KEY_VAULT_URL`
- `LALA_ALLOWED_KEY_VAULT_HOSTS`
- `AZURE_CLIENT_ID`

The API then loads `DB_DSN` through managed identity. The deployment workflow may
read the same secret during schema migration, but masks it and never prints it.

The deploy workflow also receives `AZURE_DEPLOY_PRINCIPAL_OBJECT_ID` so the
Bicep template can grant the GitHub OIDC service principal `AcrPush` and Key
Vault secret access without storing broad Azure credentials in GitHub.

For the first local Azure CLI provisioning, `enableRoleAssignments=true` creates
the runtime RBAC bindings. The GitHub `dev` workflow passes
`enableRoleAssignments=false` so the deploy principal can redeploy app
configuration without needing broad role-assignment write permission.

## Safety Boundary

This deployment lane is for shared dev, not production.

- Public DB access is restricted to Azure services plus a short-lived GitHub
  runner firewall rule during schema migration.
- Production should use private networking, separate staging/prod resource
  groups, stricter database identities, backup policy review, and explicit
  DNS cutover planning.
- Live resource names and subscription identifiers must stay out of tracked
  Markdown. Put them in GitHub environment variables, Azure, or local runbooks.
