variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant id."
  type        = string
}

variable "key_vault_name" {
  description = "Key Vault name."
  type        = string
}

variable "runtime_identity_name" {
  description = "User-assigned managed identity name used by the runtime."
  type        = string
}

variable "deployment_principal_object_id" {
  description = "Microsoft Entra object id for the deployment principal."
  type        = string
  default     = null
}

variable "enable_role_assignments" {
  description = "Create runtime and deployment role assignments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
}
