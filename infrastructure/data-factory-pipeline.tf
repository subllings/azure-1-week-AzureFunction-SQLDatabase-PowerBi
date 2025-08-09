# =============================================================================
# Azure Data Factory Pipelines for iRail Train Data Collection
# =============================================================================
# This creates the actual pipelines that will collect train data from
# all major Belgian stations every 5 minutes with robust error handling
# =============================================================================

# Main pipeline for train data collection (Legacy/Demo)
resource "azurerm_data_factory_pipeline" "irail_train_data_collection" {
  name            = "pipeline_irail_train_data_collection"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  description = "Collects train data from all major Belgian stations every 5 minutes"

  parameters = {
    "station_list"        = jsonencode(["Brussels-Central", "Brussels-North", "Brussels-South", "Antwerp-Central", "Ghent-Sint-Pieters", "Leuven", "Charleroi-Sud", "Bruges", "Liege-Guillemins"]) 
    "execution_timestamp" = "@utcnow()"
    "max_retries"         = "3"
  }

  activities_json = jsonencode([
    {
      name = "HealthCheck"
      type = "WebActivity"
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/health"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-iRail-Collector" }
      }
      policy = { timeout = "00:01:00", retry = 2, retryIntervalInSeconds = 30 }
    },
    {
      name = "TriggerDataCollection"
      type = "WebActivity"
      dependsOn = [{ activity = "HealthCheck", dependencyConditions = ["Succeeded"] }]
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/collect-data"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-iRail-Collector" }
      }
      policy = { timeout = "00:05:00", retry = 3, retryIntervalInSeconds = 60 }
    },
    {
      name = "VerifyDatabaseUpdate"
      type = "WebActivity"
      dependsOn = [{ activity = "TriggerDataCollection", dependencyConditions = ["Succeeded"] }]
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/analytics"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-iRail-Collector" }
      }
      policy = { timeout = "00:02:00", retry = 1, retryIntervalInSeconds = 30 }
    },
    {
      name = "LogSuccess"
      type = "WebActivity"
      dependsOn = [{ activity = "VerifyDatabaseUpdate", dependencyConditions = ["Succeeded"] }]
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/debug"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-Success-Logger", "X-Collection-Status" = "SUCCESS" }
      }
      policy = { timeout = "00:01:00", retry = 1, retryIntervalInSeconds = 15 }
    }
  ])

  folder = "iRail Data Collection"
  annotations = ["iRail", "Train Data", "Automated Collection", "Every 5 Minutes"]
}

# Secondary pipeline for enhanced data collection (Legacy/Demo)
resource "azurerm_data_factory_pipeline" "irail_enhanced_collection" {
  name            = "pipeline_irail_enhanced_collection"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  description = "Enhanced collection pipeline that calls liveboard for each major station individually"

  parameters = {
    "execution_timestamp" = "@utcnow()"
    "station_limit"       = "10"
    "station_list"        = jsonencode(["Brussels-Central", "Brussels-North", "Brussels-South", "Antwerp-Central", "Ghent-Sint-Pieters", "Leuven", "Charleroi-Sud", "Bruges", "Liege-Guillemins"]) 
  }

  activities_json = jsonencode([
    {
      name = "ProcessEachStation"
      type = "ForEach"
      typeProperties = {
        items = { value = "@pipeline().parameters.station_list", type = "Expression" }
        isSequential = false
        batchCount   = 3
        activities = [
          {
            name = "CollectStationData"
            type = "WebActivity"
            typeProperties = {
              url = { value = "@concat('https://irail-functions-simple.azurewebsites.net/api/liveboard?station=', item(), '&limit=', pipeline().parameters.station_limit)", type = "Expression" }
              method = "GET"
              headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-Station-Collector", "X-Station" = "@{item()}" }
            }
            policy = { timeout = "00:03:00", retry = 2, retryIntervalInSeconds = 45 }
          }
        ]
      }
    }
  ])

  folder = "iRail Data Collection"
  annotations = ["iRail", "Enhanced Collection", "Individual Stations", "Parallel Processing"]
}

# Error handling pipeline (Legacy/Demo)
resource "azurerm_data_factory_pipeline" "irail_error_handler" {
  name            = "pipeline_irail_error_handler"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  description = "Handles errors and sends notifications when data collection fails"

  parameters = { "error_message" = "", "failed_activity" = "", "execution_timestamp" = "@utcnow()" }

  activities_json = jsonencode([
    {
      name = "LogError"
      type = "WebActivity"
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/debug"
        method = "GET"
        headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-Error-Logger", "X-Error-Message" = "@{pipeline().parameters.error_message}", "X-Failed-Activity" = "@{pipeline().parameters.failed_activity}", "X-Collection-Status" = "ERROR" }
      }
      policy = { timeout = "00:01:00", retry = 1, retryIntervalInSeconds = 15 }
    }
  ])

  folder = "iRail Data Collection/Error Handling"
  annotations = ["iRail", "Error Handling", "Notifications", "Monitoring"]
}

