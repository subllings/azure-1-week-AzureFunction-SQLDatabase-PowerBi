#!/bin/bash

# =============================================================================
# Azure Function App Deployment Script - Staging Environment
# =============================================================================
# This script deploys the Azure Function code to the staging environment
# and verifies all endpoints are working correctly.
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Function App infrastructure already deployed (Y1 plan)
# - Python virtual environment activated
#
# Usage: ./scripts/deploy-function-staging.sh
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Staging Environment
RESOURCE_GROUP="rg-irail-dev-b7m2sk"
FUNCTION_APP_NAME="func-irail-dev-b7m2sk"
FUNCTION_APP_URL="https://func-irail-dev-b7m2sk.azurewebsites.net"
SOURCE_DIR="azure_function"
BUILD_DIR="azure_function"

echo -e "${BLUE}🚀 Starting Azure Function App Deployment - Staging Environment${NC}"
echo "=================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Function App: $FUNCTION_APP_NAME"
echo "Source Directory: $SOURCE_DIR"
echo ""

# Function to print status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
echo -e "${BLUE}🔍 Checking Prerequisites${NC}"
echo "================================"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi
print_success "Azure CLI is installed"

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi
print_success "Logged in to Azure"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    print_error "Source directory '$SOURCE_DIR' not found"
    exit 1
fi
print_success "Source directory found: $SOURCE_DIR"

# Check if function_app.py exists
if [ ! -f "$SOURCE_DIR/function_app.py" ]; then
    print_error "function_app.py not found in $SOURCE_DIR"
    exit 1
fi
print_success "Function app code found"

# Check if requirements.txt exists
if [ ! -f "$SOURCE_DIR/requirements.txt" ]; then
    print_error "requirements.txt not found in $SOURCE_DIR"
    exit 1
fi
print_success "Requirements file found"

echo ""

# Verify Function App exists
echo -e "${BLUE}🔍 Verifying Function App Infrastructure${NC}"
echo "============================================="

if ! az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Function App '$FUNCTION_APP_NAME' not found in resource group '$RESOURCE_GROUP'"
    print_error "Please deploy the infrastructure first using terraform"
    exit 1
fi
print_success "Function App '$FUNCTION_APP_NAME' exists"

# Get Function App status
FUNCTION_STATUS=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv)
print_status "Current Function App status: $FUNCTION_STATUS"

echo ""

# Prepare deployment package
echo -e "${BLUE}📦 Preparing Deployment Package${NC}"
echo "=================================="

cd "$BUILD_DIR"

# Remove existing ZIP if it exists
if [ -f "function_app.zip" ]; then
    rm function_app.zip
    print_status "Removed existing deployment package"
fi

# Create deployment ZIP
print_status "Creating deployment package..."
zip -r function_app.zip . -x "*.git*" "*__pycache__*" "*.pyc" "*.env*" ".venv/*" ".python_packages/*" "*.zip"

if [ -f "function_app.zip" ]; then
    ZIP_SIZE=$(du -h function_app.zip | cut -f1)
    print_success "Deployment package created: function_app.zip ($ZIP_SIZE)"
else
    print_error "Failed to create deployment package"
    exit 1
fi

cd ..

echo ""

# Deploy Function App
echo -e "${BLUE}🚀 Deploying Function App Code${NC}"
echo "==============================="

print_status "Deploying code to Function App '$FUNCTION_APP_NAME'..."

if az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --src "$SOURCE_DIR/function_app.zip" \
    --timeout 600; then
    print_success "Function App code deployed successfully"
else
    print_error "Failed to deploy Function App code"
    exit 1
fi

echo ""

# Wait for deployment to complete
echo -e "${BLUE}⏳ Waiting for Deployment to Complete${NC}"
echo "======================================"

print_status "Waiting 30 seconds for Function App to initialize..."
sleep 30

# Restart Function App to ensure clean start
print_status "Restarting Function App for clean initialization..."
if az functionapp restart --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP"; then
    print_success "Function App restarted successfully"
else
    print_warning "Failed to restart Function App, but deployment may still work"
fi

print_status "Waiting additional 30 seconds for restart to complete..."
sleep 30

echo ""

# Test Function App endpoints
echo -e "${BLUE}🧪 Testing Function App Endpoints${NC}"
echo "=================================="

# Array of endpoints to test
declare -a endpoints=(
    "/api/health:Health Check"
    "/api/stations:Stations API"
    "/api/connections:Connections API"  
    "/api/liveboard:Liveboard API"
)

SUCCESS_COUNT=0
TOTAL_COUNT=${#endpoints[@]}

for endpoint_info in "${endpoints[@]}"; do
    IFS=':' read -r endpoint description <<< "$endpoint_info"
    FULL_URL="${FUNCTION_APP_URL}${endpoint}"
    
    print_status "Testing $description: $endpoint"
    
    # Test with timeout and retry logic
    RESPONSE_CODE=0
    for attempt in 1 2 3; do
        if RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$FULL_URL" 2>/dev/null); then
            break
        else
            if [ $attempt -lt 3 ]; then
                print_warning "Attempt $attempt failed, retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done
    
    if [ "$RESPONSE_CODE" -eq 200 ]; then
        print_success "$description: OK (HTTP $RESPONSE_CODE)"
        ((SUCCESS_COUNT++))
    elif [ "$RESPONSE_CODE" -eq 0 ]; then
        print_error "$description: Connection failed or timeout"
    else
        print_error "$description: HTTP $RESPONSE_CODE"
    fi
done

echo ""

# Final deployment report
echo -e "${BLUE}📊 Deployment Summary${NC}"
echo "====================="
echo "Function App: $FUNCTION_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "URL: $FUNCTION_APP_URL"
echo "Endpoints tested: $SUCCESS_COUNT/$TOTAL_COUNT successful"

if [ $SUCCESS_COUNT -eq $TOTAL_COUNT ]; then
    echo ""
    print_success "🎉 Deployment completed successfully!"
    print_success "All endpoints are responding correctly"
    echo ""
    echo "Available endpoints:"
    echo "- Health Check: ${FUNCTION_APP_URL}/api/health"
    echo "- Stations: ${FUNCTION_APP_URL}/api/stations"
    echo "- Connections: ${FUNCTION_APP_URL}/api/connections"
    echo "- Liveboard: ${FUNCTION_APP_URL}/api/liveboard"
    echo ""
    echo "You can now use these endpoints for testing and integration."
    exit 0
else
    echo ""
    print_warning "⚠️  Deployment completed with issues"
    print_warning "$((TOTAL_COUNT - SUCCESS_COUNT)) endpoint(s) failed"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check Function App logs in Azure Portal"
    echo "2. Verify environment variables are set correctly"
    echo "3. Check Application Insights for errors"
    echo "4. Ensure SQL Database connection is working"
    echo ""
    echo "Function App URL: $FUNCTION_APP_URL"
    echo "Resource Group: $RESOURCE_GROUP"
    exit 1
fi
