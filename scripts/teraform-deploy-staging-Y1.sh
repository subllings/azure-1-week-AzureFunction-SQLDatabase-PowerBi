#!/bin/bash

# =============================================================================
# TERAFORM-DEPLOY-STAGING-Y1.sh - AZURE FUNCTIONS Y1 CONSUMPTION PLAN
# =============================================================================
# 
# Y1 PLAN : Azure Functions standard        
# This version deploys Azure Functions using Y1 (Consumption Plan):
# - Y1 SKU: Standard Consumption Plan (pay-per-execution)
# - Shared infrastructure with automatic scaling
# - Python 3.12 runtime support (PYTHON_VERSION=3.12)
# - Complete infrastructure + Azure Functions code deployment
# - Automatic deployment package creation
# - Endpoint testing after deployment
# 
# Y1 Plan Features:
# - Pay-per-execution billing model
# - Automatic scale in/out based on demand
# - Cold starts after inactivity periods
# - No fixed IP or Premium features
# - 5-10 min max execution time
# 
# Best for: Lightweight tasks, event-driven jobs, occasional serverless workloads
# 
# =============================================================================

# Deploy Staging Environment Only
# Script to deploy only the staging environment
# =============================================================================
# chmod +x ./scripts/teraform-deploy-staging-Y1.sh
# ./scripts/teraform-deploy-staging-Y1.sh


set -e  # Exit on any error

# Function to detect PowerShell 7 and set terraform command
setup_terraform_command() {
    if command -v pwsh &> /dev/null; then
        echo "✓ PowerShell 7 detected - using explicit terraform commands"
        TERRAFORM_CMD="terraform"
    else
        echo "✓ Using standard terraform commands"
        TERRAFORM_CMD="terraform"
    fi
    
    # Always use explicit terraform command for clarity
    export TERRAFORM_CMD="terraform"
}

echo "Deploy STAGING environment only"
echo "=============================="

# Setup terraform command with PowerShell 7 detection
setup_terraform_command

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

# Load staging-specific environment variables
if [ -f ".env.staging" ]; then
    echo "Loading staging environment variables..."
    source .env.staging
    echo "✓ Staging environment variables loaded"
else
    echo "⚠️  .env.staging file not found in infrastructure directory"
    echo "   Creating infrastructure/.env.staging with your configuration..."
fi

# Check if Terraform is installed
if ! command -v $TERRAFORM_CMD &> /dev/null; then
    echo "Terraform is not installed. Install it from: https://www.terraform.io/downloads.html"
    echo "or choco install terraform"
    exit 1
fi

echo "Terraform found ($TERRAFORM_CMD)"

# Note: SQL password is configured in staging.tfvars file or .env file
echo "Using SQL password from configuration files"

echo "Initializing Terraform..."
$TERRAFORM_CMD init

echo "Planning staging deployment..."
$TERRAFORM_CMD plan -var-file="staging.tfvars" -out="staging.tfplan"

echo "Deployment plan generated. Do you want to continue?"
read -p "Type 'yes' to deploy staging: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo "Deploying staging environment..."
$TERRAFORM_CMD apply "staging.tfplan"

