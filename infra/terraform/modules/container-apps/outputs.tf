output "container_app_environment_id" {
  description = "Container Apps managed environment id."
  value       = azurerm_container_app_environment.this.id
}

output "container_app_environment_name" {
  description = "Container Apps managed environment name."
  value       = azurerm_container_app_environment.this.name
}

output "api_container_app_id" {
  description = "API Container App id."
  value       = azurerm_container_app.api.id
}

output "api_container_app_name" {
  description = "API Container App name."
  value       = azurerm_container_app.api.name
}

output "api_fqdn" {
  description = "Default Azure Container Apps FQDN."
  value       = azurerm_container_app.api.ingress[0].fqdn
}

output "api_custom_domain_verification_id" {
  description = "Verification id used for custom-domain TXT records."
  value       = azurerm_container_app.api.custom_domain_verification_id
}
