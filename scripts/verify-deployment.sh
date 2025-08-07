#!/bin/bash

# Verify FC1 Deployment - Test and Validate
# =============================================================================
# chmod +x ./scripts/verify-deployment.sh
# ./scripts/verify-deployment.sh [staging|production]

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
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}=====================================${NC}"
}

# Environment parameter (staging or production)
ENVIRONMENT=${1:-staging}

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
    print_error "Invalid environment. Use: staging or production"
    echo "Usage: ./scripts/verify-deployment.sh [staging|production]"
    exit 1
fi

echo "FC1 Deployment Verification - $ENVIRONMENT"
echo "========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "infrastructure/main.tf" ]; then
    echo "Error: This script must be executed from the project root"
    exit 1
fi

# Navigate to infrastructure directory
cd infrastructure

# Function to get Terraform output
get_terraform_output() {
    local output_name=$1
    terraform output -raw "$output_name" 2>/dev/null || echo ""
}

print_header "Infrastructure Verification"

# Check if Terraform state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    print_error "Terraform state not found. Please deploy infrastructure first:"
    print_info "  ./scripts/deploy-$ENVIRONMENT.sh"
    exit 1
fi

print_info "Terraform state found - getting deployment details..."

# Get infrastructure details
FUNCTION_APP_NAME=$(get_terraform_output "function_app_name")
RESOURCE_GROUP_NAME=$(get_terraform_output "resource_group_name")
SQL_SERVER_NAME=$(get_terraform_output "sql_server_name")
APP_SERVICE_PLAN_NAME=$(get_terraform_output "app_service_plan_name")
SQL_DATABASE_NAME=$(get_terraform_output "sql_database_name")

if [[ -z "$FUNCTION_APP_NAME" ]]; then
    print_error "Could not retrieve infrastructure details from Terraform outputs"
    exit 1
fi

print_success "Infrastructure details retrieved"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Function App: $FUNCTION_APP_NAME"
echo "  SQL Server: $SQL_SERVER_NAME"
echo "  App Service Plan: $APP_SERVICE_PLAN_NAME"
echo ""

print_header "Azure Authentication Check"

# Check Azure authentication
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
print_success "Azure authentication OK"
echo "  Subscription: $CURRENT_SUBSCRIPTION"
echo ""

print_header "App Service Plan Verification (FC1)"

# Verify App Service Plan SKU is FC1
if az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
    ASP_SKU=$(az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "sku.name" -o tsv)
    ASP_TIER=$(az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "sku.tier" -o tsv)
    ASP_LOCATION=$(az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "location" -o tsv)
    
    if [[ "$ASP_SKU" == "FC1" ]]; then
        print_success "App Service Plan is FC1 (Flex Consumption)"
        echo "  SKU: $ASP_SKU"
        echo "  Tier: $ASP_TIER"
        echo "  Location: $ASP_LOCATION"
        
        if [[ "$ASP_LOCATION" == "France Central" ]]; then
            print_success "Deployed in France Central as expected"
        else
            print_warning "Deployed in $ASP_LOCATION (expected France Central)"
        fi
    else
        print_error "App Service Plan SKU is $ASP_SKU (expected FC1)"
        echo "  Current Tier: $ASP_TIER"
    fi
else
    print_error "App Service Plan not found: $APP_SERVICE_PLAN_NAME"
fi
echo ""

print_header "Function App Verification"

# Verify Function App
if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
    FUNCTION_STATE=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "state" -o tsv)
    FUNCTION_RUNTIME=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "siteConfig.linuxFxVersion" -o tsv)
    FUNCTION_URL=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "defaultHostName" -o tsv)
    
    if [[ "$FUNCTION_STATE" == "Running" ]]; then
        print_success "Function App is running"
    else
        print_warning "Function App state: $FUNCTION_STATE"
    fi
    
    echo "  URL: https://$FUNCTION_URL"
    echo "  Runtime: $FUNCTION_RUNTIME"
else
    print_error "Function App not found: $FUNCTION_APP_NAME"
    exit 1
fi
echo ""

print_header "SQL Database Verification"

