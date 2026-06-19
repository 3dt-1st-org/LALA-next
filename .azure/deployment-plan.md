# LALA Azure Migration Deployment Plan

Status: Validated

## Goal

Migrate the shared LALA dev runtime to Azure and add a GitHub Actions workflow
that deploys the dev environment automatically when changes land on the `dev`
branch.

## Current Assumptions

- Frontend remains Flutter Web and can keep the existing public web deployment
  path while it points at the Azure-hosted API. This keeps the contest/demo URL
  stable while backend state moves to a shared team runtime.
- Backend API should run on Azure and connect to a shared Azure PostgreSQL
  database.
- Static and dynamic data jobs should run outside request handlers.
- Secrets must stay out of git and be supplied through Azure/GitHub OIDC,
  Key Vault, or deployment environment settings.

## Architecture Decision

Use Azure Container Apps for the FastAPI backend, Azure Database for PostgreSQL
Flexible Server for the shared dev database, Azure Key Vault for application
secrets, Azure Container Registry for the API image, and Log
Analytics/Application Insights for runtime telemetry.

The Flutter Web deployment is not moved in this pass. It should continue to use
its existing web hosting path and point to the Azure API once the backend smoke
is green.

## Planned Artifacts

- `infra/azure/main.bicep`: shared dev infrastructure.
- `infra/azure/api.Dockerfile`: FastAPI API container image.
- `.github/workflows/azure-dev-deploy.yml`: automatic deployment from `dev`.
- `infra/azure/README.md`: one-time GitHub/Azure setup notes.
- `docs/operations/azure-dev-deployment.md`: operational deployment summary.
- `.dockerignore`: prevents local secrets and unrelated artifacts from entering
  the image build context.

## Validation Plan

- Compile Bicep locally with `az bicep build`.
- Run the safety contract tests covering secret scanning and workflow shape.
- Run the standard Unix verification wrapper.
- Do not create or mutate live Azure resources until GitHub environment
  variables, the OIDC federated credential, and the dev branch policy are
  confirmed.

## Role Assignment Verification

- Status: Verified for the current dev deployment path.
- API user-assigned identity: `AcrPull` on the generated container registry and
  `Key Vault Secrets User` on the generated LALA vault.
- GitHub OIDC deploy principal: `AcrPush` on the generated container registry
  and `Key Vault Secrets Officer` on the generated LALA vault during first local
  provisioning.
- Workflow boundary: `dev` branch workflow passes
  `enableRoleAssignments=false` after the first local provisioning because the
  deploy principal is not delegated broad role-assignment write permission.

## Validation Proof

- 2026-06-20 KST: `az account show` confirmed an authenticated Azure CLI session.
- 2026-06-20 KST: Required Azure resource providers were registered.
- 2026-06-20 KST: Existing LALA Key Vault location was confirmed and the dev
  deployment target was aligned to the same resource group and Azure region.
- 2026-06-20 KST: `az bicep build --file infra/azure/main.bicep` succeeded.
- 2026-06-20 KST: `python -m pytest apps/api/tests/test_safety_contracts.py`
  succeeded.
- 2026-06-20 KST: `az deployment group validate` succeeded for
  `infra/azure/main.bicep` with `enableRoleAssignments=true`.
- 2026-06-20 KST: `az deployment group what-if` succeeded for
  `infra/azure/main.bicep` with `enableRoleAssignments=true`.

## Approval

Approved by the user in chat on 2026-06-20 KST for the first live Azure dev
deployment. Branch protection is intentionally not configured for development
speed.
