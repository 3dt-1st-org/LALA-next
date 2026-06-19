# Azure Terraform State Backend

This runbook covers the bootstrap order for the Azure Blob backend used by
LALA Terraform.

## Scope

Use
[`infra/terraform/bootstrap/state-backend`](/Users/geondongkim/.codex/worktrees/fd5e/LALA-next/infra/terraform/bootstrap/state-backend)
to provision only:

- An optional dedicated resource group for tfstate
- A StorageV2 account
- A private blob container
- Operator and GitHub Actions RBAC

Do not use this bootstrap module to create app runtime resources, DNS records,
or Key Vault secret values.

## Recommended State Keys

- `lala/bootstrap/tfstate-backend.tfstate`
- `lala/dev/terraform.tfstate`
- `lala/prod/terraform.tfstate`

## Bootstrap Order

1. Choose whether Terraform state should live in a dedicated resource group or
   an already-approved shared infra resource group.
2. Validate the bootstrap module locally with `terraform init -backend=false`
   and `terraform validate`.
3. Apply the bootstrap module from an approved operator machine or an approved
   CI lane.
4. Record the resulting backend coordinates in the GitHub `dev` environment:
   `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`,
   `TFSTATE_KEY`.
5. Reinitialize `infra/terraform/environments/dev` against that backend and
   migrate any temporary local state.

## GitHub Environment Wiring

Keep backend coordinates in GitHub environment variables only:

- `TFSTATE_RESOURCE_GROUP`
- `TFSTATE_STORAGE_ACCOUNT`
- `TFSTATE_CONTAINER`
- `TFSTATE_KEY`

Do not commit `backend.hcl`, backend credentials, shared access keys, or local
state files.

## Notes

- Use Azure AD auth for backend access.
- Grant `Storage Blob Data Contributor` to both approved operators and the
  GitHub OIDC workload identity.
- Terraform state remains sensitive because infrastructure inputs include the
  PostgreSQL administrator password. Protect the backend as production-adjacent
  operational data even if the environment itself is only shared dev.
