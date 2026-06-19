locals {
  resource_group_name = trimspace(coalesce(var.resource_group_name, "")) != "" ? trimspace(var.resource_group_name) : module.naming.resource_group_name

  tags = merge(
    {
      app        = var.app_name
      env        = var.environment_name
      managed_by = "terraform"
      service    = "lala-next-api"
      data_path  = "postgres-keyvault-rag"
      hardening  = "pending"
    },
    var.additional_tags
  )

  key_vault_secret_names = {
    api_bearer_token   = "api-bearer-token"
    cors_allow_origins = "cors-allow-origins"
    db_dsn             = "db-dsn"
  }
}

module "naming" {
  source                  = "../../modules/naming"
  app_name                = var.app_name
  environment             = var.environment_name
  name_suffix             = var.name_suffix
  postgres_database_name  = var.postgres_database_name
  resource_name_overrides = var.resource_name_overrides
}

module "resource_group" {
  source   = "../../modules/resource-group"
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

module "observability" {
  source                       = "../../modules/observability"
  resource_group_name          = module.resource_group.name
  location                     = module.resource_group.location
  log_analytics_workspace_name = module.naming.log_analytics_workspace_name
  application_insights_name    = module.naming.application_insights_name
  log_retention_days           = 30
  tags                         = local.tags
}

module "key_vault" {
  source                         = "../../modules/key-vault"
  resource_group_name            = module.resource_group.name
  location                       = module.resource_group.location
  tenant_id                      = var.tenant_id
  key_vault_name                 = module.naming.key_vault_name
  runtime_identity_name          = module.naming.runtime_identity_name
  deployment_principal_object_id = var.deployment_principal_object_id
  enable_role_assignments        = var.enable_role_assignments
  tags                           = local.tags
}

module "container_registry" {
  source                         = "../../modules/container-registry"
  resource_group_name            = module.resource_group.name
  location                       = module.resource_group.location
  name                           = module.naming.container_registry_name
  runtime_principal_id           = module.key_vault.runtime_identity_principal_id
  deployment_principal_object_id = var.deployment_principal_object_id
  enable_role_assignments        = var.enable_role_assignments
  tags                           = local.tags
}

module "postgres" {
  source                                    = "../../modules/postgres"
  resource_group_name                       = module.resource_group.name
  location                                  = module.resource_group.location
  server_name                               = module.naming.postgres_server_name
  database_name                             = module.naming.postgres_database_name
  administrator_login                       = var.postgres_admin_login
  administrator_password                    = var.postgres_admin_password
  postgres_version                          = var.postgres_version
  sku_name                                  = var.postgres_sku_name
  storage_mb                                = var.postgres_storage_mb
  backup_retention_days                     = var.postgres_backup_retention_days
  zone                                      = var.postgres_zone
  public_network_access_enabled             = var.postgres_public_network_access_enabled
  enabled_extensions                        = var.postgres_extensions
  create_allow_azure_services_firewall_rule = true
  tags                                      = local.tags
}

module "container_apps" {
  source                                 = "../../modules/container-apps"
  resource_group_name                    = module.resource_group.name
  location                               = module.resource_group.location
  container_app_environment_name         = module.naming.container_app_environment_name
  api_container_app_name                 = module.naming.api_container_app_name
  log_analytics_workspace_id             = module.observability.log_analytics_workspace_id
  runtime_identity_id                    = module.key_vault.runtime_identity_id
  runtime_identity_client_id             = module.key_vault.runtime_identity_client_id
  registry_server                        = module.container_registry.login_server
  api_image                              = var.api_image
  key_vault_url                          = module.key_vault.key_vault_uri
  allowed_key_vault_hosts                = module.key_vault.key_vault_host
  application_insights_connection_string = module.observability.application_insights_connection_string
  public_demo_mode                       = var.public_demo_mode
  enable_live_ai                         = var.enable_live_ai
  enable_live_speech                     = var.enable_live_speech
  api_target_port                        = var.api_target_port
  api_min_replicas                       = var.api_min_replicas
  api_max_replicas                       = var.api_max_replicas
  api_cpu                                = var.api_cpu
  api_memory                             = var.api_memory
  http_concurrent_requests               = var.api_http_concurrent_requests
  ingress_transport                      = var.api_ingress_transport
  custom_domain_name                     = var.api_custom_domain_name
  custom_domain_certificate_id           = var.api_custom_domain_certificate_id
  tags                                   = local.tags
}
