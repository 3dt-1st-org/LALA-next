locals {
  has_deployment_principal = trimspace(coalesce(var.deployment_principal_object_id, "")) != ""
}

resource "azurerm_key_vault" "this" {
  name                          = var.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = true
  rbac_authorization_enabled    = true
  public_network_access_enabled = true
  soft_delete_retention_days    = 7
  tags                          = var.tags
}

resource "azurerm_user_assigned_identity" "runtime" {
  name                = var.runtime_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "runtime_key_vault_secrets_user" {
  count                = var.enable_role_assignments ? 1 : 0
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
}

resource "azurerm_role_assignment" "deployment_key_vault_secrets_officer" {
  count                = var.enable_role_assignments && local.has_deployment_principal ? 1 : 0
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployment_principal_object_id
}
