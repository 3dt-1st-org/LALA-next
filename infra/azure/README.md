# LALA Azure Dev Runtime

This folder contains the legacy Bicep deployment rail for the shared LALA dev
runtime. It is intentionally separate from the current public Flutter Web
deployment.

Terraform under
[`infra/terraform`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/infra/terraform)
is now the modular IaC source of truth. Keep this Bicep lane only as a
transitional bootstrap and rollback reference until the shared dev stack has
been fully imported and stabilized in Terraform state.

## Target Architecture

- Azure Container Apps runs the FastAPI API.
- Azure Database for PostgreSQL Flexible Server stores shared canonical data.
- Azure Key Vault stores `db-dsn` and other application secrets.
- Azure Container Registry stores the API container image.
- Log Analytics and Application Insights receive API runtime telemetry.
- GitHub Actions deploys from the `dev` branch using Azure OIDC.

## One-Time GitHub Environment

Create a GitHub Environment named `dev`.

Environment variables:

- `AZURE_CLIENT_ID`
- `AZURE_DEPLOY_PRINCIPAL_OBJECT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_LOCATION` such as `koreacentral`
- `LALA_ENVIRONMENT_NAME` such as `dev`
- `POSTGRES_ADMIN_LOGIN` such as `lalaadmin`
- `CORS_ALLOW_ORIGINS` such as `https://lala-next.cloud,https://www.lala-next.cloud`
- `AZURE_API_CUSTOM_DOMAIN_NAME` such as `api.lala-next.cloud`
- `AZURE_API_CUSTOM_DOMAIN_CERTIFICATE_ID` when the custom domain is already bound

Environment secrets:

- `AZURE_POSTGRES_ADMIN_PASSWORD`
- `AZURE_API_BEARER_TOKEN`

OIDC removes the need for a long-lived Azure credential secret in GitHub. The
PostgreSQL admin password is still needed for the initial dev database
provisioning path unless an existing database and Key Vault secret are supplied
outside this workflow.

`AZURE_CLIENT_ID` is the application/client id used by `azure/login`.
`AZURE_DEPLOY_PRINCIPAL_OBJECT_ID` is the service principal object id used by
the Bicep template to grant ACR push and Key Vault secret migration rights.

## One-Time Azure OIDC Setup

Create an Entra app registration or user-assigned identity for GitHub Actions,
grant it least-privilege deployment rights on the target resource group, then add
a federated credential for the GitHub Environment named `dev`:

```bash
az ad app federated-credential create \
  --id "<application-client-id-or-object-id>" \
  --parameters '{
    "name": "lala-dev-environment",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:3dt-1st-org/LALA-next:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

The deploy principal needs permission to create or update:

- Resource group deployments
- Azure Container Apps and managed environments
- Azure Container Registry
- Azure Key Vault and secrets
- Azure Database for PostgreSQL Flexible Server
- Managed identities and role assignments
- Log Analytics and Application Insights

The principal must be able to create role assignments in the target resource
group because the template grants runtime identities and the deploy principal
the least privileges needed after provisioning.

## Deploy Flow

`.github/workflows/azure-dev-deploy.yml` runs on pushes to `dev`.

1. Syncs Python dependencies with `uv`.
2. Runs the API safety contracts.
3. Deploys the Bicep template.
4. Builds and pushes the API image to ACR.
5. Updates the Container App revision.
6. Runs a required `/healthz` smoke check and a non-blocking `/readyz` probe.

The dev deployment workflow intentionally does not apply PostgreSQL schema or
seed data. Shared database changes should be reviewed and run separately with
SQL tooling or the guarded canonical SQL runbooks.

For the Terraform-first lane, use:

- [`docs/operations/azure-dev-deployment.md`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/docs/operations/azure-dev-deployment.md)
- [`docs/operations/azure-terraform-state-backend.md`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/docs/operations/azure-terraform-state-backend.md)

## Notes

- The app reads `DB_DSN` and `api-bearer-token` from Key Vault at runtime
  through `KEY_VAULT_URL`.
- `LALA_ALLOWED_KEY_VAULT_HOSTS` is set to the generated LALA vault host so the
  API cannot accidentally read ONMU or unrelated vaults.
- `LALA_PUBLIC_DEMO_MODE` is explicitly disabled for Azure dev, production, and
  review runtimes. The normal data path is PostgreSQL plus Key Vault backed by
  the official ingest, scoring, and RAG pipeline.
- Bundled static data is only an offline, read-only snapshot fallback for DB
  outage handling or isolated local checks. Do not present it as the deployed
  service's primary data path.
- The first local Azure CLI deployment should use `enableRoleAssignments=true`.
  The GitHub `dev` workflow uses `enableRoleAssignments=false` after those RBAC
  bindings exist.
- The PostgreSQL server currently uses a dev-friendly public endpoint with
  Azure-service access. For staging or production, move to private networking
  before treating it as durable hosting.