if [ $? -eq 0 ]; then
    echo "======================="
    echo "INFRASTRUCTURE DEPLOYED SUCCESSFULLY!"
    echo "======================="
    echo ""
    echo "Terraform outputs:"
    $TERRAFORM_CMD output
    echo ""
    
    # Now deploy the function code to the newly created infrastructure
    echo "======================="
    echo "DEPLOYING FUNCTION CODE..."
    echo "======================="
    
    # Navigate back to project root for function deployment
    cd ..
    
    # Function to get Terraform output
    get_terraform_output() {
        local output_name=$1
        cd infrastructure
        $TERRAFORM_CMD output -raw "$output_name" 2>/dev/null || echo ""
        cd ..
    }
    
    # Deploy function code directly
    deploy_function_code() {
        echo ""
        echo -e "\033[0;34m======================================"
        echo -e " Deploy Functions to Staging"
        echo -e "======================================\033[0m"
        
        # Get infrastructure details from Terraform outputs
        FUNCTION_APP_NAME=$(get_terraform_output "function_app_name")
        RESOURCE_GROUP_NAME=$(get_terraform_output "resource_group_name")
        SQL_CONNECTION_STRING=$(get_terraform_output "sql_connection_string")
        
        if [[ -z "$FUNCTION_APP_NAME" ]]; then
            echo -e "\033[0;31m[ERROR]\033[0m Could not retrieve function app name from Terraform outputs"
            exit 1
        fi
        
        echo -e "\033[0;34m[INFO]\033[0m Deploying to Function App: $FUNCTION_APP_NAME"
        echo -e "\033[0;34m[INFO]\033[0m Resource Group: $RESOURCE_GROUP_NAME"
        
        # Navigate to the function directory
        if [[ ! -d "azure_function" ]]; then
            echo -e "\033[0;31m[ERROR]\033[0m azure_function directory not found"
            exit 1
        fi
        
        # Check if function_app.py exists
        if [[ ! -f "azure_function/function_app.py" ]]; then
            echo -e "\033[0;31m[ERROR]\033[0m function_app.py not found in azure_function directory"
            exit 1
        fi
        
        echo -e "\033[0;34m[INFO]\033[0m Setting up function app configuration..."
        
        # Configure app settings for the function app
        echo -e "\033[0;34m[INFO]\033[0m Updating application settings..."
        az functionapp config appsettings set \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --settings \
                "SQL_CONNECTION_STRING=$SQL_CONNECTION_STRING" \
                "IRAIL_API_BASE_URL=https://api.irail.be" \
                "IRAIL_API_FORMAT=json" \
                "IRAIL_API_LANG=en" \
                "PROJECT_NAME=Azure Train Data Pipeline" \
                "ENVIRONMENT=staging" \
                "FUNCTIONS_WORKER_RUNTIME=python" \
                "FUNCTIONS_EXTENSION_VERSION=~4" \
                "PYTHON_VERSION=3.12" \
            --output none
        
        if [[ $? -eq 0 ]]; then
            echo -e "\033[0;32m[SUCCESS]\033[0m Application settings configured successfully"
        else
            echo -e "\033[0;31m[ERROR]\033[0m Failed to configure application settings"
            exit 1
        fi
        
        # Deploy the function code using PowerShell zip
        echo -e "\033[0;34m[INFO]\033[0m Creating deployment package..."
        
        # Use PowerShell to create zip and deploy
        cd azure_function
        powershell -Command "Compress-Archive -Path '.\*' -DestinationPath '..\function-deployment.zip' -Force" 2>/dev/null
        cd ..
        
        if [[ -f "function-deployment.zip" ]]; then
            echo -e "\033[0;34m[INFO]\033[0m Deploying function code..."
            az functionapp deployment source config-zip \
                --name "$FUNCTION_APP_NAME" \
                --resource-group "$RESOURCE_GROUP_NAME" \
                --src "function-deployment.zip" \
                --timeout 300 \
                --output none
            
            # Clean up
            rm -f "function-deployment.zip"
            
            if [[ $? -eq 0 ]]; then
                echo -e "\033[0;32m[SUCCESS]\033[0m Function code deployed successfully"
            else
                echo -e "\033[0;31m[ERROR]\033[0m Failed to deploy function code"
                exit 1
            fi
        else
            echo -e "\033[0;31m[ERROR]\033[0m Failed to create deployment package"
            exit 1
        fi
        
        # Restart the function app
        echo -e "\033[0;34m[INFO]\033[0m Restarting function app to apply changes..."
        az functionapp restart \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --output none
        
        if [[ $? -eq 0 ]]; then
            echo -e "\033[0;32m[SUCCESS]\033[0m Function app restarted successfully"
        else
            echo -e "\033[0;33m[WARNING]\033[0m Function app restart may have failed, but deployment should still work"
        fi
        
        # Get the function app URL
        FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"
        
        echo -e "\033[0;32m[SUCCESS]\033[0m Function deployment completed!"
        echo ""
        echo -e "\033[0;32mFunction App Details:\033[0m"
        echo -e "  Name: $FUNCTION_APP_NAME"
        echo -e "  URL: $FUNCTION_URL"
        echo -e "  Resource Group: $RESOURCE_GROUP_NAME"
        echo ""
        echo -e "\033[0;32mAvailable Endpoints:\033[0m"
        echo -e "  Health Check: $FUNCTION_URL/api/health"
        echo -e "  PowerBI Data: $FUNCTION_URL/api/powerbi-data"
        echo -e "  Analytics: $FUNCTION_URL/api/analytics"
        echo ""
        
        # Test the health endpoint
        echo -e "\033[0;34m[INFO]\033[0m Testing function endpoints..."
        echo -e "\033[0;34m[INFO]\033[0m Waiting for function app to be ready..."
        sleep 30
        
        echo -e "\033[0;34m[INFO]\033[0m Testing health endpoint..."
        if curl -s -f "$FUNCTION_URL/api/health" > /dev/null 2>&1; then
            echo -e "\033[0;32m[SUCCESS]\033[0m Health endpoint is responding"
        else
            echo -e "\033[0;33m[WARNING]\033[0m Health endpoint may not be ready yet (this is normal after deployment)"
        fi
        
        echo -e "\033[0;34m[INFO]\033[0m You can test the endpoints manually with:"
        echo "  curl $FUNCTION_URL/api/health"
        echo "  curl $FUNCTION_URL/api/powerbi-data"
        echo "  curl $FUNCTION_URL/api/analytics"
    }
    
    # Execute function deployment
    deploy_function_code
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "======================================="
        echo "COMPLETE STAGING DEPLOYMENT SUCCESSFUL!"
        echo "======================================="
        echo ""
        echo "✅ Infrastructure deployed:"
        echo "  - App Service Plan: FC1 (Flex Consumption)"
        echo "  - Azure Functions: Optimized for staging"
        echo "  - SQL Database: Basic SKU"
        echo "  - Storage: LRS"
        echo "  - Data Factory: With automated pipelines"
        echo "  - Key Vault: With connection strings"
        echo ""
        echo "✅ Function code deployed:"
        echo "  - iRail API endpoints"
        echo "  - Database connectivity"
        echo "  - Monitoring and health checks"
        echo ""
        echo "🎯 Next steps:"
        echo "  1. Test API endpoints in browser"
        echo "  2. Monitor Data Factory pipeline runs"
        echo "  3. Verify data collection in SQL Database"
        echo "  4. Check Application Insights for telemetry"
        echo ""
        # Get function app name from terraform output
        cd infrastructure
        FUNCTION_APP_NAME=$(terraform output -raw function_app_name 2>/dev/null)
        cd ..
        
        if [ -n "$FUNCTION_APP_NAME" ]; then
            echo "🌐 Your staging function app is ready:"
            echo "   https://${FUNCTION_APP_NAME}.azurewebsites.net"
            echo ""
            echo "📊 Test endpoints:"
            echo "   https://${FUNCTION_APP_NAME}.azurewebsites.net/api/health"
            echo "   https://${FUNCTION_APP_NAME}.azurewebsites.net/api/stations"
            echo "   https://${FUNCTION_APP_NAME}.azurewebsites.net/api/analytics"
        fi
    else
        echo "❌ Function deployment failed, but infrastructure is ready"
        echo "You can manually run: ./scripts/deploy-irail-function-staging.sh"
        exit 1
    fi
else
    echo "❌ Infrastructure deployment failed"
    exit 1
fi
