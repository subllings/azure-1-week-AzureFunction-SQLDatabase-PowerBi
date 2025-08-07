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
    
    # Deploy the function code using Azure CLI from source
    print_info "Deploying function code from source..."
    
    # Deploy directly from the azure_function directory
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --src azure_function \
        --timeout 300 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        print_success "Function code deployed successfully"
    else
        print_warning "Zip deployment failed, trying alternative deployment method..."
        
        # Alternative: Use PowerShell to create zip and deploy
        powershell -Command "Compress-Archive -Path 'azure_function\*' -DestinationPath 'function-deployment.zip' -Force"
        
        if [[ -f "function-deployment.zip" ]]; then
            az functionapp deployment source config-zip \
                --name "$FUNCTION_APP_NAME" \
                --resource-group "$RESOURCE_GROUP_NAME" \
                --src "function-deployment.zip" \
                --timeout 300 \
                --output none
            
            # Clean up
            rm -f "function-deployment.zip"
            
            if [[ $? -eq 0 ]]; then
                print_success "Function code deployed successfully using alternative method"
            else
                print_error "Failed to deploy function code"
                exit 1
            fi
        else
            print_error "Failed to create deployment package"
            exit 1
        fi
    fi
    
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
