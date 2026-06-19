locals {
  has_custom_domain             = trimspace(var.custom_domain_name) != ""
  has_custom_domain_certificate = trimspace(var.custom_domain_certificate_id) != ""
  api_env = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
    AZURE_CLIENT_ID                       = var.runtime_identity_client_id
    KEY_VAULT_URL                         = var.key_vault_url
    LALA_ALLOWED_KEY_VAULT_HOSTS          = var.allowed_key_vault_hosts
    LALA_ENABLE_LIVE_AI                   = tostring(var.enable_live_ai)
    LALA_ENABLE_LIVE_SPEECH               = tostring(var.enable_live_speech)
    LALA_PUBLIC_DEMO_MODE                 = tostring(var.public_demo_mode)
    PORT                                  = tostring(var.api_target_port)
  }
}

resource "azurerm_container_app_environment" "this" {
  name                       = var.container_app_environment_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags
}

resource "azurerm_container_app" "api" {
  name                         = var.api_container_app_name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  workload_profile_name        = var.workload_profile_name
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.runtime_identity_id]
  }

  registry {
    server   = var.registry_server
    identity = var.runtime_identity_id
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = var.api_target_port
    transport                  = var.ingress_transport

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.api_min_replicas
    max_replicas = var.api_max_replicas

    container {
      name   = "api"
      image  = var.api_image
      cpu    = var.api_cpu
      memory = var.api_memory

      dynamic "env" {
        for_each = local.api_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }

    http_scale_rule {
      name                = "http-scale"
      concurrent_requests = var.http_concurrent_requests
    }
  }
}

resource "azurerm_container_app_custom_domain" "api" {
  count = local.has_custom_domain ? 1 : 0

  name             = var.custom_domain_name
  container_app_id = azurerm_container_app.api.id

  container_app_environment_certificate_id = local.has_custom_domain_certificate ? var.custom_domain_certificate_id : null
  certificate_binding_type                 = local.has_custom_domain_certificate ? "SniEnabled" : null
}
