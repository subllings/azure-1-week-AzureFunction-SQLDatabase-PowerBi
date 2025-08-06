#!/bin/bash

# Deploy Staging Environment Only
# Script to deploy only the staging environment

set -e  # Exit on any error

echo "Deploy STAGING environment only"
echo "=============================="

# Check if we're in the right directory
if [ ! -f "infrastructure/main.tf" ]; then
    echo "Error: This script must be executed from the project root"
    echo "Make sure you are in the azure-1-week-subllings folder"
    exit 1
fi

# Check if Azure CLI is logged in
echo "Checking Azure authentication..."
if ! az account show &> /dev/null; then
    echo "You are not logged in to Azure. Run: az login"
    exit 1
fi

echo "Azure authentication OK"

# Navigate to infrastructure directory
cd infrastructure

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Terraform is not installed. Install it from: https://www.terraform.io/downloads.html"
    exit 1
fi

echo "Terraform found"

# Prompt for SQL password if not set
if [ -z "$TF_VAR_sql_admin_password" ]; then
    echo "SQL Admin password required for staging:"
    read -s -p "Enter SQL password (min 8 characters, with uppercase, lowercase, numbers): " SQL_PASSWORD
    echo
    export TF_VAR_sql_admin_password="$SQL_PASSWORD"
fi

# Optionally get developer IP for SQL access
if [ -z "$TF_VAR_developer_ip" ]; then
    echo "Do you want to allow your IP for direct SQL Server access?"
    read -p "Enter your public IP (or press Enter to skip): " DEV_IP
    if [ ! -z "$DEV_IP" ]; then
        export TF_VAR_developer_ip="$DEV_IP"
    fi
fi

echo "Initializing Terraform..."
terraform init

echo "Planning staging deployment..."
terraform plan -var-file="staging.tfvars" -out="staging.tfplan"

echo "Deployment plan generated. Do you want to continue?"
read -p "Type 'yes' to deploy staging: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo "Deploying staging environment..."
terraform apply "staging.tfplan"

if [ $? -eq 0 ]; then
    echo "======================="
    echo "STAGING DEPLOYED SUCCESSFULLY!"
    echo "======================="
    echo ""
    echo "Deployed resources:"
    echo "  - App Service Plan: FC1 (Flex Consumption)"
    echo "  - Azure Functions: Optimized for staging"
    echo "  - SQL Database: Basic SKU"
    echo "  - Storage: LRS"
    echo ""
    echo "Next steps:"
    echo "  1. Configure secrets in Azure DevOps"
    echo "  2. Test API endpoints"
    echo "  3. Verify iRail data collection"
    echo ""
    echo "Terraform outputs:"
    terraform output
else
    echo "Error during deployment"
    exit 1
fi
