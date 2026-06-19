variable "app_name" {
  description = "Application name used in Azure resource names."
  type        = string
}

variable "environment" {
  description = "Deployment environment such as dev or prod."
  type        = string
}

variable "name_suffix" {
  description = "Optional stable suffix for uniqueness and import alignment."
  type        = string
  default     = ""
}

variable "postgres_database_name" {
  description = "Application database name."
  type        = string
  default     = "lala"
}

variable "resource_name_overrides" {
  description = "Optional explicit resource names keyed by output name."
  type        = map(string)
  default     = {}
}
