#!/bin/bash

# Enhanced Deploy Staging with FC1 support and comprehensive validation
# Script supports multiple password configuration methods and FC1 Flex Consumption
# =============================================================================
# chmod +x ./scripts/teraform-deploy-staging-enhanced.sh
# ./scripts/teraform-deploy-staging-enhanced.sh

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

# Function to handle post-restart recovery
post_restart_recovery() {
    echo "🔄 Post-restart recovery mode detected"
    echo "====================================="
    
    # Check if Azure login is still valid
    if ! az account show &> /dev/null; then
        echo "❌ Azure authentication expired after restart. Please login again:"
        echo "   az login"
        exit 1
    fi
    
    # Re-initialize Terraform backend (might need re-authentication)
    echo "Re-initializing Terraform backend after restart..."
    if ! $TERRAFORM_CMD init -reconfigure; then
        echo "❌ Terraform re-initialization failed"
        echo "   This is common after machine restart. Try:"
        echo "   1. cd infrastructure"
        echo "   2. terraform init -reconfigure"
        echo "   3. Re-run this script"
        exit 1
    fi
    
    echo "✓ Post-restart recovery completed successfully"
}

echo "Deploy STAGING environment (Y1 Cost-Effective)"
echo "=============================================="
echo "Target: Y1 Consumption Plan (Most Cost-Effective)"
echo ""

# Setup terraform command with PowerShell 7 detection
setup_terraform_command

# Check if this is a post-restart deployment
if [[ "${1:-}" == "--post-restart" ]]; then
    post_restart_recovery
fi

# Check if we're in the right directory
if [ ! -f "infrastructure/main.tf" ]; then
    echo "Error: This script must be executed from the project root"
    exit 1
fi

# Navigate to infrastructure directory
cd infrastructure

# Load .env.staging file if it exists
if [ -f ".env.staging" ]; then
    echo "Loading environment variables from .env.staging file..."
    set -a  # Automatically export all variables
    source .env.staging
    set +a  # Stop auto-exporting
    echo "✓ Environment variables loaded from .env.staging"
elif [ -f ".env" ]; then
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

# Check France Central availability for Y1
echo "Verifying Y1 availability in France Central..."
Y1_REGIONS=$(az functionapp list-consumption-locations --query "[?contains(name, 'France Central')].name" -o tsv 2>/dev/null || echo "")
if [[ -z "$Y1_REGIONS" ]]; then
    echo "⚠️  Could not verify Y1 availability in France Central"
    echo "   Continuing with deployment (should work with Y1 plan)"
else
    echo "✓ France Central supports Consumption plans"
fi

# Check Terraform and validate configuration
if ! command -v $TERRAFORM_CMD &> /dev/null; then
    echo "❌ Terraform is not installed."
    exit 1
fi
echo "✓ Terraform found ($TERRAFORM_CMD)"

# Validate Terraform configuration
echo "Validating Terraform configuration..."
if ! $TERRAFORM_CMD validate -compact-warnings; then
    echo "❌ Terraform configuration validation failed"
    exit 1
fi
echo "✓ Terraform configuration is valid"

# Check for Y1-specific configuration
echo "Checking Y1 configuration..."
if grep -q 'sku_name.*=.*"Y1"' app-service-plan.tf 2>/dev/null; then
    echo "✓ Y1 App Service Plan configured"
elif grep -q 'sku_name.*=.*"FC1"' app-service-plan.tf 2>/dev/null; then
    echo "⚠️  Found FC1 configuration, Y1 is recommended for cost optimization"
    echo "   Consider updating sku_name = \"Y1\" in app-service-plan.tf"
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
echo "🚀 Starting Y1 deployment..."
echo "=============================="

# Initialize Terraform with backend configuration check
echo "Initializing Terraform..."
if ! $TERRAFORM_CMD init -upgrade; then
    echo "❌ Terraform initialization failed"
    exit 1
fi
echo "✓ Terraform initialized successfully"

# Format check
echo "Checking Terraform formatting..."
if ! $TERRAFORM_CMD fmt -check=true; then
    echo "⚠️  Terraform files need formatting. Running terraform fmt..."
    $TERRAFORM_CMD fmt
fi

