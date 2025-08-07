#!/bin/bash

# Enhanced Deploy Staging with FC1 support and comprehensive validation
# Script supports multiple password configuration methods and FC1 Flex Consumption
# =============================================================================
# chmod +x ./scripts/deploy-staging-enhanced.sh
# ./scripts/deploy-staging-enhanced.sh

set -e  # Exit on any error

echo "Deploy STAGING environment (FC1 Enhanced)"
echo "=========================================="
echo "Target: FC1 Flex Consumption in France Central"
echo ""

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

# Check Azure authentication and subscription
echo "Checking Azure authentication..."
if ! az account show &> /dev/null; then
    echo "❌ You are not logged in to Azure. Run: az login"
    exit 1
fi

# Show current subscription for confirmation
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
echo "✓ Azure authentication OK"
echo "  Current subscription: $CURRENT_SUBSCRIPTION"
echo "  Subscription ID: $SUBSCRIPTION_ID"
echo ""

# Check France Central availability for FC1
echo "Verifying FC1 availability in France Central..."
FC1_REGIONS=$(az functionapp list-consumption-locations --query "[?contains(name, 'France Central')].name" -o tsv 2>/dev/null || echo "")
if [[ -z "$FC1_REGIONS" ]]; then
    echo "⚠️  Could not verify FC1 availability in France Central"
    echo "   Continuing with deployment (may fail if not supported)"
else
    echo "✓ France Central supports Flex Consumption plans"
fi

# Check Terraform and validate configuration
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed."
    exit 1
fi
echo "✓ Terraform found"

# Validate Terraform configuration
echo "Validating Terraform configuration..."
if ! terraform validate -compact-warnings; then
    echo "❌ Terraform configuration validation failed"
    exit 1
fi
echo "✓ Terraform configuration is valid"

# Check for FC1-specific configuration
echo "Checking FC1 configuration..."
if grep -q 'sku_name.*=.*"FC1"' app-service-plan.tf 2>/dev/null; then
    echo "✓ FC1 App Service Plan configured"
elif grep -q 'sku_name.*=.*"Y1"' app-service-plan.tf 2>/dev/null; then
    echo "⚠️  Found Y1 configuration, FC1 is recommended for better performance"
    echo "   Consider updating sku_name = \"FC1\" in app-service-plan.tf"
else
    echo "⚠️  Could not verify App Service Plan SKU configuration"
fi

