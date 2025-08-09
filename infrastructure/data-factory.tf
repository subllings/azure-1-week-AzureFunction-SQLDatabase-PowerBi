# =============================================================================
# Azure Data Factory for iRail Train Data Collection
# =============================================================================
# This creates an Azure Data Factory to reliably trigger train data collection
# every 5 minutes, providing better reliability than Azure Functions timers
# =============================================================================

# Data Factory (Demo/Legacy)
resource "azurerm_data_factory" "irail_data_factory" {
  name                = var.data_factory_name != "" ? var.data_factory_name : "df-irail-data-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Ensure new factory can be created before the old one is destroyed when renaming
  lifecycle {
    create_before_destroy = true
  }

  # Enable managed identity for authentication
  identity {
    type = "SystemAssigned"
  }

  # Enable public network access (can be restricted later)
  public_network_enabled = true

  tags = {
    Environment = var.environment
    Project     = "iRail-Data-Collection"
    Purpose     = "Automated-Train-Data-Scheduling"
    ManagedBy   = "Terraform"
  }
}

# Linked Service for HTTP connections to Azure Functions (Demo/Legacy)
resource "azurerm_data_factory_linked_service_web" "irail_functions_http" {
  name            = "ls_irail_functions_http"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  # Legacy/demo Functions base URL (kept intact)
  url = "https://irail-functions-simple.azurewebsites.net"

  # Authentication - using anonymous for now (Functions handle their own auth)
  authentication_type = "Anonymous"

  description = "HTTP connection to iRail Azure Functions (demo)"

  # Additional HTTP headers if needed
  additional_properties = {
    "User-Agent" = "Azure-Data-Factory-iRail-Collector"
    "Accept"     = "application/json"
  }
}

# Dataset for HTTP responses (Demo/Legacy)
resource "azurerm_data_factory_dataset_http" "irail_api_response" {
  name                = "ds_irail_api_response"
  data_factory_id     = azurerm_data_factory.irail_data_factory.id
  linked_service_name = azurerm_data_factory_linked_service_web.irail_functions_http.name

  # Schema for the response (JSON)
  schema_column {
    name        = "status"
    type        = "String"
    description = "API response status"
  }

  schema_column {
    name        = "timestamp"
    type        = "DateTime"
    description = "Response timestamp"
  }

  schema_column {
    name        = "data"
    type        = "String"
    description = "Response data as JSON string"
  }

  description = "Dataset representing HTTP responses from iRail Functions (demo)"

  additional_properties = {
    "contentType" = "application/json"
  }
}

# Log Analytics Workspace for Data Factory monitoring
resource "azurerm_log_analytics_workspace" "data_factory_logs" {
  name                = "log-df-irail-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = var.environment
    Project     = "iRail-Data-Collection"
    Purpose     = "Data-Factory-Monitoring"
    ManagedBy   = "Terraform"
  }
}

# Diagnostic settings for Data Factory
resource "azurerm_monitor_diagnostic_setting" "data_factory_diagnostics" {
  name                       = "df-diagnostics"
  target_resource_id         = azurerm_data_factory.irail_data_factory.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.data_factory_logs.id

  # Enable all log categories
  enabled_log {
    category = "PipelineRuns"
  }

  enabled_log {
    category = "TriggerRuns"
  }

  enabled_log {
    category = "ActivityRuns"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Role assignment for Data Factory to access resources
resource "azurerm_role_assignment" "data_factory_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.irail_data_factory.identity[0].principal_id
}

# =============================================================================
# New Data Factory (v2) - dynamically targets current Function App hostname
# =============================================================================
resource "azurerm_data_factory" "irail_data_factory_v2" {
  name                = var.data_factory2_name != "" ? var.data_factory2_name : "df-irail-data-v2-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  lifecycle { create_before_destroy = true }

  identity { type = "SystemAssigned" }

  public_network_enabled = true

  tags = {
    Environment = var.environment
    Project     = "iRail-Data-Collection"
    Purpose     = "Automated-Train-Data-Scheduling-V2"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_data_factory_linked_service_web" "irail_functions_http_v2" {
  name            = "ls_irail_functions_http_v2"
  data_factory_id = azurerm_data_factory.irail_data_factory_v2.id

  # Dynamic Functions base URL (current deployment)
  url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}"

  authentication_type = "Anonymous"
  description         = "HTTP connection to iRail Azure Functions (v2)"

  additional_properties = {
    "User-Agent" = "Azure-Data-Factory-iRail-Collector-V2"
    "Accept"     = "application/json"
  }
}

resource "azurerm_data_factory_dataset_http" "irail_api_response_v2" {
  name                = "ds_irail_api_response_v2"
  data_factory_id     = azurerm_data_factory.irail_data_factory_v2.id
  linked_service_name = azurerm_data_factory_linked_service_web.irail_functions_http_v2.name

  schema_column { name = "status"    type = "String"  description = "API response status" }
  schema_column { name = "timestamp" type = "DateTime" description = "Response timestamp" }
  schema_column { name = "data"      type = "String"  description = "Response data as JSON string" }

  description = "Dataset representing HTTP responses from iRail Functions (v2)"

  additional_properties = { "contentType" = "application/json" }
}
