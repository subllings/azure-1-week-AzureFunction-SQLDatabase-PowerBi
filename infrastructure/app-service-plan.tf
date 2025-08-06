# =============================================================================
# Azure App Service Plan for iRail Functions
# =============================================================================
# This creates the App Service Plan that will host the Azure Functions
# with different SKUs for staging and production environments
# =============================================================================

# App Service Plan
resource "azurerm_service_plan" "irail_functions_plan" {
  name                = "asp-${local.project_name}-${local.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  
  # SKU based on environment
  # FC1 = Flex Consumption (serverless) - for staging and development
  # EP1 = Elastic Premium - for production with better performance
  sku_name = var.environment == "production" ? "EP1" : "FC1"
  
  tags = merge(local.common_tags, {
    Component = "App Service Plan"
    Purpose   = "Azure Functions Hosting"
  })
}

# Output the App Service Plan information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.irail_functions_plan.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.irail_functions_plan.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.irail_functions_plan.sku_name
}
