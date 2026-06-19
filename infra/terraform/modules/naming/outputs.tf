locals {
  normalized_suffix = trimspace(var.name_suffix)
  base_parts        = compact([var.app_name, var.environment, local.normalized_suffix])
  base_name         = lower(join("-", local.base_parts))
  compact_name      = replace(lower(join("", local.base_parts)), "/[^0-9a-z]/", "")
  key_vault_parts   = compact([var.app_name, var.environment, "kv", local.normalized_suffix])
  postgres_parts    = compact([var.app_name, var.environment, "pg", local.normalized_suffix])
}

output "resource_group_name" {
  value = trimspace(lookup(var.resource_name_overrides, "resource_group_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "resource_group_name", "")) : "rg-${lower(var.app_name)}-${lower(var.environment)}"
}

output "container_app_environment_name" {
  value = trimspace(lookup(var.resource_name_overrides, "container_app_environment_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "container_app_environment_name", "")) : "${local.base_name}-cae"
}

output "api_container_app_name" {
  value = trimspace(lookup(var.resource_name_overrides, "api_container_app_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "api_container_app_name", "")) : "${local.base_name}-api"
}

output "runtime_identity_name" {
  value = trimspace(lookup(var.resource_name_overrides, "runtime_identity_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "runtime_identity_name", "")) : "${local.base_name}-api-id"
}

output "key_vault_name" {
  value = trimspace(lookup(var.resource_name_overrides, "key_vault_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "key_vault_name", "")) : substr(lower(join("-", local.key_vault_parts)), 0, 24)
}

output "container_registry_name" {
  value = trimspace(lookup(var.resource_name_overrides, "container_registry_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "container_registry_name", "")) : substr("acr${local.compact_name}", 0, 50)
}

output "postgres_server_name" {
  value = trimspace(lookup(var.resource_name_overrides, "postgres_server_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "postgres_server_name", "")) : substr(lower(join("-", local.postgres_parts)), 0, 63)
}

output "postgres_database_name" {
  value = trimspace(lookup(var.resource_name_overrides, "postgres_database_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "postgres_database_name", "")) : var.postgres_database_name
}

output "log_analytics_workspace_name" {
  value = trimspace(lookup(var.resource_name_overrides, "log_analytics_workspace_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "log_analytics_workspace_name", "")) : "${local.base_name}-logs"
}

output "application_insights_name" {
  value = trimspace(lookup(var.resource_name_overrides, "application_insights_name", "")) != "" ? trimspace(lookup(var.resource_name_overrides, "application_insights_name", "")) : "${local.base_name}-appi"
}
