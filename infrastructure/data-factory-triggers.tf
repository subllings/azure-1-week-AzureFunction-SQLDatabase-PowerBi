# =============================================================================
# Azure Data Factory Triggers for iRail Train Data Collection
# =============================================================================
# This creates the triggers that will automatically execute the pipelines
# every 5 minutes with proper scheduling and error handling
# =============================================================================

# Main trigger - executes every 5 minutes
resource "azurerm_data_factory_trigger_schedule" "irail_collection_trigger" {
  name            = "trigger_irail_collection_every_5min"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  # Schedule configuration - every 5 minutes
  frequency = "Minute"
  interval  = 5

  # Start time (immediate)
  start_time = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timestamp())

  # Timezone
  time_zone = "UTC"

  # Description
  description = "Triggers iRail train data collection every 5 minutes"

  # Annotations
  annotations = [
    "iRail",
    "Every 5 Minutes", 
    "Automated",
    "Production"
  ]

  # Pipeline to trigger
  pipeline {
    name = azurerm_data_factory_pipeline.irail_train_data_collection.name
    parameters = {
      "execution_timestamp" = "@trigger().scheduledTime"
      "max_retries"        = "3"
    }
  }

  # Enable the trigger
  activated = true
}

# Enhanced collection trigger - executes every 15 minutes (less frequent for detailed collection)
resource "azurerm_data_factory_trigger_schedule" "irail_enhanced_trigger" {
  name            = "trigger_irail_enhanced_every_15min"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  # Schedule configuration - every 15 minutes
  frequency = "Minute"
  interval  = 15

  # Start time (immediate + 2 minutes offset to avoid collision)
  start_time = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timeadd(timestamp(), "2m"))

  # Timezone
  time_zone = "UTC"

  # Description
  description = "Triggers enhanced iRail collection (individual stations) every 15 minutes"

  # Annotations
  annotations = [
    "iRail",
    "Every 15 Minutes",
    "Enhanced Collection",
    "Individual Stations"
  ]

  # Pipeline to trigger
  pipeline {
    name = azurerm_data_factory_pipeline.irail_enhanced_collection.name
    parameters = {
      "execution_timestamp" = "@trigger().scheduledTime"
      "station_limit"      = "10"
    }
  }

  # Enable the trigger (can be disabled initially)
  activated = false  # Set to true when you want enhanced collection
}

# Daily maintenance trigger - executes once per day for cleanup and analysis
resource "azurerm_data_factory_trigger_schedule" "irail_daily_maintenance" {
  name            = "trigger_irail_daily_maintenance"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  # Schedule configuration - daily at 2 AM UTC
  frequency = "Day"
  interval  = 1

  # Start time - today at 2 AM UTC
  start_time = formatdate("YYYY-MM-DD'T'02:00:00'Z'", timestamp())

  # Timezone
  time_zone = "UTC"

  # Specific time
  schedule {
    hours   = [2]
    minutes = [0]
  }

  # Description
  description = "Daily maintenance and analysis trigger for iRail data"

  # Annotations
  annotations = [
    "iRail",
    "Daily",
    "Maintenance",
    "Analysis"
  ]

  # Pipeline to trigger (database analytics)
  pipeline {
    name = "pipeline_irail_train_data_collection"  # Use main pipeline for now
    parameters = {
      "execution_timestamp" = "@trigger().scheduledTime"
      "max_retries"        = "5"
    }
  }

  # Enable the trigger
  activated = true
}

# Tumbling window trigger - for precise timing (alternative approach)
resource "azurerm_data_factory_trigger_tumbling_window" "irail_tumbling_window" {
  name            = "trigger_irail_tumbling_window_5min"
  data_factory_id = azurerm_data_factory.irail_data_factory.id

  # Frequency - every 5 minutes
  frequency = "Minute"
  interval  = 5

  # Start time
  start_time = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timestamp())

  # End time (optional - can run indefinitely)
  # end_time = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timeadd(timestamp(), "8760h")) # 1 year

  # Description
  description = "Tumbling window trigger for precise 5-minute intervals"

  # Annotations
  annotations = [
    "iRail",
    "Tumbling Window",
    "Precise Timing",
    "5 Minutes"
  ]

  # Pipeline configuration
  pipeline {
    name = azurerm_data_factory_pipeline.irail_train_data_collection.name
    parameters = {
      "execution_timestamp" = "@trigger().outputs.windowStartTime"
      "max_retries"        = "3"
    }
  }

  # Retry policy
  retry {
    count    = 3
    interval = 30
  }

  # Enable the trigger (disabled by default - choose between schedule or tumbling window)
  activated = false  # Set to true if you prefer tumbling window over schedule trigger
}