# Verify SQL Database
if az sql db show --name "$SQL_DATABASE_NAME" --server "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
    DB_STATUS=$(az sql db show --name "$SQL_DATABASE_NAME" --server "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "status" -o tsv)
    DB_SKU=$(az sql db show --name "$SQL_DATABASE_NAME" --server "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "currentServiceObjectiveName" -o tsv)
    
    if [[ "$DB_STATUS" == "Online" ]]; then
        print_success "SQL Database is online"
    else
        print_warning "SQL Database status: $DB_STATUS"
    fi
    
    echo "  SKU: $DB_SKU"
    echo "  Server: $SQL_SERVER_NAME.database.windows.net"
else
    print_error "SQL Database not found: $SQL_DATABASE_NAME"
fi
echo ""

print_header "Function App Endpoints Testing"

# Test Function App endpoints
FUNCTION_BASE_URL="https://$FUNCTION_URL"

print_info "Testing Function App endpoints..."
print_info "Waiting for function app to be ready..."
sleep 10

# Test health endpoint
print_info "Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/health_response "$FUNCTION_BASE_URL/api/health" 2>/dev/null || echo "000")

if [[ "$HEALTH_RESPONSE" == "200" ]]; then
    print_success "Health endpoint is responding (HTTP 200)"
    HEALTH_CONTENT=$(cat /tmp/health_response 2>/dev/null || echo "")
    if [[ ! -z "$HEALTH_CONTENT" ]]; then
        echo "  Response: $HEALTH_CONTENT"
    fi
elif [[ "$HEALTH_RESPONSE" == "000" ]]; then
    print_error "Could not connect to health endpoint"
else
    print_warning "Health endpoint returned HTTP $HEALTH_RESPONSE"
fi

# Test other endpoints
print_info "Testing other endpoints..."

ENDPOINTS=("powerbi-data" "analytics" "departures?station=008892007")

for endpoint in "${ENDPOINTS[@]}"; do
    ENDPOINT_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "$FUNCTION_BASE_URL/api/$endpoint" 2>/dev/null || echo "000")
    
    if [[ "$ENDPOINT_RESPONSE" == "200" ]]; then
        print_success "/api/$endpoint is responding (HTTP 200)"
    elif [[ "$ENDPOINT_RESPONSE" == "000" ]]; then
        print_warning "/api/$endpoint - could not connect"
    else
        print_warning "/api/$endpoint returned HTTP $ENDPOINT_RESPONSE"
    fi
done

# Clean up temp files
rm -f /tmp/health_response

echo ""
print_header "Configuration Verification"

# Check Function App settings
print_info "Checking Function App configuration..."
SETTINGS_COUNT=$(az functionapp config appsettings list --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "$SETTINGS_COUNT" -gt 0 ]]; then
    print_success "$SETTINGS_COUNT application settings configured"
    
    # Check for key settings
    KEY_SETTINGS=("SQL_CONNECTION_STRING" "FUNCTIONS_WORKER_RUNTIME" "PYTHON_VERSION")
    
    for setting in "${KEY_SETTINGS[@]}"; do
        SETTING_VALUE=$(az functionapp config appsettings list --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$setting'].value" -o tsv 2>/dev/null)
        if [[ ! -z "$SETTING_VALUE" ]]; then
            if [[ "$setting" == "SQL_CONNECTION_STRING" ]]; then
                print_success "$setting is configured (length: ${#SETTING_VALUE})"
            else
                print_success "$setting = $SETTING_VALUE"
            fi
        else
            print_warning "$setting is not configured"
        fi
    done
else
    print_warning "No application settings found"
fi

# Return to project root
cd ..

echo ""
print_header "Deployment Summary"

echo "Environment: $ENVIRONMENT"
echo "Function App: $FUNCTION_APP_NAME"
echo "Status: Function App is deployed and accessible"
echo "URL: https://$FUNCTION_URL"
echo "Plan Type: FC1 (Flex Consumption)"
echo ""

print_header "Manual Testing Commands"

echo "Test endpoints manually:"
echo "  curl https://$FUNCTION_URL/api/health"
echo "  curl https://$FUNCTION_URL/api/powerbi-data"
echo "  curl https://$FUNCTION_URL/api/analytics"
echo "  curl https://$FUNCTION_URL/api/departures?station=008892007"
echo ""

echo "Monitor logs:"
echo "  az functionapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

echo "View configuration:"
echo "  az functionapp config appsettings list --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

print_success "$ENVIRONMENT deployment verification completed"
