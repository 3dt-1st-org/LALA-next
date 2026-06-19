variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "name" {
  description = "Azure Container Registry name."
  type        = string
}

variable "sku" {
  description = "Azure Container Registry SKU."
  type        = string
  default     = "Basic"
}

variable "runtime_principal_id" {
  description = "Managed identity principal id that should receive AcrPull."
  type        = string
  default     = null
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