# WARMUP PIPELINE - Keep Functions Alive (Legacy/Demo)
resource "azurerm_data_factory_pipeline" "irail_function_warmup" {
  name            = "pipeline_irail_function_warmup"
  data_factory_id = azurerm_data_factory.irail_data_factory.id
  description     = "Keeps Azure Functions warm to prevent cold starts and timeouts"

  folder = "iRail Data Collection/Maintenance"
  parameters = { "execution_timestamp" = "@utcnow()", "warmup_type" = "regular" }

  activities_json = jsonencode([
    {
      "name" : "WarmupFunction",
      "type" : "WebActivity",
      "policy" : { "timeout" : "00:02:00", "retry" : 2, "retryIntervalInSeconds" : 15 },
      "typeProperties" : {
        "url" : "https://irail-functions-simple.azurewebsites.net/api/warmup",
        "method" : "GET",
        "headers" : { "Content-Type" : "application/json", "User-Agent" : "Azure-Data-Factory-Function-Warmup", "X-Warmup-Type" : "@{pipeline().parameters.warmup_type}" }
      }
    },
    {
      "name" : "VerifyHealth",
      "type" : "WebActivity",
      "dependsOn" : [{ "activity" : "WarmupFunction", "dependencyConditions" : ["Succeeded"] }],
      "policy" : { "timeout" : "00:01:00", "retry" : 1, "retryIntervalInSeconds" : 10 },
      "typeProperties" : {
        "url" : "https://irail-functions-simple.azurewebsites.net/api/health",
        "method" : "GET",
        "headers" : { "Content-Type" : "application/json", "User-Agent" : "Azure-Data-Factory-Health-Check" }
      }
    },
    {
      "name" : "TestiRailConnection",
      "type" : "WebActivity",
      "dependsOn" : [{ "activity" : "VerifyHealth", "dependencyConditions" : ["Succeeded"] }],
      "policy" : { "timeout" : "00:01:00", "retry" : 1, "retryIntervalInSeconds" : 10 },
      "typeProperties" : {
        "url" : "https://irail-functions-simple.azurewebsites.net/api/debug",
        "method" : "GET",
        "headers" : { "Content-Type" : "application/json", "User-Agent" : "Azure-Data-Factory-Connection-Test", "X-Test-Type" : "warmup" }
      }
    }
  ])

  annotations = ["iRail", "Function Warmup", "Cold Start Prevention", "Performance"]
}

# ============================================================================
# New Pipelines (v2) - Using dynamic Function App hostname and new Data Factory
# ============================================================================
resource "azurerm_data_factory_pipeline" "irail_train_data_collection_v2" {
  name            = "pipeline_irail_train_data_collection"
  data_factory_id = azurerm_data_factory.irail_data_factory_v2.id
  description     = "Collects train data every 5 minutes (v2)"

  parameters = {
    "station_list"        = jsonencode(["Brussels-Central", "Brussels-North", "Brussels-South", "Antwerp-Central", "Ghent-Sint-Pieters", "Leuven", "Charleroi-Sud", "Bruges", "Liege-Guillemins"]) 
    "execution_timestamp" = "@utcnow()"
    "max_retries"         = "3"
  }

  activities_json = jsonencode([
    { name = "HealthCheck", type = "WebActivity", typeProperties = { url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/health", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-iRail-Collector" } }, policy = { timeout = "00:01:00", retry = 2, retryIntervalInSeconds = 30 } },
    { name = "TriggerDataCollection", type = "WebActivity", dependsOn = [{ activity = "HealthCheck", dependencyConditions = ["Succeeded"] }], typeProperties = { url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/collect-data", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-iRail-Collector" } }, policy = { timeout = "00:05:00", retry = 3, retryIntervalInSeconds = 60 } },
    { name = "VerifyDatabaseUpdate", type = "WebActivity", dependsOn = [{ activity = "TriggerDataCollection", dependencyConditions = ["Succeeded"] }], typeProperties = { url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/analytics", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-iRail-Collector" } }, policy = { timeout = "00:02:00", retry = 1, retryIntervalInSeconds = 30 } },
    { name = "LogSuccess", type = "WebActivity", dependsOn = [{ activity = "VerifyDatabaseUpdate", dependencyConditions = ["Succeeded"] }], typeProperties = { url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/debug", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-Success-Logger", "X-Collection-Status" = "SUCCESS" } }, policy = { timeout = "00:01:00", retry = 1, retryIntervalInSeconds = 15 } }
  ])

  folder      = "iRail Data Collection"
  annotations = ["iRail", "Train Data", "Automated Collection", "Every 5 Minutes"]
}

