locals {
  has_deployment_principal = trimspace(coalesce(var.deployment_principal_object_id, "")) != ""
  has_runtime_principal    = trimspace(coalesce(var.runtime_principal_id, "")) != ""
}

resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "runtime_acr_pull" {
  count                = var.enable_role_assignments && local.has_runtime_principal ? 1 : 0
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.runtime_principal_id
}

resource "azurerm_role_assignment" "deployment_acr_push" {
  count                = var.enable_role_assignments && local.has_deployment_principal ? 1 : 0
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = var.deployment_principal_object_id
}
