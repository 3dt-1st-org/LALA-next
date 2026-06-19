variable "subscription_id" {
  description = "Azure subscription id used by the azurerm provider."
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant id used by Key Vault configuration."
  type        = string
}

variable "location" {
  description = "Azure region for the production-shaped stack."
  type        = string
  default     = "koreacentral"
}

variable "app_name" {
  description = "Short application name used in Azure resource names."
  type        = string
  default     = "lala"
}

variable "environment_name" {
  description = "Logical environment name."
  type        = string
  default     = "prod"
}

variable "name_suffix" {
  description = "Stable suffix to align Terraform names with existing Azure resources."
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "Explicit resource group name. Leave null to use the naming module default."
  type        = string
  default     = null
}

variable "resource_name_overrides" {
  description = "Optional explicit Azure resource names keyed by module output name, used when importing existing resources."
  type        = map(string)
  default     = {}
}

variable "additional_tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

variable "deployment_principal_object_id" {
  description = "Microsoft Entra object id for the GitHub OIDC deployment principal."
  type        = string
  default     = null
}

variable "enable_role_assignments" {
  description = "Create role assignments for ACR pull and Key Vault secret access."
  type        = bool
  default     = false
}

variable "postgres_admin_login" {
  description = "PostgreSQL administrator login."
  type        = string
  default     = "lalaadmin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL administrator password."
  type        = string
  sensitive   = true
}

variable "postgres_database_name" {
  description = "Application database name."
  type        = string
  default     = "lala"
}

variable "postgres_version" {
  description = "PostgreSQL Flexible Server version."
  type        = string
  default     = "16"
}

variable "postgres_sku_name" {
  description = "PostgreSQL Flexible Server SKU name."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage size in MiB."
  type        = number
  default     = 32768
}

variable "postgres_backup_retention_days" {
  description = "PostgreSQL backup retention days."
  type        = number
  default     = 7
}

variable "postgres_zone" {
  description = "Optional availability zone for PostgreSQL."
  type        = string
  default     = null
}

variable "postgres_public_network_access_enabled" {
  description = "Expose PostgreSQL over the public endpoint."
  type        = bool
  default     = true
}

variable "postgres_extensions" {
  description = "Extensions enabled through the azure.extensions server configuration."
  type        = list(string)
  default     = ["POSTGIS", "VECTOR", "PGCRYPTO"]
}

variable "api_image" {
  description = "Container image used by the API Container App."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "api_image_repository_name" {
  description = "Repository name used when building and pushing the API image into ACR."
  type        = string
  default     = "lala-api"
}

variable "api_target_port" {
  description = "Application port exposed by the Container App."
  type        = number
  default     = 8000
}

variable "api_min_replicas" {
  description = "Minimum API replica count."
  type        = number
  default     = 1
}

variable "api_max_replicas" {
  description = "Maximum API replica count."
  type        = number
  default     = 3
}

variable "api_cpu" {
  description = "Container App CPU allocation."
  type        = number
  default     = 0.5
}

variable "api_memory" {
  description = "Container App memory allocation."
  type        = string
  default     = "1Gi"
}

variable "api_http_concurrent_requests" {
  description = "KEDA HTTP scale target."
  type        = number
  default     = 25
}

variable "api_ingress_transport" {
  description = "Container App ingress transport."
  type        = string
  default     = "auto"
}

variable "api_custom_domain_name" {
  description = "Optional API custom domain hostname."
  type        = string
  default     = ""
}

variable "api_custom_domain_certificate_id" {
  description = "Optional existing Container Apps environment certificate id for the API custom domain."
  type        = string
  default     = ""
}

variable "public_demo_mode" {
  description = "Compatibility switch for bundled snapshot fallback."
  type        = bool
  default     = false
}

variable "enable_live_ai" {
  description = "Enable Azure OpenAI runtime calls."
  type        = bool
  default     = false
}

variable "enable_live_speech" {
  description = "Enable Azure Speech runtime calls."
  type        = bool
  default     = false
}
