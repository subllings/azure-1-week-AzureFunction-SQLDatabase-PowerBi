#!/bin/bash
# =============================================================================
# Azure Functions Deployment Script - Staging Environment
# =============================================================================
# Deploys the iRail Functions to the staging environment created by Terraform
# This script uses the infrastructure outputs from the staging deployment
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE} Deploy Functions to Staging${NC}"
    echo -e "${BLUE}=====================================${NC}"
}

# Function to get Terraform output
get_terraform_output() {
    local output_name=$1
    cd infrastructure
    terraform output -raw "$output_name" 2>/dev/null || echo ""
    cd ..
}

deploy_function_code() {
    print_header
    
    # Get infrastructure details from Terraform outputs
    FUNCTION_APP_NAME=$(get_terraform_output "function_app_name")
    RESOURCE_GROUP_NAME=$(get_terraform_output "resource_group_name")
    SQL_CONNECTION_STRING=$(get_terraform_output "sql_connection_string")
    
    if [[ -z "$FUNCTION_APP_NAME" ]]; then
        print_error "Could not retrieve function app name from Terraform outputs"
        print_info "Make sure you've run the staging infrastructure deployment first"
        print_info "  ./scripts/deploy-staging.sh"
        exit 1
    fi
    
    print_info "Deploying to Function App: $FUNCTION_APP_NAME"
    print_info "Resource Group: $RESOURCE_GROUP_NAME"
    
    # Check if Azure CLI is available and user is logged in
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Navigate to the function directory
    if [[ ! -d "azure_function" ]]; then
        print_error "azure_function directory not found"
        exit 1
    fi
    
    cd azure_function
    
    # Check if function_app.py exists
    if [[ ! -f "function_app.py" ]]; then
        print_error "function_app.py not found in azure_function directory"
        exit 1
    fi
    
    print_info "Setting up function app configuration..."
    
    # Configure app settings for the function app
    print_info "Updating application settings..."
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
        print_success "Application settings configured successfully"
    else
        print_error "Failed to configure application settings"
        exit 1
    fi
    
    # Deploy the function code using zip deployment
    print_info "Creating deployment package..."
    
    # Create a temporary directory for deployment
    TEMP_DIR=$(mktemp -d)
    cp -r . "$TEMP_DIR/"
    
    # Remove unnecessary files from deployment package
    cd "$TEMP_DIR"
    rm -rf __pycache__ .git .vscode *.pyc
    
    # Create zip file
    zip -r ../function-deployment.zip . -q
    
    print_info "Deploying function code..."
    
    # Deploy using Azure CLI
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --src "../function-deployment.zip" \
        --timeout 300 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        print_success "Function code deployed successfully"
    else
        print_error "Failed to deploy function code"
        exit 1
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR" "../function-deployment.zip"
    
    # Go back to project root
    cd ..
    
    # Wait for deployment to complete and restart the function app
    print_info "Restarting function app to apply changes..."
    az functionapp restart \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        print_success "Function app restarted successfully"
    else
        print_warning "Function app restart may have failed, but deployment should still work"
    fi
    
    # Get the function app URL
    FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"
    
    print_success "Function deployment completed!"
    echo ""
    echo -e "${GREEN}Function App Details:${NC}"
    echo -e "  Name: $FUNCTION_APP_NAME"
    echo -e "  URL: $FUNCTION_URL"
    echo -e "  Resource Group: $RESOURCE_GROUP_NAME"
    echo ""
    echo -e "${GREEN}Available Endpoints:${NC}"
    echo -e "  Health Check: $FUNCTION_URL/api/health"
    echo -e "  PowerBI Data: $FUNCTION_URL/api/powerbi-data"
    echo -e "  Analytics: $FUNCTION_URL/api/analytics"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  1. Test the endpoints to verify deployment"
    echo -e "  2. Monitor the function logs in Azure Portal"
    echo -e "  3. Check Data Factory pipelines are working correctly"
    echo ""
}

# Test function endpoints
test_endpoints() {
    print_info "Testing function endpoints..."
    
    FUNCTION_APP_NAME=$(get_terraform_output "function_app_name")
    FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"
    
    # Wait a moment for the function app to be ready
    print_info "Waiting for function app to be ready..."
    sleep 30
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    if curl -s -f "$FUNCTION_URL/api/health" > /dev/null; then
        print_success "Health endpoint is responding"
    else
        print_warning "Health endpoint may not be ready yet (this is normal after deployment)"
    fi
    
    print_info "You can test the endpoints manually with:"
    echo "  curl $FUNCTION_URL/api/health"
    echo "  curl $FUNCTION_URL/api/powerbi-data"
    echo "  curl $FUNCTION_URL/api/analytics"
}

# Main execution
main() {
    # Check if we're in the right directory
    if [[ ! -f "azure_function/function_app.py" ]]; then
        print_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Check if infrastructure is deployed
    if [[ ! -f "infrastructure/terraform.tfstate" ]] && [[ ! -f "infrastructure/.terraform/terraform.tfstate" ]]; then
        print_error "Terraform state not found. Please run infrastructure deployment first:"
        print_info "  ./scripts/deploy-staging.sh"
        exit 1
    fi
    
    deploy_function_code
    test_endpoints
    
    print_success "Staging function deployment completed successfully!"
}

# Execute main function
main "$@"
pandas>=1.5.0
python-dateutil>=2.8.0

# Environment and Configuration
python-dotenv>=1.0.0
EOF
    
    # Create startup script for ODBC driver installation
    cat > "$deployment_dir/startup.sh" << 'EOF'
