variable "subscription_id" {
  description = "Azure subscription id for provider authentication."
  type        = string
  default     = null
}

variable "subscription_display_name" {
  description = "Human-readable subscription label for operator confirmation."
  type        = string
  default     = "LALA shared subscription"
}

variable "location" {
  description = "Azure region for the state backend resources."
  type        = string
  default     = "koreacentral"
}

variable "create_resource_group" {
  description = "Create a dedicated resource group for Terraform state."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Resource group name for the Terraform state backend."
  type        = string
  default     = "rg-lala-shared-tfstate"
}

variable "storage_account_name" {
  description = "Globally unique Storage Account name for Terraform state."
  type        = string
  default     = "lalatfstateexample01"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and numbers."
  }
}

variable "container_name" {
  description = "Private blob container name for Terraform state."
  type        = string
  default     = "tfstate"
}

variable "create_state_container" {
  description = "Create the private blob container used by the azurerm backend."
  type        = bool
  default     = true
}

variable "replication_type" {
  description = "Storage account replication type."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "enable_storage_account_delete_lock" {
  description = "Create a CanNotDelete lock on the tfstate storage account."
  type        = bool
  default     = false
}

variable "bootstrap_state_key" {
  description = "State key for the bootstrap root module."
  type        = string
  default     = "lala/bootstrap/tfstate-backend.tfstate"
}

variable "dev_state_key" {
  description = "State key for the dev environment."
  type        = string
  default     = "lala/dev/terraform.tfstate"
}

variable "prod_state_key" {
  description = "State key for the prod environment."
  type        = string
  default     = "lala/prod/terraform.tfstate"
}

variable "operator_principal_object_ids" {
  description = "Microsoft Entra object ids for human operators who can read and write tfstate blobs."
  type        = set(string)
  default     = []
}

variable "github_actions_principal_object_ids" {
  description = "Microsoft Entra object ids for GitHub Actions workload identities that can read and write tfstate blobs."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Common tags for tfstate backend resources."
  type        = map(string)
  default = {
    app        = "lala"
    env        = "shared"
    managed_by = "terraform-bootstrap"
    owner      = "lala-team"
    service    = "tfstate"
  }
}
