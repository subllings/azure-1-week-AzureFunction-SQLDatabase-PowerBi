# Variables for Terraform configuration

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = ""
}

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_admin_password) >= 8
    error_message = "SQL admin password must be at least 8 characters long."
  }
}

variable "developer_ip" {
  description = "Developer IP address for SQL Server firewall"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
  default     = "azure-1-week-subllings"
}

variable "github_organization" {
  description = "GitHub organization or username"
  type        = string
  default     = "becodeorg"
}

# Optional override for the legacy/demo Data Factory name (kept as-is by default)
variable "data_factory_name" {
  description = "Optional explicit name for the Azure Data Factory (legacy/demo)."
  type        = string
  default     = ""
}

# Optional name for the new Data Factory that we deploy alongside the demo one
variable "data_factory2_name" {
  description = "Optional explicit name for the NEW Azure Data Factory (v2). Leave empty to autogenerate."
  type        = string
  default     = ""
}
