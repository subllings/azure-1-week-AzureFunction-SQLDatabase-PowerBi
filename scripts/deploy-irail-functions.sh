# =============================================================================
# Azure Functions Deployment Script with ODBC Support - iRail Train Data API
# =============================================================================
# This script deploys the iRail Functions to Azure with proper ODBC configuration
# 
# Usage Instructions:
# cd /e/_SoftEng/_BeCode/azure-1-week-subllings  # Navigate to project directory
# chmod +x scripts/*.sh                          # Make scripts executable
# ./scripts/deploy-irail-functions.sh            # Execute this deployment script
# =============================================================================

#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="irail-functions-simple-rg"
FUNCTION_APP_NAME="irail-functions-simple"
STORAGE_ACCOUNT="irailsimplestorage"
LOCATION="westeurope"

# Database configuration - use your provided credentials
SQL_SERVER="traindata-sql-subllings.database.windows.net"
SQL_DATABASE="traindata-db"
SQL_USERNAME="sqladmin"
SQL_PASSWORD="MiLolita421+"
SQL_CONNECTION_STRING="Driver={ODBC Driver 18 for SQL Server};Server=tcp:${SQL_SERVER},1433;Database=${SQL_DATABASE};Uid=${SQL_USERNAME};Pwd=${SQL_PASSWORD};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"

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

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check func core tools
    if ! command -v func &> /dev/null; then
        print_error "Azure Functions Core Tools is not installed. Please install it from https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

deploy_function_with_requirements() {
    print_info "Creating custom deployment with ODBC support..."
    
    # Create a temporary directory for the deployment
    temp_dir=$(mktemp -d)
    deployment_dir="$temp_dir/deployment"
    
    # Copy function files
    mkdir -p "$deployment_dir"
    cp -r azure_function/* "$deployment_dir/"
    
    # Create updated requirements.txt with ODBC dependencies
    cat > "$deployment_dir/requirements.txt" << 'EOF'
# Azure Functions and Core
azure-functions>=1.11.0

# HTTP Requests
requests>=2.28.0

# Database with ODBC support
pyodbc>=5.0.0

# Azure Identity and Authentication
azure-identity>=1.12.0
azure-keyvault-secrets>=4.7.0

# Monitoring and Telemetry
opencensus-ext-azure>=1.1.13
opencensus-ext-requests>=0.8.0
opencensus-ext-logging>=0.1.1

# Data Processing
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
