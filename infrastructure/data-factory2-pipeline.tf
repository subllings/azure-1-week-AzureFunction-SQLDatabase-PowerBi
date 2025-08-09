# =============================================================================
# Azure Data Factory 2 Pipelines (Dynamic host)
# =============================================================================

locals {
  adf2_func_base = "https://${azurerm_linux_function_app.irail_functions.default_hostname}"
}

# Main pipeline (ADF2)
resource "azurerm_data_factory_pipeline" "irail_train_data_collection_v2" {
  name            = "pipeline_irail_train_data_collection_v2"
  data_factory_id = azurerm_data_factory.irail_data_factory2.id
  description     = "Collects train data using dynamic Function App host"

  parameters = {
    "station_list"        = jsonencode(["Brussels-Central","Brussels-North","Brussels-South","Antwerp-Central","Ghent-Sint-Pieters","Leuven","Charleroi-Sud","Bruges","Liege-Guillemins"])
    "execution_timestamp" = "@utcnow()"
    "max_retries"         = "3"
  }

  activities_json = jsonencode([
    {
      name = "HealthCheck"
      type = "WebActivity"
      typeProperties = {
        url    = "${local.adf2_func_base}/api/health"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "ADF2" }
      }
      policy = { timeout = "00:01:00", retry = 2, retryIntervalInSeconds = 30 }
    },
    {
      name = "TriggerDataCollection"
      type = "WebActivity"
      dependsOn = [{ activity = "HealthCheck", dependencyConditions = ["Succeeded"] }]
      typeProperties = {
        url    = "${local.adf2_func_base}/api/collect-data"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "ADF2" }
      }
      policy = { timeout = "00:05:00", retry = 3, retryIntervalInSeconds = 60 }
    },
    {
      name = "VerifyDatabaseUpdate"
      type = "WebActivity"
      dependsOn = [{ activity = "TriggerDataCollection", dependencyConditions = ["Succeeded"] }]
      typeProperties = {
        url    = "${local.adf2_func_base}/api/analytics"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "ADF2" }
      }
      policy = { timeout = "00:02:00", retry = 1, retryIntervalInSeconds = 30 }
    }
  ])

  folder = "iRail Data Collection v2"
  annotations = ["iRail", "Dynamic Host", "v2"]
}

# Warmup pipeline (ADF2)
resource "azurerm_data_factory_pipeline" "irail_function_warmup_v2" {
  name            = "pipeline_irail_function_warmup_v2"
  data_factory_id = azurerm_data_factory.irail_data_factory2.id
  description     = "Keeps Azure Functions warm (ADF2)"

  folder = "iRail Data Collection v2/Maintenance"
  parameters = { "execution_timestamp" = "@utcnow()", "warmup_type" = "regular" }

  activities_json = jsonencode([
    {
      name = "WarmupFunction"
      type = "WebActivity"
      typeProperties = { url = "${local.adf2_func_base}/api/warmup", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "ADF2" } }
      policy = { timeout = "00:02:00", retry = 2, retryIntervalInSeconds = 15 }
    },
    {
      name = "VerifyHealth"
      type = "WebActivity"
      dependsOn = [{ activity = "WarmupFunction", dependencyConditions = ["Succeeded"] }]
      typeProperties = { url = "${local.adf2_func_base}/api/health", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "ADF2" } }
      policy = { timeout = "00:01:00", retry = 1, retryIntervalInSeconds = 10 }
    }
  ])

  annotations = ["iRail", "Function Warmup", "v2"]
}
