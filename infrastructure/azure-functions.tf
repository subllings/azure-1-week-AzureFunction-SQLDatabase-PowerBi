# Azure Functions App for iRail Train Data API
# =============================================================================
# This creates the Azure Functions App that will host all the iRail APIs
# with container support and proper security configuration
# =============================================================================

# Azure Function App
resource "azurerm_linux_function_app" "irail_functions" {
  name                = "func-${local.project_name}-${local.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Storage configuration for Consumption plan (Y1)
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key

  # Link to App Service Plan
  service_plan_id = azurerm_service_plan.irail_functions_plan.id

  # Managed Identity configuration
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function_identity.id]
  }

  # Site configuration for Consumption Plan (Y1)
  site_config {
    # CORS settings for frontend integration
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }

    # Performance settings for Y1 plan
    always_on = false # Always_on is not available with Consumption plan

    # Application Insights integration
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string

    # Python runtime configuration for Y1 plan
    application_stack {
      python_version = "3.12"
    }
  }

  # Application settings
  app_settings = {
    # Runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "FUNCTIONS_EXTENSION_VERSION" = "~4"

    # Function timeout settings for Consumption Plan (Y1)
    "functionTimeout"                = "00:05:00" # 5 minute timeout (Y1 max limit)
    "FUNCTIONS_WORKER_PROCESS_COUNT" = "1"

    # Y1-specific settings
    "FUNCTIONS_WORKER_RUNTIME_VERSION" = "3.11"
    "AzureWebJobsFeatureFlags"         = "EnableWorkerIndexing"

    # Performance settings for Consumption plan
    "WEBSITE_RUN_FROM_PACKAGE"        = "1" # Run from package for better performance
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"

    # Container settings (for container deployment if needed)
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_REGISTRY_SERVER_URL"          = "https://${azurerm_container_registry.main.login_server}"
    "DOCKER_REGISTRY_SERVER_USERNAME"     = azurerm_container_registry.main.admin_username
    "DOCKER_REGISTRY_SERVER_PASSWORD"     = azurerm_container_registry.main.admin_password

    # Monitoring and logging
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string

    # Database connection (via Key Vault reference for security)
    "SQL_CONNECTION_STRING" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=sql-connection-string)"

    # iRail API configuration
    "IRAIL_API_BASE_URL" = "https://api.irail.be"
    "USER_AGENT"         = "BeCodeTrainApp/1.0 (student.project@becode.education)"

    # Environment configuration
    "ENVIRONMENT"                 = var.environment
    "AZURE_FUNCTIONS_ENVIRONMENT" = var.environment

    # Timezone configuration
    "WEBSITE_TIME_ZONE" = "W. Europe Standard Time"
  }

  tags = merge(local.common_tags, {
    Component = "Azure Functions"
    Purpose   = "iRail Train Data API"
    Runtime   = "Python 3.12"
  })

  depends_on = [
    azurerm_key_vault_access_policy.current,
    azurerm_service_plan.irail_functions_plan
  ]
}

# Key Vault Access Policy for Function App Managed Identity
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_user_assigned_identity.function_identity.tenant_id
  object_id    = azurerm_user_assigned_identity.function_identity.principal_id

  secret_permissions = [
    "Get", "List"
  ]
}

# Output the Function App information
output "function_app_name" {
  description = "Name of the Azure Functions App"
  value       = azurerm_linux_function_app.irail_functions.name
}

output "function_app_url" {
  description = "URL of the Azure Functions App"
  value       = "https://${azurerm_linux_function_app.irail_functions.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_user_assigned_identity.function_identity.principal_id
}

output "function_app_identity_client_id" {
  description = "Client ID of the Function App managed identity"
  value       = azurerm_user_assigned_identity.function_identity.client_id
}
