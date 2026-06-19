variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "server_name" {
  description = "PostgreSQL Flexible Server name."
  type        = string
}

variable "database_name" {
  description = "Application database name."
  type        = string
}

variable "administrator_login" {
  description = "PostgreSQL administrator login."
  type        = string
}

variable "administrator_password" {
  description = "PostgreSQL administrator password."
  type        = string
  sensitive   = true
}

variable "postgres_version" {
  description = "PostgreSQL Flexible Server version."
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "PostgreSQL Flexible Server SKU name."
  type        = string
}

variable "storage_mb" {
  description = "PostgreSQL storage size in MiB."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "PostgreSQL backup retention days."
  type        = number
  default     = 7
}

variable "zone" {
  description = "Optional availability zone."
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Expose PostgreSQL over the public endpoint."
  type        = bool
  default     = true
}

variable "enabled_extensions" {
  description = "Extensions enabled through the azure.extensions server configuration."
  type        = list(string)
  default     = []
}

variable "create_allow_azure_services_firewall_rule" {
  description = "Create the AllowAzureServices firewall rule."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
}
