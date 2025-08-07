# Staging Environment Configuration
# This file contains variables specific to the staging environment

# Environment identification
environment = "staging"
location    = "West Europe"

# SQL Server configuration for staging
sql_admin_username = "sqladmin"
# sql_admin_password will be loaded from .env file as TF_VAR_sql_admin_password

# Development access
developer_ip = ""  # Set this to your IP for direct SQL access during development

# Resource sizing for staging (cost-optimized)
# App Service Plan: FC1 (Flex Consumption) - Better performance than Y1
# SQL Database: Basic SKU
# Storage: LRS replication
