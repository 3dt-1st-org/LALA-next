output "key_vault_id" {
  description = "Key Vault id."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}

output "key_vault_host" {
  description = "Key Vault host without protocol."
  value       = replace(replace(azurerm_key_vault.this.vault_uri, "https://", ""), "/", "")
}

output "runtime_identity_id" {
  description = "User-assigned managed identity id."
  value       = azurerm_user_assigned_identity.runtime.id
}

output "runtime_identity_client_id" {
  description = "User-assigned managed identity client id."
  value       = azurerm_user_assigned_identity.runtime.client_id
}

output "runtime_identity_principal_id" {
  description = "User-assigned managed identity principal id."
  value       = azurerm_user_assigned_identity.runtime.principal_id
}