# ============================================================================
# WARMUP TRIGGER - Keep Functions Alive Every 3 Minutes
# ============================================================================

resource "azurerm_data_factory_trigger_schedule" "irail_function_warmup_trigger" {
  name          = "trigger_irail_function_warmup_3min"
  data_factory_id = azurerm_data_factory.irail_data_factory.id
  description   = "Triggers function warmup every 3 minutes to prevent cold starts"
  
  # Every 3 minutes to keep functions warm
  frequency = "Minute"
  interval  = 3
  
  activated = true
  
  # Start immediately
  start_time = "2024-01-01T00:00:00Z"
  time_zone  = "UTC"
  
  pipeline {
    name = azurerm_data_factory_pipeline.irail_function_warmup.name
    parameters = {
      "execution_timestamp" = "@trigger().scheduledTime"
      "warmup_type"        = "scheduled"
    }
  }
  
  annotations = [
    "iRail",
    "Function Warmup",
    "Every 3 Minutes",
    "Cold Start Prevention"
  ]
}

# Custom event trigger (for manual triggering or external events)
# Temporarily commented out - requires eventgrid_topic_id
# resource "azurerm_data_factory_trigger_custom_event" "irail_custom_event" {
#   name            = "trigger_irail_custom_event"
#   data_factory_id = azurerm_data_factory.irail_data_factory.id
#   eventgrid_topic_id = "" # This needs to be configured with an actual Event Grid topic
# 
#   # Description
#   description = "Custom event trigger for manual or external system triggering"
# 
#   # Subject filter
#   subject_begins_with = "irail"
#   subject_ends_with   = "collection"
# 
#   # Events to listen for
#   events = [
#     "Microsoft.Storage.BlobCreated",
#     "Microsoft.EventGrid.SubscriptionValidationEvent"
#   ]
# 
#   # Annotations
#   annotations = [
#     "iRail",
#     "Custom Events",
#     "Manual Trigger",
#     "External Systems"
#   ]
# 
#   # Pipeline configuration
#   pipeline {
#     name = azurerm_data_factory_pipeline.irail_train_data_collection.name
#     parameters = {
#       "execution_timestamp" = "@trigger().outputs.eventTime"
#       "max_retries"        = "1"
#     }
#   }
# 
#   # Disabled by default
#   activated = false
# }

# Output information about triggers
output "data_factory_triggers_info" {
  description = "Information about the Data Factory triggers"
  value = {
    main_trigger = {
      name        = azurerm_data_factory_trigger_schedule.irail_collection_trigger.name
      frequency   = "${azurerm_data_factory_trigger_schedule.irail_collection_trigger.frequency} - ${azurerm_data_factory_trigger_schedule.irail_collection_trigger.interval}"
      activated   = azurerm_data_factory_trigger_schedule.irail_collection_trigger.activated
      start_time  = azurerm_data_factory_trigger_schedule.irail_collection_trigger.start_time
    }
    enhanced_trigger = {
      name        = azurerm_data_factory_trigger_schedule.irail_enhanced_trigger.name
      frequency   = "${azurerm_data_factory_trigger_schedule.irail_enhanced_trigger.frequency} - ${azurerm_data_factory_trigger_schedule.irail_enhanced_trigger.interval}"
      activated   = azurerm_data_factory_trigger_schedule.irail_enhanced_trigger.activated
      start_time  = azurerm_data_factory_trigger_schedule.irail_enhanced_trigger.start_time
    }
    daily_maintenance = {
      name        = azurerm_data_factory_trigger_schedule.irail_daily_maintenance.name
      frequency   = "${azurerm_data_factory_trigger_schedule.irail_daily_maintenance.frequency} - ${azurerm_data_factory_trigger_schedule.irail_daily_maintenance.interval}"
      activated   = azurerm_data_factory_trigger_schedule.irail_daily_maintenance.activated
      start_time  = azurerm_data_factory_trigger_schedule.irail_daily_maintenance.start_time
    }
  }
}
