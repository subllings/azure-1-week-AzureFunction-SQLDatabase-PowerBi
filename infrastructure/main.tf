terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  # Backend configuration for state management with Azure AD authentication
###  backend "azurerm" {
###    resource_group_name  = "rg-iraildata"
###    storage_account_name = "irailstorage1754441353"
###    container_name       = "tfstate"
###    key                  = "adf-iRail.tfstate"
###    use_azuread_auth     = true
###  }
}
# Azure Train Data Project - Terraform Configuration
# Hardcore Level: Full CI/CD with Infrastructure as Code


# Configure the Microsoft Azure Provider
provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Random suffix for resource naming (alternative reference for compatibility)
resource "random_string" "resource_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for configuration
locals {
  project_name    = "irail"
  environment     = "dev"
  location        = "francecentral"
  resource_prefix = "${local.project_name}-${local.environment}"
  resource_suffix = random_string.suffix.result
  
  # Common tags
  common_tags = {
    Project     = "Azure Train Data Pipeline"
    Environment = local.environment
    ManagedBy   = "Terraform"
    Repository  = "azure-1-week-subllings"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}-${local.resource_suffix}"
  location = local.location
  tags     = local.common_tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "st${replace(local.resource_prefix, "-", "")}${local.resource_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = local.common_tags
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${local.resource_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id
  
  tags = local.common_tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.resource_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                = "kv-${local.resource_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = "standard"
  
  # Enable for deployment
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  
  # Soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  tags = local.common_tags
}

# Current client configuration
data "azurerm_client_config" "current" {}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Import", "Delete", "Purge"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Purge"
  ]
}



# User Assigned Managed Identity for Function App
resource "azurerm_user_assigned_identity" "function_identity" {
  name                = "id-${local.resource_prefix}-func-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Container Registry (for containerized deployment option)
resource "azurerm_container_registry" "main" {
  name                = "cr${replace(local.resource_prefix, "-", "")}${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  
  tags = local.common_tags
}

# Role assignment: Function App Managed Identity -> Container Registry
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.function_identity.principal_id
}