# Enhanced password configuration options
echo "Checking SQL password configuration..."
if [ ! -z "$TF_VAR_sql_admin_password" ]; then
    echo "✓ SQL password configured via environment variable"
    # Validate password strength
    if [[ ${#TF_VAR_sql_admin_password} -lt 8 ]]; then
        echo "⚠️  Password should be at least 8 characters long"
    fi
elif grep -q "sql_admin_password.*=" staging.tfvars 2>/dev/null; then
    echo "✓ SQL password configured in staging.tfvars"
else
    echo "❌ SQL password not configured. Options:"
    echo "   1. Add to .env file: TF_VAR_sql_admin_password=YourPassword123!"
    echo "   2. Export environment variable: export TF_VAR_sql_admin_password='YourPassword123!'"
    echo "   3. Add to staging.tfvars: sql_admin_password = \"YourPassword123!\""
    echo ""
    echo "Password requirements:"
    echo "   • At least 8 characters"
    echo "   • Must contain uppercase, lowercase, numbers, and symbols"
    echo "   • Cannot contain username or common patterns"
    exit 1
fi

# Check staging.tfvars exists and has required values
if [ ! -f "staging.tfvars" ]; then
    echo "❌ staging.tfvars not found"
    echo "   Please ensure staging.tfvars exists with required configuration"
    exit 1
fi
echo "✓ staging.tfvars found"

echo ""
echo "🚀 Starting FC1 deployment..."
echo "=============================="

# Initialize Terraform with backend configuration check
echo "Initializing Terraform..."
if ! terraform init -upgrade; then
    echo "❌ Terraform initialization failed"
    exit 1
fi
echo "✓ Terraform initialized successfully"

# Format check
echo "Checking Terraform formatting..."
if ! terraform fmt -check=true; then
    echo "⚠️  Terraform files need formatting. Running terraform fmt..."
    terraform fmt
fi

# Plan deployment with enhanced output
echo ""
echo "Planning staging deployment..."
echo "Target configuration:"
echo "  • Environment: staging"
echo "  • App Service Plan: FC1 (Flex Consumption)"
echo "  • Region: France Central"
echo "  • Database: Basic SKU"
echo ""

if ! terraform plan -var-file="staging.tfvars" -out="staging.tfplan" -detailed-exitcode; then
    PLAN_EXIT_CODE=$?
    if [ $PLAN_EXIT_CODE -eq 1 ]; then
        echo "❌ Terraform plan failed with errors"
        exit 1
    elif [ $PLAN_EXIT_CODE -eq 2 ]; then
        echo "✓ Plan completed - changes detected"
    else
        echo "✓ Plan completed - no changes needed"
    fi
else
    echo "✓ Plan completed - no changes needed"
fi

# Enhanced deployment confirmation
echo ""
echo "📋 Deployment Summary"
echo "===================="
echo "Subscription: $CURRENT_SUBSCRIPTION"
echo "Environment: staging"  
echo "Plan Type: FC1 (Flex Consumption)"
echo "Region: France Central"
echo "Configuration file: staging.tfvars"
echo ""

# Show what will be deployed
echo "Resources to be deployed/updated:"
terraform show -no-color staging.tfplan | grep -E "^\s*[#+~-]" | head -10
echo ""

read -p "Type 'yes' to deploy FC1 staging environment: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled by user"
    exit 0
fi

# Deploy with progress tracking
echo ""
echo "🚀 Deploying FC1 staging environment..."
echo "======================================="
START_TIME=$(date +%s)

if terraform apply "staging.tfplan"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "🎉 FC1 STAGING DEPLOYED SUCCESSFULLY!"
    echo "====================================="
    echo "Deployment completed in ${DURATION} seconds"
    echo ""
    
    # Enhanced output display
    echo "📊 Deployment Results:"
    echo "====================="
    terraform output -json | python3 -m json.tool 2>/dev/null || terraform output
    
    # Post-deployment verification
    echo ""
    echo "🔍 Post-deployment verification..."
    echo "=================================="
    
    # Check if Function App was created
    FUNCTION_APP_NAME=$(terraform output -raw function_app_name 2>/dev/null || echo "")
    if [[ ! -z "$FUNCTION_APP_NAME" ]]; then
        echo "✓ Function App created: $FUNCTION_APP_NAME"
        
        # Check Function App status
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$(terraform output -raw resource_group_name 2>/dev/null)" &> /dev/null; then
            APP_STATE=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$(terraform output -raw resource_group_name)" --query "state" -o tsv 2>/dev/null)
            if [[ "$APP_STATE" == "Running" ]]; then
                echo "✓ Function App is running"
            else
                echo "⚠️  Function App state: $APP_STATE"
            fi
            
            # Check if it's FC1
            SKU_NAME=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$(terraform output -raw resource_group_name)" --query "appServicePlanId" -o tsv 2>/dev/null | xargs -I {} az appservice plan show --ids {} --query "sku.name" -o tsv 2>/dev/null)
            if [[ "$SKU_NAME" == "FC1" ]]; then
                echo "✓ Confirmed FC1 (Flex Consumption) deployment"
            else
                echo "⚠️  App Service Plan SKU: $SKU_NAME (expected FC1)"
            fi
        fi
    fi
    
    # Check SQL Database
    SQL_SERVER_NAME=$(terraform output -raw sql_server_name 2>/dev/null || echo "")
    if [[ ! -z "$SQL_SERVER_NAME" ]]; then
        echo "✓ SQL Server created: $SQL_SERVER_NAME"
    fi
    
    echo ""
    echo "📚 Next steps:"
    echo "=============="
    echo "  1. 🧪 Test Function App endpoints:"
    FUNCTION_URL=$(terraform output -raw function_app_default_hostname 2>/dev/null || echo "")
    if [[ ! -z "$FUNCTION_URL" ]]; then
        echo "     https://$FUNCTION_URL/api/stations"
        echo "     https://$FUNCTION_URL/api/departures?station=008892007"
    fi
    echo "  2. 🗄️  Verify SQL database connectivity"
    echo "  3. 📊 Check Application Insights logs"
    echo "  4. 🚀 Run integration tests"
    echo "  5. 📈 Monitor FC1 performance and scaling"
    echo ""
    echo "💡 Pro tip: FC1 plans support up to 10-minute execution time!"
    echo "   Perfect for data processing and ETL operations."
    
else
    echo ""
    echo "❌ DEPLOYMENT FAILED"
    echo "==================="
    echo "Check the error messages above for details."
    echo ""
    echo "Common FC1 deployment issues:"
    echo "  • Unsupported configuration properties for FC1"
    echo "  • Region availability for Flex Consumption"
    echo "  • Resource quotas or limits"
    echo "  • Authentication/permission issues"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check terraform validate output"
    echo "  2. Verify Azure CLI authentication"
    echo "  3. Review terraform plan for unsupported properties"
    echo "  4. Check Azure portal for partial deployments"
    exit 1
fi
