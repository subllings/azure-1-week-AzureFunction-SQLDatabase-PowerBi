#!/bin/bash

# Enhanced Deploy Staging with .env support
# Script supports multiple password configuration methods
# =============================================================================
# chmod +x ./scripts/deploy-staging-enhanced.sh
# ./scripts/deploy-staging-enhanced.sh

set -e  # Exit on any error

echo "Deploy STAGING environment (Enhanced)"
echo "===================================="

# Check if we're in the right directory
if [ ! -f "infrastructure/main.tf" ]; then
    echo "Error: This script must be executed from the project root"
    exit 1
fi

# Navigate to infrastructure directory
cd infrastructure

# Load .env file if it exists
if [ -f ".env" ]; then
    echo "Loading environment variables from .env file..."
    set -a  # Automatically export all variables
    source .env
    set +a  # Stop auto-exporting
    echo "✓ Environment variables loaded from .env"
elif [ -f ".env.template" ]; then
    echo "⚠️  Found .env.template but no .env file"
    echo "   Copy .env.template to .env and configure your values:"
    echo "   cp .env.template .env"
    echo ""
fi

# Check Azure authentication
echo "Checking Azure authentication..."
if ! az account show &> /dev/null; then
    echo "You are not logged in to Azure. Run: az login"
    exit 1
fi
echo "✓ Azure authentication OK"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo "Terraform is not installed."
    exit 1
fi
echo "✓ Terraform found"

# Password configuration options
if [ ! -z "$TF_VAR_sql_admin_password" ]; then
    echo "✓ SQL password configured via environment variable"
elif grep -q "sql_admin_password.*=" staging.tfvars 2>/dev/null; then
    echo "✓ SQL password configured in staging.tfvars"
else
    echo "❌ SQL password not configured. Options:"
    echo "   1. Add to .env file: TF_VAR_sql_admin_password=YourPassword123!"
    echo "   2. Export environment variable: export TF_VAR_sql_admin_password='YourPassword123!'"
    echo "   3. Add to staging.tfvars: sql_admin_password = \"YourPassword123!\""
    exit 1
fi

echo ""
echo "🚀 Starting deployment..."

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Plan deployment
echo "Planning staging deployment..."
terraform plan -var-file="staging.tfvars" -out="staging.tfplan"

# Confirm deployment
echo ""
echo "Deployment plan generated. Do you want to continue?"
read -p "Type 'yes' to deploy staging: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

# Deploy
echo "Deploying staging environment..."
terraform apply "staging.tfplan"

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 STAGING DEPLOYED SUCCESSFULLY!"
    echo "================================"
    echo ""
    terraform output
    echo ""
    echo "Next steps:"
    echo "  • Test the Function App endpoints"
    echo "  • Verify SQL database connectivity"
    echo "  • Check Application Insights logs"
else
    echo "❌ Error during deployment"
    exit 1
fi
