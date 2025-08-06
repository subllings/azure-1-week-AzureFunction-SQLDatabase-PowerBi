# =============================================================================
# Azure Data Factory Outputs and Monitoring
# =============================================================================
# This file contains outputs and monitoring configuration for the Data Factory
# deployment, providing URLs, monitoring dashboards, and operational insights
# =============================================================================

# Data Factory outputs
output "data_factory_info" {
  description = "Information about the deployed Azure Data Factory"
  value = {
    name                = azurerm_data_factory.irail_data_factory.name
    resource_group_name = azurerm_data_factory.irail_data_factory.resource_group_name
    location           = azurerm_data_factory.irail_data_factory.location
    id                 = azurerm_data_factory.irail_data_factory.id
    
    # Management URLs
    management_url = "https://adf.azure.com/en/home?factory=${azurerm_data_factory.irail_data_factory.name}&resourceGroup=${azurerm_data_factory.irail_data_factory.resource_group_name}"
    monitoring_url = "https://adf.azure.com/en/monitoring/pipelineruns?factory=${azurerm_data_factory.irail_data_factory.name}&resourceGroup=${azurerm_data_factory.irail_data_factory.resource_group_name}"
    
    # Identity information
    managed_identity_principal_id = azurerm_data_factory.irail_data_factory.identity[0].principal_id
    
    # Network configuration
    public_network_enabled = azurerm_data_factory.irail_data_factory.public_network_enabled
  }
}

# Pipeline information
output "data_factory_pipelines" {
  description = "Information about the Data Factory pipelines"
  value = {
    main_collection_pipeline = {
      name        = azurerm_data_factory_pipeline.irail_train_data_collection.name
      description = azurerm_data_factory_pipeline.irail_train_data_collection.description
      folder      = azurerm_data_factory_pipeline.irail_train_data_collection.folder
    }
    enhanced_collection_pipeline = {
      name        = azurerm_data_factory_pipeline.irail_enhanced_collection.name
      description = azurerm_data_factory_pipeline.irail_enhanced_collection.description
      folder      = azurerm_data_factory_pipeline.irail_enhanced_collection.folder
    }
    error_handler_pipeline = {
      name        = azurerm_data_factory_pipeline.irail_error_handler.name
      description = azurerm_data_factory_pipeline.irail_error_handler.description
      folder      = azurerm_data_factory_pipeline.irail_error_handler.folder
    }
  }
}

# Monitoring and logging information
output "data_factory_monitoring" {
  description = "Monitoring and logging configuration for Data Factory"
  value = {
    log_analytics_workspace = {
      name                = azurerm_log_analytics_workspace.data_factory_logs.name
      workspace_id        = azurerm_log_analytics_workspace.data_factory_logs.workspace_id
      retention_in_days   = azurerm_log_analytics_workspace.data_factory_logs.retention_in_days
    }
    
    # Direct links to monitoring dashboards
    monitoring_links = {
      pipeline_runs    = "https://portal.azure.com/#@/resource${azurerm_data_factory.irail_data_factory.id}/pipelineruns"
      trigger_runs     = "https://portal.azure.com/#@/resource${azurerm_data_factory.irail_data_factory.id}/triggerruns"
      activity_runs    = "https://portal.azure.com/#@/resource${azurerm_data_factory.irail_data_factory.id}/activityruns"
      log_analytics    = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.data_factory_logs.id}/logs"
    }
    
    # Useful KQL queries for monitoring
    useful_queries = {
      failed_pipeline_runs = "ADFPipelineRun | where Status == 'Failed' | order by TimeGenerated desc"
      trigger_run_summary  = "ADFTriggerRun | summarize count() by TriggerName, Status | order by TriggerName"
      activity_performance = "ADFActivityRun | where TimeGenerated > ago(24h) | summarize avg(Duration) by ActivityName"
      error_analysis      = "ADFPipelineRun | where Status == 'Failed' | project TimeGenerated, PipelineName, Parameters, Error"
    }
  }
}

# Connection and integration information
output "data_factory_connections" {
  description = "Connection information for external integrations"
  value = {
    linked_service = {
      name = azurerm_data_factory_linked_service_web.irail_functions_http.name
      url  = "https://irail-functions-simple.azurewebsites.net"
      type = "HTTP"
    }
    
    # REST API endpoints for external monitoring
    rest_api_endpoints = {
      base_url           = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_data_factory.irail_data_factory.resource_group_name}/providers/Microsoft.DataFactory/factories/${azurerm_data_factory.irail_data_factory.name}"
      pipeline_runs      = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_data_factory.irail_data_factory.resource_group_name}/providers/Microsoft.DataFactory/factories/${azurerm_data_factory.irail_data_factory.name}/pipelineruns"
      trigger_runs       = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_data_factory.irail_data_factory.resource_group_name}/providers/Microsoft.DataFactory/factories/${azurerm_data_factory.irail_data_factory.name}/triggerruns"
    }
  }
}

