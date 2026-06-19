variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "container_app_environment_name" {
  description = "Container Apps managed environment name."
  type        = string
}

variable "api_container_app_name" {
  description = "API Container App name."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace id."
  type        = string
}

variable "runtime_identity_id" {
  description = "User-assigned managed identity id used by the runtime."
  type        = string
}

variable "runtime_identity_client_id" {
  description = "User-assigned managed identity client id used by the runtime."
  type        = string
}

variable "registry_server" {
  description = "Azure Container Registry login server."
  type        = string
}

variable "api_image" {
  description = "Container image for the API app."
  type        = string
}

variable "key_vault_url" {
  description = "LALA-owned Key Vault URL."
  type        = string
}

variable "allowed_key_vault_hosts" {
  description = "Comma-separated Key Vault host allowlist consumed by the runtime."
  type        = string
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string."
  type        = string
  sensitive   = true
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

variable "api_target_port" {
  description = "Application port exposed by the Container App."
  type        = number
  default     = 8000
}

variable "api_min_replicas" {
  description = "Minimum API replica count."
  type        = number
  default     = 0
}

variable "api_max_replicas" {
  description = "Maximum API replica count."
  type        = number
  default     = 2
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

variable "http_concurrent_requests" {
  description = "KEDA HTTP scale target."
  type        = number
  default     = 25
}

variable "ingress_transport" {
  description = "Container App ingress transport."
  type        = string
  default     = "auto"
}

variable "custom_domain_name" {
  description = "Optional API custom domain hostname."
  type        = string
  default     = ""
}

variable "custom_domain_certificate_id" {
  description = "Optional Container Apps environment certificate id."
  type        = string
  default     = ""
}

variable "workload_profile_name" {
  description = "Optional workload profile name. Leave null for Consumption."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
}
