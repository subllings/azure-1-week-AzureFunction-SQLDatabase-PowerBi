# =============================================================================
# Azure Data Factory 2 (New) - Dynamic Function Host
# =============================================================================
# This creates a second Azure Data Factory alongside the demo one.
# It references the current Function App dynamically (no hard-coded host).
# =============================================================================

# Second Data Factory (New)
resource "azurerm_data_factory" "irail_data_factory2" {
  name                = var.data_factory2_name != "" ? var.data_factory2_name : "df2-irail-data-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  lifecycle {
    create_before_destroy = true
  }

  identity {
    type = "SystemAssigned"
  }

  public_network_enabled = true

  tags = {
    Environment = var.environment
    Project     = "iRail-Data-Collection"
    Purpose     = "Automated-Train-Data-Scheduling"
    ManagedBy   = "Terraform"
    Variant     = "v2"
  }
}

# Linked Service for HTTP connections to Azure Functions (ADF2)
resource "azurerm_data_factory_linked_service_web" "irail_functions_http_v2" {
  name            = "ls_irail_functions_http_v2"
  data_factory_id = azurerm_data_factory.irail_data_factory2.id

  # Dynamic Function App host
  url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}"

  authentication_type = "Anonymous"
  description         = "HTTP connection to iRail Azure Functions for data collection (new)"

  additional_properties = {
    "User-Agent" = "Azure-Data-Factory-iRail-Collector"
    "Accept"     = "application/json"
  }
}

# Dataset for HTTP responses (ADF2)
resource "azurerm_data_factory_dataset_http" "irail_api_response_v2" {
  name                = "ds_irail_api_response_v2"
  data_factory_id     = azurerm_data_factory.irail_data_factory2.id
  linked_service_name = azurerm_data_factory_linked_service_web.irail_functions_http_v2.name

  schema_column { name = "status"    type = "String"  description = "API response status" }
  schema_column { name = "timestamp" type = "DateTime" description = "Response timestamp" }
  schema_column { name = "data"      type = "String"  description = "Response data as JSON string" }

  description = "Dataset representing HTTP responses from iRail Functions (ADF2)"
  additional_properties = { "contentType" = "application/json" }
}

# Reuse existing workspace for DF monitoring
resource "azurerm_monitor_diagnostic_setting" "data_factory2_diagnostics" {
  name                       = "df2-diagnostics"
  target_resource_id         = azurerm_data_factory.irail_data_factory2.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.data_factory_logs.id

  enabled_log { category = "PipelineRuns" }
  enabled_log { category = "TriggerRuns" }
  enabled_log { category = "ActivityRuns" }
  metric { category = "AllMetrics" enabled = true }
}

# Role assignment for Data Factory 2 to access RG resources if needed
resource "azurerm_role_assignment" "data_factory2_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.irail_data_factory2.identity[0].principal_id
}