# Plan deployment with enhanced output
echo ""
echo "Planning staging deployment..."
echo "Target configuration:"
echo "  • Environment: staging"
echo "  • App Service Plan: Y1 (Consumption)"
echo "  • Region: France Central"
echo "  • Database: Basic SKU"
echo ""

if ! $TERRAFORM_CMD plan -var-file="staging.tfvars" -out="staging.tfplan" -detailed-exitcode; then
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
$TERRAFORM_CMD show -no-color staging.tfplan | grep -E "^\s*[#+~-]" | head -10
echo ""

read -p "Type 'yes' to deploy Y1 staging environment: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled by user"
    exit 0
fi

# Deploy with progress tracking
echo ""
echo "🚀 Deploying Y1 staging environment..."
echo "======================================"
START_TIME=$(date +%s)

if $TERRAFORM_CMD apply "staging.tfplan"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "🎉 Y1 STAGING DEPLOYED SUCCESSFULLY!"
    echo "===================================="
    echo "Deployment completed in ${DURATION} seconds"
    echo ""
    
    # Enhanced output display
    echo "📊 Deployment Results:"
    echo "====================="
    $TERRAFORM_CMD output -json | python3 -m json.tool 2>/dev/null || $TERRAFORM_CMD output
    
    # Post-deployment verification
    echo ""
    echo "🔍 Post-deployment verification..."
    echo "=================================="
    
    # Check if Function App was created
    FUNCTION_APP_NAME=$($TERRAFORM_CMD output -raw function_app_name 2>/dev/null || echo "")
    if [[ ! -z "$FUNCTION_APP_NAME" ]]; then
        echo "✓ Function App created: $FUNCTION_APP_NAME"
        
        # Check Function App status
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$($TERRAFORM_CMD output -raw resource_group_name 2>/dev/null)" &> /dev/null; then
            APP_STATE=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$($TERRAFORM_CMD output -raw resource_group_name)" --query "state" -o tsv 2>/dev/null)
            if [[ "$APP_STATE" == "Running" ]]; then
                echo "✓ Function App is running"
            else
                echo "⚠️  Function App state: $APP_STATE"
            fi
            
            # Check if it's Y1
            SKU_NAME=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$($TERRAFORM_CMD output -raw resource_group_name)" --query "appServicePlanId" -o tsv 2>/dev/null | xargs -I {} az appservice plan show --ids {} --query "sku.name" -o tsv 2>/dev/null)
            if [[ "$SKU_NAME" == "Y1" ]]; then
                echo "✓ Confirmed Y1 (Consumption) deployment"
            else
                echo "⚠️  App Service Plan SKU: $SKU_NAME (expected Y1)"
            fi
        fi
    fi
    
    # Check SQL Database
    SQL_SERVER_NAME=$($TERRAFORM_CMD output -raw sql_server_name 2>/dev/null || echo "")
    if [[ ! -z "$SQL_SERVER_NAME" ]]; then
        echo "✓ SQL Server created: $SQL_SERVER_NAME"
    fi
    
    echo ""
    echo "📚 Next steps:"
    echo "=============="
    echo "  1. 🧪 Test Function App endpoints:"
    FUNCTION_URL=$($TERRAFORM_CMD output -raw function_app_default_hostname 2>/dev/null || echo "")
    if [[ ! -z "$FUNCTION_URL" ]]; then
        echo "     https://$FUNCTION_URL/api/stations"
        echo "     https://$FUNCTION_URL/api/departures?station=008892007"
    fi
    echo "  2. 🗄️  Verify SQL database connectivity"
    echo "  3. 📊 Check Application Insights logs"
    echo "  4. 🚀 Run integration tests"
    echo "  5. 📈 Monitor FC1 performance and scaling"
    echo ""
    echo "💡 Pro tip: Y1 plans are the most cost-effective for development!"
    echo "   Perfect for learning and testing Azure Functions."
    
else
    echo ""
    echo "❌ DEPLOYMENT FAILED"
    echo "==================="
    echo "Check the error messages above for details."
    echo ""
    echo "Common Y1 deployment issues:"
    echo "  • Python version compatibility"
    echo "  • Function timeout limits (5 minutes max)"
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