# Operational commands and scripts
output "data_factory_operations" {
  description = "Useful commands and scripts for Data Factory operations"
  value = {
    # Azure CLI commands
    cli_commands = {
      list_pipeline_runs = "az datafactory pipeline-run query --factory-name ${azurerm_data_factory.irail_data_factory.name} --resource-group ${azurerm_data_factory.irail_data_factory.resource_group_name} --last-updated-after '2024-01-01' --last-updated-before '2025-12-31'"
      list_trigger_runs  = "az datafactory trigger-run query --factory-name ${azurerm_data_factory.irail_data_factory.name} --resource-group ${azurerm_data_factory.irail_data_factory.resource_group_name} --last-updated-after '2024-01-01' --last-updated-before '2025-12-31'"
      start_trigger      = "az datafactory trigger start --factory-name ${azurerm_data_factory.irail_data_factory.name} --resource-group ${azurerm_data_factory.irail_data_factory.resource_group_name} --name ${azurerm_data_factory_trigger_schedule.irail_collection_trigger.name}"
      stop_trigger       = "az datafactory trigger stop --factory-name ${azurerm_data_factory.irail_data_factory.name} --resource-group ${azurerm_data_factory.irail_data_factory.resource_group_name} --name ${azurerm_data_factory_trigger_schedule.irail_collection_trigger.name}"
    }
    
    # PowerShell commands
    powershell_commands = {
      list_pipeline_runs = "Get-AzDataFactoryV2PipelineRun -DataFactoryName '${azurerm_data_factory.irail_data_factory.name}' -ResourceGroupName '${azurerm_data_factory.irail_data_factory.resource_group_name}'"
      trigger_pipeline   = "Invoke-AzDataFactoryV2Pipeline -DataFactoryName '${azurerm_data_factory.irail_data_factory.name}' -ResourceGroupName '${azurerm_data_factory.irail_data_factory.resource_group_name}' -PipelineName '${azurerm_data_factory_pipeline.irail_train_data_collection.name}'"
    }
    
    # Curl commands for manual testing
    curl_commands = {
      test_health_endpoint = "curl -X GET 'https://irail-functions-simple.azurewebsites.net/api/health' -H 'Content-Type: application/json' -H 'User-Agent: Azure-Data-Factory-Test'"
      test_data_collection = "curl -X GET 'https://irail-functions-simple.azurewebsites.net/api/powerbi-data' -H 'Content-Type: application/json' -H 'User-Agent: Azure-Data-Factory-Test'"
      check_analytics     = "curl -X GET 'https://irail-functions-simple.azurewebsites.net/api/analytics' -H 'Content-Type: application/json' -H 'User-Agent: Azure-Data-Factory-Test'"
    }
  }
}

# Summary for easy reference
output "data_factory_summary" {
  description = "Quick summary of the Data Factory deployment"
  value = {
    status = "✅ Data Factory deployed successfully"
    
    key_features = [
      "🕐 Automated data collection every 5 minutes",
      "🔄 Robust retry mechanisms and error handling", 
      "📊 Comprehensive monitoring and logging",
      "🚄 Multiple pipeline strategies (main + enhanced)",
      "⚡ Real-time triggers and scheduling",
      "🛡️ Built-in health checks and validation"
    ]
    
    next_steps = [
      "1. Visit the Data Factory Studio: ${azurerm_data_factory.irail_data_factory.name}",
      "2. Monitor pipeline runs in Azure Portal",
      "3. Check Log Analytics for detailed logs", 
      "4. Validate data collection in your SQL database",
      "5. Enable enhanced collection trigger if needed"
    ]
    
    important_urls = {
      data_factory_studio = "https://adf.azure.com/en/home?factory=${azurerm_data_factory.irail_data_factory.name}&resourceGroup=${azurerm_data_factory.irail_data_factory.resource_group_name}"
      monitoring_dashboard = "https://portal.azure.com/#@/resource${azurerm_data_factory.irail_data_factory.id}/overview"
      log_analytics = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.data_factory_logs.id}/logs"
    }
  }
}
