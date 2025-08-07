# =============================================================================
# Azure Data Factory Pipelines for iRail Train Data Collection
# =============================================================================
# This creates the actual pipelines that will collect train data from
# all major Belgian stations every 5 minutes with robust error handling
# =============================================================================

# Main pipeline for train data collection
resource "azurerm_data_factory_pipeline" "irail_train_data_collection" {
  name            = "pipeline_irail_train_data_collection"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  description = "Collects train data from all major Belgian stations every 5 minutes"

  # Pipeline parameters
  parameters = {
    "station_list" = jsonencode([
      "Brussels-Central",
      "Brussels-North",
      "Brussels-South",
      "Antwerp-Central",
      "Ghent-Sint-Pieters",
      "Leuven",
      "Charleroi-Sud",
      "Bruges",
      "Liege-Guillemins"
    ])
    "execution_timestamp" = "@utcnow()"
    "max_retries"         = "3"
  }

  # Pipeline activities as JSON
  activities_json = jsonencode([
    # Activity 1: Health Check
    {
      name = "HealthCheck"
      type = "WebActivity"
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/health"
        method = "GET"
        headers = {
          "Content-Type" = "application/json"
          "User-Agent"   = "Azure-Data-Factory-iRail-Collector"
        }
      }
      policy = {
        timeout                = "00:01:00"
        retry                  = 2
        retryIntervalInSeconds = 30
      }
    },

    # Activity 2: Trigger Data Collection (depends on health check)
    {
      name = "TriggerDataCollection"
      type = "WebActivity"
      dependsOn = [
        {
          activity             = "HealthCheck"
          dependencyConditions = ["Succeeded"]
        }
      ]
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/collect-data"
        method = "GET"
        headers = {
          "Content-Type" = "application/json"
          "User-Agent"   = "Azure-Data-Factory-iRail-Collector"
        }
      }
      policy = {
        timeout                = "00:05:00"
        retry                  = 3
        retryIntervalInSeconds = 60
      }
    },

    # Activity 3: Verify Database Update (depends on data collection)
    {
      name = "VerifyDatabaseUpdate"
      type = "WebActivity"
      dependsOn = [
        {
          activity             = "TriggerDataCollection"
          dependencyConditions = ["Succeeded"]
        }
      ]
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/analytics"
        method = "GET"
        headers = {
          "Content-Type" = "application/json"
          "User-Agent"   = "Azure-Data-Factory-iRail-Collector"
        }
      }
      policy = {
        timeout                = "00:02:00"
        retry                  = 1
        retryIntervalInSeconds = 30
      }
    },

    # Activity 4: Log Success (depends on verification)
    {
      name = "LogSuccess"
      type = "WebActivity"
      dependsOn = [
        {
          activity             = "VerifyDatabaseUpdate"
          dependencyConditions = ["Succeeded"]
        }
      ]
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/debug"
        method = "GET"
        headers = {
          "Content-Type"        = "application/json"
          "User-Agent"          = "Azure-Data-Factory-Success-Logger"
          "X-Collection-Status" = "SUCCESS"
        }
      }
      policy = {
        timeout                = "00:01:00"
        retry                  = 1
        retryIntervalInSeconds = 15
      }
    }
  ])

  # Folder organization
  folder = "iRail Data Collection"

  # Annotations for better organization
  annotations = [
    "iRail",
    "Train Data",
    "Automated Collection",
    "Every 5 Minutes"
  ]
}

# Secondary pipeline for enhanced data collection (all stations individually)
resource "azurerm_data_factory_pipeline" "irail_enhanced_collection" {
  name            = "pipeline_irail_enhanced_collection"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  description = "Enhanced collection pipeline that calls liveboard for each major station individually"

  # Pipeline parameters
  parameters = {
    "execution_timestamp" = "@utcnow()"
    "station_limit"       = "10"
    "station_list" = jsonencode([
      "Brussels-Central",
      "Brussels-North",
      "Brussels-South",
      "Antwerp-Central",
      "Ghent-Sint-Pieters",
      "Leuven",
      "Charleroi-Sud",
      "Bruges",
      "Liege-Guillemins"
    ])
  }

  # Enhanced activities for individual station collection
  activities_json = jsonencode([
    # ForEach activity to process each station
    {
      name = "ProcessEachStation"
      type = "ForEach"
      typeProperties = {
        items = {
          value = "@pipeline().parameters.station_list"
          type  = "Expression"
        }
        isSequential = false # Parallel processing for efficiency
        batchCount   = 3     # Process 3 stations at a time
        activities = [
          {
            name = "CollectStationData"
            type = "WebActivity"
            typeProperties = {
              url = {
                value = "@concat('https://irail-functions-simple.azurewebsites.net/api/liveboard?station=', item(), '&limit=', pipeline().parameters.station_limit)"
                type  = "Expression"
              }
              method = "GET"
              headers = {
                "Content-Type" = "application/json"
                "User-Agent"   = "Azure-Data-Factory-Station-Collector"
                "X-Station"    = "@{item()}"
              }
            }
            policy = {
              timeout                = "00:03:00"
              retry                  = 2
              retryIntervalInSeconds = 45
            }
          }
        ]
      }
    }
  ])

  # Folder organization
  folder = "iRail Data Collection"

  # Annotations
  annotations = [
    "iRail",
    "Enhanced Collection",
    "Individual Stations",
    "Parallel Processing"
  ]
}

