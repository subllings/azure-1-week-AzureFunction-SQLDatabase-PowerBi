# =============================================================================
# SQL Server and Database for iRail Train Data Storage
# =============================================================================
# This creates the SQL Server and Database for storing train data
# with proper security, backup, and firewall configuration
# =============================================================================

# SQL Server
resource "azurerm_mssql_server" "irail_sql_server" {
  name                         = "sql-${local.project_name}-${local.environment}-${local.resource_suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  
  # Security configuration
  minimum_tls_version = "1.2"
  
  # Azure AD integration
  azuread_administrator {
    login_username = azurerm_user_assigned_identity.function_identity.name
    object_id      = azurerm_user_assigned_identity.function_identity.principal_id
  }
  
  tags = merge(local.common_tags, {
    Component = "SQL Server"
    Purpose   = "Train Data Storage"
  })
}

# SQL Database
resource "azurerm_mssql_database" "irail_database" {
  name         = "sqldb-${local.project_name}-${local.environment}"
  server_id    = azurerm_mssql_server.irail_sql_server.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  
  # SKU based on environment
  # Basic for staging/development
  # S2 (Standard) for production
  sku_name = var.environment == "production" ? "S2" : "Basic"
  
  # Storage configuration - Basic tier max is 2GB
  max_size_gb = var.environment == "production" ? 250 : 2
  
  # Backup configuration
  short_term_retention_policy {
    retention_days = var.environment == "production" ? 35 : 7
  }
  
  long_term_retention_policy {
    weekly_retention  = var.environment == "production" ? "P12W" : "PT0S"
    monthly_retention = var.environment == "production" ? "P12M" : "PT0S"
    yearly_retention  = var.environment == "production" ? "P5Y" : "PT0S"
    week_of_year     = var.environment == "production" ? 1 : null
  }
  
  tags = merge(local.common_tags, {
    Component = "SQL Database"
    Purpose   = "Train Data Storage"
    SKU       = var.environment == "production" ? "S2" : "Basic"
  })
}

# SQL Server Firewall Rule - Allow Azure Services
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.irail_sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# SQL Server Firewall Rule - Allow Developer IP (optional)
resource "azurerm_mssql_firewall_rule" "developer" {
  count            = var.developer_ip != "" ? 1 : 0
  name             = "AllowDeveloperIP"
  server_id        = azurerm_mssql_server.irail_sql_server.id
  start_ip_address = var.developer_ip
  end_ip_address   = var.developer_ip
}

# SQL Server Firewall Rule - Allow Data Factory IP (for data ingestion)
resource "azurerm_mssql_firewall_rule" "data_factory" {
  name             = "AllowDataFactory"
  server_id        = azurerm_mssql_server.irail_sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Store SQL connection string in Key Vault
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.irail_sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.irail_database.name};Authentication=Active Directory Managed Identity;User Id=${azurerm_user_assigned_identity.function_identity.client_id};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_key_vault_access_policy.current
  ]
}

# Store SQL admin connection string in Key Vault (for admin operations)
resource "azurerm_key_vault_secret" "sql_admin_connection_string" {
  name         = "sql-admin-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.irail_sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.irail_database.name};User ID=${var.sql_admin_username};Password=${var.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_key_vault_access_policy.current
  ]
}

# Role assignment: Function App Managed Identity -> SQL Database
resource "azurerm_role_assignment" "sql_contributor" {
  scope                = azurerm_mssql_database.irail_database.id
  role_definition_name = "SQL DB Contributor"
  principal_id         = azurerm_user_assigned_identity.function_identity.principal_id
}

# Output the SQL Server information
output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = azurerm_mssql_server.irail_sql_server.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.irail_sql_server.fully_qualified_domain_name
  sensitive   = true
}

output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = azurerm_mssql_database.irail_database.name
}

output "sql_connection_string" {
  description = "SQL Database connection string with managed identity"
  value       = azurerm_key_vault_secret.sql_connection_string.value
  sensitive   = true
}
