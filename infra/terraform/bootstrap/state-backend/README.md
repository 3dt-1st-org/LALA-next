# LALA Terraform State Backend Bootstrap

This root module prepares only the Azure Blob backend for Terraform state. It
does not create the LALA app runtime, PostgreSQL data plane, or Key Vault
secret values.

## Resources

- Optional dedicated resource group for tfstate
- StorageV2 account with Azure AD auth
- Private blob container for `.tfstate`
- Optional `CanNotDelete` lock on the storage account
- Least-privilege RBAC for operators and GitHub Actions workload identities

## State Keys

- Bootstrap: `lala/bootstrap/tfstate-backend.tfstate`
- Dev: `lala/dev/terraform.tfstate`
- Prod: `lala/prod/terraform.tfstate`

## Local Validation

```bash
cd infra/terraform/bootstrap/state-backend
terraform init -backend=false
terraform validate
```

## Backend Config Example

```hcl
resource_group_name  = "rg-lala-shared-tfstate"
storage_account_name = "replacewithgloballyuniquesa"
container_name       = "tfstate"
key                  = "lala/dev/terraform.tfstate"
use_azuread_auth     = true
```

Initialize the real backend only after the storage account, container, and
RBAC bootstrap have been approved and applied.
