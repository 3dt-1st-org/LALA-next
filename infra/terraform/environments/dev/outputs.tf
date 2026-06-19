output "resource_group_name" {
  description = "Shared dev resource group name."
  value       = module.resource_group.name
}

output "container_registry_name" {
  description = "Azure Container Registry name."
  value       = module.container_registry.name
}

output "container_registry_login_server" {
  description = "Azure Container Registry login server."
  value       = module.container_registry.login_server
}

output "api_image_repository" {
  description = "Recommended API image repository inside ACR."
  value       = "${module.container_registry.login_server}/${var.api_image_repository_name}"
}

output "key_vault_name" {
  description = "Azure Key Vault name."
  value       = module.key_vault.key_vault_name
}

output "key_vault_uri" {
  description = "Azure Key Vault URI."
  value       = module.key_vault.key_vault_uri
}

output "key_vault_host" {
  description = "Azure Key Vault host used by the runtime allowlist."
  value       = module.key_vault.key_vault_host
}

output "runtime_identity_id" {
  description = "User-assigned managed identity resource id."
  value       = module.key_vault.runtime_identity_id
}

output "runtime_identity_client_id" {
  description = "User-assigned managed identity client id."
  value       = module.key_vault.runtime_identity_client_id
}

output "runtime_identity_principal_id" {
  description = "User-assigned managed identity principal id."
  value       = module.key_vault.runtime_identity_principal_id
}

output "container_app_environment_name" {
  description = "Container Apps managed environment name."
  value       = module.container_apps.container_app_environment_name
}

output "api_container_app_name" {
  description = "API Container App name."
  value       = module.container_apps.api_container_app_name
}

output "api_fqdn" {
  description = "Default Azure Container Apps FQDN."
  value       = module.container_apps.api_fqdn
}

output "api_custom_domain_verification_id" {
  description = "Verification id used for custom-domain TXT records."
  value       = module.container_apps.api_custom_domain_verification_id
}

output "postgres_server_name" {
  description = "PostgreSQL Flexible Server name."
  value       = module.postgres.server_name
}

output "postgres_fqdn" {
  description = "PostgreSQL Flexible Server FQDN."
  value       = module.postgres.fqdn
}

output "postgres_database_name" {
  description = "Application database name."
  value       = module.postgres.database_name
}

output "key_vault_secret_names" {
  description = "Key Vault secret names expected by the shared runtime."
  value       = local.key_vault_secret_names
}
