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
