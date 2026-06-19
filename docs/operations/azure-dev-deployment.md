# Azure Dev Deployment

LALA keeps the public Flutter Web site on its existing hosting path while the
shared backend and database live on Azure for team development.

Terraform under
[`infra/terraform`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/infra/terraform)
is now the IaC source of truth for that Azure runtime. The Bicep workflow stays
in the repo as a transitional fallback and rollback rail, not the primary lane
for new infrastructure changes.

## What Moves To Azure

- FastAPI backend on Azure Container Apps
- Shared PostgreSQL on Azure Database for PostgreSQL Flexible Server
- Secret source on Azure Key Vault
- API image registry on Azure Container Registry
- Logs and telemetry on Log Analytics and Application Insights

## What Stays Outside Azure For Now

- Flutter Web public deployment remains separate so `lala-next.cloud` keeps
  working while `api.lala-next.cloud` points at Azure.
- Mobile simulator and local development keep using local API overrides.
- Worker jobs stay dry-run contracts until the shared DB and API path is stable.

## Terraform Workflow Lanes

- PR lane: `.github/workflows/terraform-plan.yml`
  This runs `terraform fmt`, `terraform validate`, and a `backend=false`
  `terraform plan` for `infra/terraform/environments/dev`.
- Dev apply lane: `.github/workflows/azure-dev-terraform-apply.yml`
  This runs safety tests, applies the dev Terraform environment, builds and
  pushes the API image, reapplies Terraform with the built image, syncs Key
  Vault bootstrap secrets, restarts the active revision, and smokes `/healthz`
  plus `/readyz`.
- Transitional fallback lane: `.github/workflows/azure-dev-deploy.yml`
  Keep this only for conservative rollback coverage while Terraform state
  bootstrap and resource adoption are being finalized.

Because the GitHub jobs use Environment `dev`, the Entra federated credential
subject must be `repo:3dt-1st-org/LALA-next:environment:dev`.

## GitHub Environment `dev`

Variables reused from the current Azure lane:

- `AZURE_CLIENT_ID`
- `AZURE_DEPLOY_PRINCIPAL_OBJECT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_LOCATION`
- `LALA_ENVIRONMENT_NAME`
- `POSTGRES_ADMIN_LOGIN`
- `CORS_ALLOW_ORIGINS`
- `AZURE_API_CUSTOM_DOMAIN_NAME`
- `AZURE_API_CUSTOM_DOMAIN_CERTIFICATE_ID`

New Terraform variables:

- `TFSTATE_RESOURCE_GROUP`
- `TFSTATE_STORAGE_ACCOUNT`
- `TFSTATE_CONTAINER`
- `TFSTATE_KEY`
- `LALA_TF_NAME_SUFFIX`
- `LALA_TF_RESOURCE_NAME_OVERRIDES_JSON`
- `LALA_TF_ADDITIONAL_TAGS_JSON`
- `LALA_TF_ENABLE_ROLE_ASSIGNMENTS`

Secrets:

- `AZURE_POSTGRES_ADMIN_PASSWORD`
- `AZURE_API_BEARER_TOKEN`

`LALA_TF_RESOURCE_NAME_OVERRIDES_JSON` should stay `{}` unless Terraform must
adopt already-created Azure resources whose names cannot be derived from the
shared naming pattern. When it is used, keep only names there, never ids or
URLs.

## Runtime Secret Flow

The API container itself receives only non-secret bootstrap values such as:

- `KEY_VAULT_URL`
- `LALA_ALLOWED_KEY_VAULT_HOSTS`
- `AZURE_CLIENT_ID`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`

After Terraform creates or updates the infrastructure, the dev apply workflow
writes the bootstrap runtime secrets into the LALA-owned Key Vault with Azure
CLI:

- `db-dsn`
- `api-bearer-token`
- `cors-allow-origins`

The workflow then restarts the active Container App revision so the runtime
reloads the fresh Key Vault values. This keeps those bootstrap secret values out
of tracked Terraform files and out of GitHub logs.

Terraform still manages sensitive infrastructure inputs such as the PostgreSQL
administrator password, so protect the remote state backend accordingly.

## Apply Order

1. Bootstrap the remote state backend with
   [`infra/terraform/bootstrap/state-backend`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/infra/terraform/bootstrap/state-backend).
2. Store backend coordinates in the `dev` GitHub environment as `TFSTATE_*`
   variables.
3. Let PRs run `terraform-plan.yml` until the dev plan matches the current
   shared runtime closely enough to adopt.
4. On `dev` pushes, let `azure-dev-terraform-apply.yml` do:
   `terraform apply` with a public bootstrap image, ACR build and push, a second
   `terraform apply` with the real image, Key Vault bootstrap secret sync, then
   revision restart and smoke tests.
5. Keep canonical SQL, ingest, scoring, and RAG rollout as separate reviewed
   operations. They are not part of every infrastructure apply.

## Safety Boundary

This lane is for shared dev, not durable production.

- `LALA_PUBLIC_DEMO_MODE` stays `false` for dev, review, and production.
- The normal deployed path is PostgreSQL plus Key Vault plus reviewed ingest,
  scoring, and RAG jobs.
- Bundled static data is only a limited read-only fallback for DB outage
  handling or isolated local checks.
- Public DB access, DNS, and identity remain intentionally conservative until a
  stricter production hardening phase exists.