# Error handling pipeline
resource "azurerm_data_factory_pipeline" "irail_error_handler" {
  name            = "pipeline_irail_error_handler"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  description = "Handles errors and sends notifications when data collection fails"

  # Parameters for error handling
  parameters = {
    "error_message"       = ""
    "failed_activity"     = ""
    "execution_timestamp" = "@utcnow()"
  }

  # Error handling activities
  activities_json = jsonencode([
    # Log error details
    {
      name = "LogError"
      type = "WebActivity"
      typeProperties = {
        url    = "https://irail-functions-simple.azurewebsites.net/api/debug"
        method = "GET"
        headers = {
          "Content-Type"        = "application/json"
          "User-Agent"          = "Azure-Data-Factory-Error-Logger"
          "X-Error-Message"     = "@{pipeline().parameters.error_message}"
          "X-Failed-Activity"   = "@{pipeline().parameters.failed_activity}"
          "X-Collection-Status" = "ERROR"
        }
      }
      policy = {
        timeout                = "00:01:00"
        retry                  = 1
        retryIntervalInSeconds = 15
      }
    }
  ])

  # Folder organization
  folder = "iRail Data Collection/Error Handling"

  # Annotations
  annotations = [
    "iRail",
    "Error Handling",
    "Notifications",
    "Monitoring"
  ]
}

# ============================================================================
# WARMUP PIPELINE - Keep Functions Alive
# ============================================================================

resource "azurerm_data_factory_pipeline" "irail_function_warmup" {
  name            = "pipeline_irail_function_warmup"
  data_factory_id = azurerm_data_factory.irail_data_factory.id
  description     = "Keeps Azure Functions warm to prevent cold starts and timeouts"

  folder = "iRail Data Collection/Maintenance"

  parameters = {
    "execution_timestamp" = "@utcnow()"
    "warmup_type"         = "regular"
  }

  activities_json = jsonencode([
    # Step 1: Function Warmup
    {
      "name" : "WarmupFunction"
      "type" : "WebActivity"
      "policy" : {
        "timeout" : "00:02:00"
        "retry" : 2
        "retryIntervalInSeconds" : 15
      }
      "typeProperties" : {
        "url" : "https://irail-functions-simple.azurewebsites.net/api/warmup"
        "method" : "GET"
        "headers" : {
          "Content-Type" : "application/json"
          "User-Agent" : "Azure-Data-Factory-Function-Warmup"
          "X-Warmup-Type" : "@{pipeline().parameters.warmup_type}"
        }
      }
    },

    # Step 2: Health Verification
    {
      "name" : "VerifyHealth"
      "type" : "WebActivity"
      "dependsOn" : [
        {
          "activity" : "WarmupFunction"
          "dependencyConditions" : ["Succeeded"]
        }
      ]
      "policy" : {
        "timeout" : "00:01:00"
        "retry" : 1
        "retryIntervalInSeconds" : 10
      }
      "typeProperties" : {
        "url" : "https://irail-functions-simple.azurewebsites.net/api/health"
        "method" : "GET"
        "headers" : {
          "Content-Type" : "application/json"
          "User-Agent" : "Azure-Data-Factory-Health-Check"
        }
      }
    },

    # Step 3: Test iRail API Connection
    {
      "name" : "TestiRailConnection"
      "type" : "WebActivity"
      "dependsOn" : [
        {
          "activity" : "VerifyHealth"
          "dependencyConditions" : ["Succeeded"]
        }
      ]
      "policy" : {
        "timeout" : "00:01:00"
        "retry" : 1
        "retryIntervalInSeconds" : 10
      }
      "typeProperties" : {
        "url" : "https://irail-functions-simple.azurewebsites.net/api/debug"
        "method" : "GET"
        "headers" : {
          "Content-Type" : "application/json"
          "User-Agent" : "Azure-Data-Factory-Connection-Test"
          "X-Test-Type" : "warmup"
        }
      }
    }
  ])

  annotations = [
    "iRail",
    "Function Warmup",
    "Cold Start Prevention",
    "Performance"
  ]
}