#!/bin/bash
# Install Microsoft ODBC Driver for SQL Server
curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
apt-get update
ACCEPT_EULA=Y apt-get install -y msodbcsql18
apt-get install -y unixodbc-dev
EOF
    
    # Deploy from temporary directory
    print_info "Deploying function code with ODBC support..."
    cd "$deployment_dir"
    func azure functionapp publish "$FUNCTION_APP_NAME" --python
    cd - > /dev/null
    
    # Clean up
    rm -rf "$temp_dir"
    
    print_success "Function deployed with ODBC support"
}

main() {
    print_success "=============================================================================="
    print_success "Starting Azure Functions Deployment - iRail Train Data API with ODBC"
    print_success "=============================================================================="
    
    check_prerequisites
    
    # Create Resource Group
    print_info "Creating resource group: $RESOURCE_GROUP"
    if az group create --name "$RESOURCE_GROUP" --location "$LOCATION" &> /dev/null; then
        print_success "Resource group created or already exists"
    else
        print_warning "Resource group $RESOURCE_GROUP already exists"
    fi
    
    # Create Storage Account
    print_info "Creating storage account: $STORAGE_ACCOUNT"
    if az storage account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 &> /dev/null; then
        print_success "Storage account created"
    else
        print_warning "Storage account $STORAGE_ACCOUNT already exists"
    fi
    
    # Create Function App with Linux OS
    print_info "Creating Function App: $FUNCTION_APP_NAME"
    if az functionapp create \
        --resource-group "$RESOURCE_GROUP" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.12 \
        --functions-version 4 \
        --name "$FUNCTION_APP_NAME" \
        --os-type linux \
        --storage-account "$STORAGE_ACCOUNT" &> /dev/null; then
        print_success "Function App created"
    else
        print_warning "Function App $FUNCTION_APP_NAME already exists"
    fi
    
    # Configure App Settings
    print_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP_NAME" \
        --settings \
            "FUNCTIONS_WORKER_RUNTIME=python" \
            "FUNCTIONS_EXTENSION_VERSION=~4" \
            "SQL_CONNECTION_STRING=$SQL_CONNECTION_STRING" \
            "SQL_SERVER=$SQL_SERVER" \
            "SQL_DATABASE=$SQL_DATABASE" \
            "SQL_USERNAME=$SQL_USERNAME" \
            "IRAIL_API_BASE_URL=https://api.irail.be" \
            "IRAIL_API_FORMAT=json" \
            "IRAIL_API_LANG=en" \
            "ENVIRONMENT=production" \
            "PROJECT_NAME=iRail-Train-Data-API" \
            "WEBSITE_RUN_FROM_PACKAGE=1" \
        > /dev/null
    
    print_success "Function App settings configured"
    
    # Deploy function with ODBC support
    deploy_function_with_requirements
    
    # Wait for deployment to stabilize
    print_info "Waiting for deployment to stabilize..."
    sleep 30
    
    # Test deployment
    print_info "Testing deployment..."
    
    print_info "Testing health endpoint..."
    if curl -sf "https://$FUNCTION_APP_NAME.azurewebsites.net/api/health" > /dev/null; then
        print_success "Health endpoint is working"
    else
        print_error "Health endpoint failed"
    fi
    
    print_info "Testing stations endpoint..."
    if curl -sf "https://$FUNCTION_APP_NAME.azurewebsites.net/api/stations?limit=1" > /dev/null; then
        print_success "Stations endpoint is working"
    else
        print_error "Stations endpoint failed"
    fi
    
    print_info "Testing database analytics endpoint..."
    response=$(curl -s "https://$FUNCTION_APP_NAME.azurewebsites.net/api/analytics")
    if echo "$response" | grep -q '"status": "success"'; then
        print_success "Analytics endpoint is working with database"
    elif echo "$response" | grep -q "Database not configured"; then
        print_warning "Analytics endpoint returned expected database config error"
    else
        print_warning "Analytics endpoint returned unexpected response"
    fi
    
    # Final Results
    print_success "=============================================================================="
    print_success "DEPLOYMENT COMPLETED!"
    print_success "=============================================================================="
    print_info "Function App URL: https://$FUNCTION_APP_NAME.azurewebsites.net"
    print_info ""
    print_info "Available Endpoints:"
    echo "  • Health Check:      https://$FUNCTION_APP_NAME.azurewebsites.net/api/health"
    echo "  • Debug Info:        https://$FUNCTION_APP_NAME.azurewebsites.net/api/debug"
    echo "  • Stations:          https://$FUNCTION_APP_NAME.azurewebsites.net/api/stations"
    echo "  • Liveboard:         https://$FUNCTION_APP_NAME.azurewebsites.net/api/liveboard"
    echo "  • Analytics:         https://$FUNCTION_APP_NAME.azurewebsites.net/api/analytics"
    echo "  • Database Preview:  https://$FUNCTION_APP_NAME.azurewebsites.net/api/database-preview"
    echo "  • PowerBI Data:      https://$FUNCTION_APP_NAME.azurewebsites.net/api/powerbi-data"
    echo "  • PowerBI Original:  https://$FUNCTION_APP_NAME.azurewebsites.net/api/powerbi"
    print_info ""
    print_info "Database Configuration:"
    echo "  • Server: $SQL_SERVER"
    echo "  • Database: $SQL_DATABASE"
    echo "  • Username: $SQL_USERNAME"
    print_info ""
    print_success "ODBC Driver 18 for SQL Server should now be available!"
    print_info "You can now test all endpoints including database-dependent ones!"
    print_success "=============================================================================="
    print_success "Deployment script completed successfully!"
}

# Run the deployment
main "$@"
