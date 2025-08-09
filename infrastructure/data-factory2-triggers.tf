# =============================================================================
# Azure Data Factory 2 Triggers
# =============================================================================

resource "azurerm_data_factory_trigger_schedule" "irail_collection_trigger_v2" {
  name            = "trigger_irail_collection_every_5min_v2"
  data_factory_id = azurerm_data_factory.irail_data_factory2.id
  frequency       = "Minute"
  interval        = 5
  start_time      = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timestamp())
  time_zone       = "UTC"
  description     = "Triggers iRail data collection every 5 minutes (ADF2)"

  pipeline {
    name = azurerm_data_factory_pipeline.irail_train_data_collection_v2.name
    parameters = {
      "execution_timestamp" = "@trigger().scheduledTime"
      "max_retries"         = "3"
    }
  }

  activated = true

  annotations = ["iRail", "Every 5 Minutes", "v2"]
}

resource "azurerm_data_factory_trigger_schedule" "irail_function_warmup_trigger_v2" {
  name            = "trigger_irail_function_warmup_3min_v2"
  data_factory_id = azurerm_data_factory.irail_data_factory2.id
  frequency       = "Minute"
  interval        = 3
  start_time      = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timeadd(timestamp(), "1m"))
  time_zone       = "UTC"
  description     = "Keeps Functions warm (ADF2)"

  pipeline {
    name = azurerm_data_factory_pipeline.irail_function_warmup_v2.name
    parameters = {
      "execution_timestamp" = "@trigger().scheduledTime"
      "warmup_type"         = "scheduled"
    }
  }

  activated   = true
  annotations = ["iRail", "Function Warmup", "v2"]
}
