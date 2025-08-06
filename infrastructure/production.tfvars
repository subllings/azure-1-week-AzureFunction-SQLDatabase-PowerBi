# Production Environment Configuration
# This file contains variables specific to the production environment

# Environment identification
environment = "production"
location    = "West Europe"

# SQL Server configuration for production
sql_admin_username = "sqladmin"
# sql_admin_password will be provided via environment variable TF_VAR_sql_admin_password

# Development access (disabled in production)
developer_ip = ""

# Resource sizing for production (performance-optimized)
# App Service Plan: EP1 (Elastic Premium)
# SQL Database: S2 (Standard) SKU
# Storage: GRS replication for geographic redundancy
