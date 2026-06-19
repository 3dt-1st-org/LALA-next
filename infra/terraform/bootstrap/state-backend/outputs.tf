output "resource_group_name" {
  description = "Resource group that hosts the Terraform state backend."
  value       = local.resolved_resource_group_name
}

output "storage_account_name" {
  description = "Terraform state Storage Account name."
  value       = azurerm_storage_account.tfstate.name
}

output "storage_account_id" {
  description = "Terraform state Storage Account id."
  value       = azurerm_storage_account.tfstate.id
}

output "container_name" {
  description = "Terraform state blob container name."
  value       = var.create_state_container ? azurerm_storage_container.tfstate[0].name : var.container_name
}

output "backend_bootstrap_config" {
  description = "Suggested backend config values for the bootstrap root module after migration."
  value = {
    resource_group_name  = local.resolved_resource_group_name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = var.container_name
    key                  = var.bootstrap_state_key
    use_azuread_auth     = true
  }
}

output "backend_dev_config" {
  description = "Suggested backend config values for environments/dev."
  value = {
    resource_group_name  = local.resolved_resource_group_name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = var.container_name
    key                  = var.dev_state_key
    use_azuread_auth     = true
  }
}

output "backend_prod_config" {
  description = "Suggested backend config values for environments/prod."
  value = {
    resource_group_name  = local.resolved_resource_group_name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = var.container_name
    key                  = var.prod_state_key
    use_azuread_auth     = true
  }
}
