# LALA Terraform

`infra/terraform` is the modular Terraform source of truth for the shared LALA
Azure runtime.

The existing Bicep deployment under [`infra/azure`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/infra/azure) stays in the repo as a transitional
bootstrap and rollback reference, but new dev/prod IaC changes should land in
Terraform first.

## Layout

- `bootstrap/state-backend`: bootstrap only for Azure Blob remote state.
- `environments/dev`: active shared-dev stack.
- `environments/prod`: production-shaped skeleton, not an approved apply target.
- `modules/*`: reusable Azure building blocks adapted from the ONMU Terraform
  structure.

## Scope

Current Terraform modules cover:

- Resource group
- Log Analytics and Application Insights
- Key Vault and runtime managed identity
- Azure Container Registry
- Azure Database for PostgreSQL Flexible Server
- Azure Container Apps managed environment and API app

Deferred expansion candidates stay documented only for now:

- Event Hubs
- Storage
- CDN or Front Door
- AI foundation services

## Secret Boundary

No live secret values, subscription ids, tenant ids, resource ids, Key Vault
URLs, or DSNs belong in tracked files.

Terraform still manages resources that require sensitive inputs, especially the
PostgreSQL administrator password. Protect the remote state backend accordingly.

The dev apply workflow is designed to keep bootstrap runtime secrets such as
`db-dsn`, `api-bearer-token`, and `cors-allow-origins` out of tracked
Terraform files. After `terraform apply`, GitHub Actions writes those values
into Key Vault via Azure CLI and restarts the Container App.

## Validation

```bash
terraform fmt -check -recursive infra/terraform

cd infra/terraform/bootstrap/state-backend
terraform init -backend=false
terraform validate

cd ../../environments/dev
terraform init -backend=false
terraform validate
```

When the Azure subscription, OIDC auth, and non-repo secrets are configured,
the PR workflow can also run `terraform plan` for `environments/dev`.
