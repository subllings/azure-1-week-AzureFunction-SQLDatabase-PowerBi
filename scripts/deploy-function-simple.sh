#!/bin/bash

# =============================================================================
# Simple Azure Functions Deployment Script - Based on deploy-irail-functions.sh
# =============================================================================
# Uses Azure Functions Core Tools for deployment - much simpler approach
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
    exit 1
}

echo "====================================="
echo " Deploy Functions to Staging (Simple)"
echo "====================================="

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check func core tools
    if ! command -v func &> /dev/null; then
        print_error "Azure Functions Core Tools is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    print_success "Prerequisites check completed"
}

# Get terraform outputs
get_terraform_output() {
    local output_name=$1
    cd infrastructure
    terraform output -raw "$output_name" 2>/dev/null || echo ""
    cd ..
}

# Deploy function with proper requirements
deploy_function_with_requirements() {
    print_info "Creating custom deployment with proper dependencies..."
    
    # Create a temporary directory for the deployment
    temp_dir=$(mktemp -d)
    deployment_dir="$temp_dir/deployment"
    
    # Copy function files
    mkdir -p "$deployment_dir"
    cp -r azure_function/* "$deployment_dir/"
    
    # Ensure we have the right requirements.txt
    cat > "$deployment_dir/requirements.txt" << 'EOF'
# Azure Functions and Core
azure-functions>=1.11.0

# HTTP Requests
requests>=2.28.0

# Database with ODBC support
pyodbc>=5.0.0

# Azure Identity and Authentication
azure-identity>=1.12.0

# Data Processing
pandas>=1.5.0
python-dateutil>=2.8.0

# Environment and Configuration
python-dotenv>=1.0.0
EOF
    
    # Deploy using func core tools
    print_info "Deploying function code using Azure Functions Core Tools..."
    cd "$deployment_dir"
    
    # Deploy to the staging function app
    func azure functionapp publish "$FUNCTION_APP_NAME" --python
    
    cd - > /dev/null
    
    # Clean up
    rm -rf "$temp_dir"
    
    print_success "Function deployed successfully using func core tools"
}

# Get infrastructure outputs
print_info "Getting infrastructure outputs from Terraform..."
FUNCTION_APP_NAME=$(get_terraform_output "function_app_name")

if [ -z "$FUNCTION_APP_NAME" ]; then
    print_error "Could not get function app name from terraform outputs. Please ensure infrastructure is deployed first."
fi

print_info "Function App Name: $FUNCTION_APP_NAME"

# Check prerequisites
check_prerequisites

# Deploy the function
deploy_function_with_requirements

# Test the deployment
print_info "Testing deployment..."
sleep 15

print_info "Testing health endpoint..."
if curl -sf "https://$FUNCTION_APP_NAME.azurewebsites.net/api/health" > /dev/null; then
    print_success "Health endpoint is working"
else
    print_warning "Health endpoint not yet ready (this is normal for new deployments)"
fi

print_success "============================================="
print_success "DEPLOYMENT COMPLETED!"
print_success "============================================="
print_info "Function App URL: https://$FUNCTION_APP_NAME.azurewebsites.net"
print_info ""
print_info "Available Endpoints:"
echo "  • Health Check: https://$FUNCTION_APP_NAME.azurewebsites.net/api/health"
echo "  • Debug Info:   https://$FUNCTION_APP_NAME.azurewebsites.net/api/debug"
echo "  • Stations:     https://$FUNCTION_APP_NAME.azurewebsites.net/api/stations"
echo "  • Analytics:    https://$FUNCTION_APP_NAME.azurewebsites.net/api/analytics"
print_success "============================================="