resource "azurerm_data_factory_pipeline" "irail_enhanced_collection_v2" {
  name            = "pipeline_irail_enhanced_collection"
  data_factory_id = azurerm_data_factory.irail_data_factory_v2.id
  description     = "Enhanced collection pipeline (v2)"

  parameters = {
    "execution_timestamp" = "@utcnow()"
    "station_limit"       = "10"
    "station_list"        = jsonencode(["Brussels-Central", "Brussels-North", "Brussels-South", "Antwerp-Central", "Ghent-Sint-Pieters", "Leuven", "Charleroi-Sud", "Bruges", "Liege-Guillemins"]) 
  }

  activities_json = jsonencode([
    {
      name = "ProcessEachStation"
      type = "ForEach"
      typeProperties = {
        items = { value = "@pipeline().parameters.station_list", type = "Expression" }
        isSequential = false
        batchCount   = 3
        activities = [
          {
            name = "CollectStationData"
            type = "WebActivity"
            typeProperties = {
              url = { value = "@concat('https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/liveboard?station=', item(), '&limit=', pipeline().parameters.station_limit)", type = "Expression" }
              method = "GET"
              headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-Station-Collector", "X-Station" = "@{item()}" }
            }
            policy = { timeout = "00:03:00", retry = 2, retryIntervalInSeconds = 45 }
          }
        ]
      }
    }
  ])

  folder      = "iRail Data Collection"
  annotations = ["iRail", "Enhanced Collection", "Individual Stations", "Parallel Processing"]
}

resource "azurerm_data_factory_pipeline" "irail_error_handler_v2" {
  name            = "pipeline_irail_error_handler"
  data_factory_id = azurerm_data_factory.irail_data_factory_v2.id
  description     = "Handles errors (v2)"

  parameters = { "error_message" = "", "failed_activity" = "", "execution_timestamp" = "@utcnow()" }

  activities_json = jsonencode([
    { name = "LogError", type = "WebActivity", typeProperties = { url = "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/debug", method = "GET", headers = { "Content-Type" = "application/json", "User-Agent" = "Azure-Data-Factory-Error-Logger", "X-Error-Message" = "@{pipeline().parameters.error_message}", "X-Failed-Activity" = "@{pipeline().parameters.failed_activity}", "X-Collection-Status" = "ERROR" } }, policy = { timeout = "00:01:00", retry = 1, retryIntervalInSeconds = 15 } }
  ])

  folder      = "iRail Data Collection/Error Handling"
  annotations = ["iRail", "Error Handling", "Notifications", "Monitoring"]
}

resource "azurerm_data_factory_pipeline" "irail_function_warmup_v2" {
  name            = "pipeline_irail_function_warmup"
  data_factory_id = azurerm_data_factory.irail_data_factory_v2.id
  description     = "Keeps Azure Functions warm (v2)"

  folder      = "iRail Data Collection/Maintenance"
  parameters  = { "execution_timestamp" = "@utcnow()", "warmup_type" = "regular" }

  activities_json = jsonencode([
    { "name" : "WarmupFunction", "type" : "WebActivity", "policy" : { "timeout" : "00:02:00", "retry" : 2, "retryIntervalInSeconds" : 15 }, "typeProperties" : { "url" : "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/warmup", "method" : "GET", "headers" : { "Content-Type" : "application/json", "User-Agent" : "Azure-Data-Factory-Function-Warmup", "X-Warmup-Type" : "@{pipeline().parameters.warmup_type}" } } },
    { "name" : "VerifyHealth", "type" : "WebActivity", "dependsOn" : [{ "activity" : "WarmupFunction", "dependencyConditions" : ["Succeeded"] }], "policy" : { "timeout" : "00:01:00", "retry" : 1, "retryIntervalInSeconds" : 10 }, "typeProperties" : { "url" : "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/health", "method" : "GET", "headers" : { "Content-Type" : "application/json", "User-Agent" : "Azure-Data-Factory-Health-Check" } } },
    { "name" : "TestiRailConnection", "type" : "WebActivity", "dependsOn" : [{ "activity" : "VerifyHealth", "dependencyConditions" : ["Succeeded"] }], "policy" : { "timeout" : "00:01:00", "retry" : 1, "retryIntervalInSeconds" : 10 }, "typeProperties" : { "url" : "https://${azurerm_linux_function_app.irail_functions.default_hostname}/api/debug", "method" : "GET", "headers" : { "Content-Type" : "application/json", "User-Agent" : "Azure-Data-Factory-Connection-Test", "X-Test-Type" : "warmup" } } }
  ])

  annotations = ["iRail", "Function Warmup", "Cold Start Prevention", "Performance"]
}
