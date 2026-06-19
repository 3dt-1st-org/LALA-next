output "id" {
  description = "Azure Container Registry id."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Azure Container Registry name."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Azure Container Registry login server."
  value       = azurerm_container_registry.this.login_server
}
