#!/bin/bash

# Deploy Production Environment Only
# Script to deploy only the production environment

set -e  # Exit on any error

echo "Deploy PRODUCTION environment only"
echo "================================="

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

# Load production-specific environment variables
if [ -f ".env.production" ]; then
    echo "Loading production environment variables..."
    source .env.production
    echo "✓ Production environment variables loaded"
else
    echo "❌ .env.production file not found in infrastructure directory"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Terraform is not installed. Install it from: https://www.terraform.io/downloads.html"
    exit 1
fi

echo "Terraform found"

# Prompt for SQL password if not set
if [ -z "$TF_VAR_sql_admin_password" ]; then
    echo "SQL Admin password required for production:"
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

echo "Planning production deployment..."
terraform plan -var-file="production.tfvars" -out="production.tfplan"

echo "PRODUCTION deployment plan generated. Do you want to continue?"
echo "WARNING: This will deploy to PRODUCTION environment!"
read -p "Type 'yes' to deploy production: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Production deployment cancelled"
    exit 0
fi

echo "Deploying production environment..."
terraform apply "production.tfplan"

if [ $? -eq 0 ]; then
    echo "========================="
    echo "PRODUCTION DEPLOYED SUCCESSFULLY!"
    echo "========================="
    echo ""
    echo "Deployed resources:"
    echo "  - App Service Plan: EP1 (Elastic Premium)"
    echo "  - Azure Functions: Production-grade configuration"
    echo "  - SQL Database: S2 Standard (50 DTU)"
    echo "  - Storage: GRS (Geo-Redundant)"
    echo ""
    echo "Next steps:"
    echo "  1. Configure production secrets in Azure DevOps"
    echo "  2. Test all API endpoints thoroughly"
    echo "  3. Monitor production metrics and alerts"
    echo "  4. Verify data collection and pipeline execution"
    echo ""
    echo "Terraform outputs:"
    terraform output
else
    echo "Error during production deployment"
    exit 1
fi
