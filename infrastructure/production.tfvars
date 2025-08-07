# Production Environment Configuration
# This file contains variables specific to the production environment

# Environment identification
environment = "production"
location    = "West Europe"

# SQL Server configuration for production
sql_admin_username = "sqladmin"
# sql_admin_password should be provided via:
#   1. Environment variable: export TF_VAR_sql_admin_password="secure_password"
#   2. Azure DevOps secret variable
#   3. GitHub Actions secret
# NEVER store production passwords in tfvars files!

# Development access (disabled in production)
developer_ip = ""

# Resource sizing for production (performance-optimized)
# App Service Plan: EP1 (Elastic Premium)
# SQL Database: S2 (Standard) SKU
# Storage: GRS replication for geographic redundancy
