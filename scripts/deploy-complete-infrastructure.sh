#!/bin/bash

# =============================================================================
# Complete Infrastructure Deployment Script - iRail Azure Data Factory
# =============================================================================
# This script handles everything:
# 1. Creates backend storage infrastructure
# 2. Configures Terraform backend
# 3. Deploys Azure Data Factory infrastructure
# 4. Activates triggers and validates deployment
# =============================================================================
# Usage: ./scripts/deploy-complete-infrastructure.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
LOCATION="francecentral"
RESOURCE_GROUP="rg-iraildata"
STORAGE_ACCOUNT_PREFIX="irailstorage"
CONTAINER_NAME="tfstate"
STATE_KEY="adf-iRail.tfstate"
TERRAFORM_DIR="infrastructure"

# Generate unique storage account name
TIMESTAMP=$(date +%s)
STORAGE_ACCOUNT="${STORAGE_ACCOUNT_PREFIX}${TIMESTAMP}"

print_header() {
    echo -e "${BLUE}=============================================================================="
    echo -e "Complete Azure Infrastructure Deployment - iRail Data Factory"
    echo -e "Location: $LOCATION"
    echo -e "Resource Group: $RESOURCE_GROUP"
    echo -e "Storage Account: $STORAGE_ACCOUNT"
    echo -e "==============================================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        echo "Run: winget install HashiCorp.Terraform"
        exit 1
    fi
    
    # Check Azure authentication
    if ! az account show &> /dev/null; then
        print_error "Not authenticated with Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "All prerequisites are met"
    
    # Show current account
    ACCOUNT_INFO=$(az account show --query '{name:name, id:id}' -o tsv)
    ACCOUNT_NAME=$(echo "$ACCOUNT_INFO" | cut -f1)
    ACCOUNT_ID=$(echo "$ACCOUNT_INFO" | cut -f2)
    echo -e "  ${BLUE}Using subscription:${NC} $ACCOUNT_NAME"
    echo -e "  ${BLUE}Subscription ID:${NC} $ACCOUNT_ID"
    echo ""
}

create_backend_infrastructure() {
    print_step "Creating backend infrastructure..."
    
    # Create resource group
    echo "Creating resource group: $RESOURCE_GROUP"
    if az group create --name "$RESOURCE_GROUP" --location "$LOCATION" &> /dev/null; then
        print_success "Resource group created/updated"
    else
        print_error "Failed to create resource group"
        exit 1
    fi
    
    # Create storage account
    echo "Creating storage account: $STORAGE_ACCOUNT"
    if az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot &> /dev/null; then
        print_success "Storage account created"
    else
        print_error "Failed to create storage account"
        exit 1
    fi
    
    # Create container
    echo "Creating blob container: $CONTAINER_NAME"
    if az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login &> /dev/null; then
        print_success "Blob container created"
    else
        print_error "Failed to create blob container"
        exit 1
    fi
    
    echo ""
}

configure_terraform_backend() {
    print_step "Configuring Terraform backend..."
    
    # For simplicity, we'll use local state for now
    # This can be migrated to remote state later if needed
    
    cd "$TERRAFORM_DIR"
    
    # Create backup
    cp main.tf main.tf.backup
    
    # Ensure backend is commented out for local deployment
    sed -i '/backend "azurerm"/,/}/s/^/#/' main.tf
    
    # Also update location to France Central if needed
    sed -i 's/westeurope/francecentral/g' main.tf
    sed -i 's/West Europe/France Central/g' main.tf
    
    print_success "Terraform configured for local state"
    print_warning "Using local state file - consider migrating to remote state for production"
    echo ""
    
    cd ..
}

initialize_terraform() {
    print_step "Initializing Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    if terraform init; then
        print_success "Terraform initialized successfully"
    else
        print_error "Terraform initialization failed"
        exit 1
    fi
    
    echo ""
    cd ..
}

validate_and_plan() {
    print_step "Validating and planning Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Validate configuration
    if terraform validate; then
        print_success "Terraform configuration is valid"
    else
        print_error "Terraform validation failed"
        exit 1
    fi
    
    # Create plan
    echo "Creating deployment plan..."
    if terraform plan -out=tfplan; then
        print_success "Terraform plan created successfully"
    else
        print_error "Terraform planning failed"
        exit 1
    fi
    
    echo ""
    cd ..
}

deploy_infrastructure() {
    print_step "Deploying Azure Data Factory infrastructure..."
    
    cd "$TERRAFORM_DIR"
    
    # Apply the plan
    if terraform apply tfplan; then
        print_success "Infrastructure deployed successfully"
    else
        print_error "Infrastructure deployment failed"
        exit 1
    fi
    
    echo ""
    cd ..
}

activate_triggers() {
    print_step "Activating Data Factory triggers..."
    
    cd "$TERRAFORM_DIR"
    
    # Get outputs
    DATA_FACTORY_NAME=$(terraform output -raw data_factory_name 2>/dev/null || echo "")
    
    if [[ -n "$DATA_FACTORY_NAME" ]]; then
        echo "Data Factory: $DATA_FACTORY_NAME"
        
        # Activate triggers
        TRIGGERS=("schedule-5min" "schedule-15min-enhanced" "schedule-daily-maintenance")
        
        for trigger in "${TRIGGERS[@]}"; do
            echo "Activating trigger: $trigger"
            if az datafactory trigger start \
                --factory-name "$DATA_FACTORY_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --name "$trigger" &> /dev/null; then
                print_success "Trigger $trigger activated"
            else
                print_warning "Could not activate trigger $trigger (may not exist or already running)"
            fi
        done
    else
        print_warning "Could not retrieve Data Factory name from Terraform outputs"
    fi
    
    echo ""
    cd ..
}

validate_deployment() {
    print_step "Validating deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Get all outputs
    echo "Terraform outputs:"
    terraform output
    
    # Get Data Factory details
    DATA_FACTORY_NAME=$(terraform output -raw data_factory_name 2>/dev/null || echo "")
    
    if [[ -n "$DATA_FACTORY_NAME" ]]; then
        echo ""
        echo "Checking Data Factory status..."
        
        # Check Data Factory
        if az datafactory show \
            --factory-name "$DATA_FACTORY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "name" -o tsv &> /dev/null; then
            print_success "Data Factory is accessible"
        else
            print_error "Data Factory is not accessible"
        fi
        
        # List pipelines
        echo "Available pipelines:"
        az datafactory pipeline list \
            --factory-name "$DATA_FACTORY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" -o tsv | while read pipeline; do
            echo "  • $pipeline"
        done
        
        # List triggers
        echo "Available triggers:"
        az datafactory trigger list \
            --factory-name "$DATA_FACTORY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].{name:name, state:properties.runtimeState}" -o table
    fi
    
    echo ""
    cd ..
}

show_summary() {
    print_step "Deployment Summary"
    
    echo -e "${GREEN}🎉 Complete infrastructure deployment successful!${NC}"
    echo ""
    echo -e "${BLUE}Infrastructure Details:${NC}"
    echo -e "  • Location: ${CYAN}$LOCATION${NC}"
    echo -e "  • Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "  • Terraform State Storage: ${CYAN}$STORAGE_ACCOUNT${NC}"
    echo ""
    
    cd "$TERRAFORM_DIR"
    DATA_FACTORY_NAME=$(terraform output -raw data_factory_name 2>/dev/null || echo "N/A")
    FUNCTION_APP_NAME=$(terraform output -raw function_app_name 2>/dev/null || echo "N/A")
    cd ..
    
    echo -e "${BLUE}Deployed Resources:${NC}"
    echo -e "  • Azure Data Factory: ${CYAN}$DATA_FACTORY_NAME${NC}"
    echo -e "  • Function App: ${CYAN}$FUNCTION_APP_NAME${NC}"
    echo ""
    
    echo -e "${BLUE}Data Collection Schedule:${NC}"
    echo -e "  • ${GREEN}Every 5 minutes${NC}: Basic train data collection"
    echo -e "  • ${GREEN}Every 15 minutes${NC}: Enhanced data collection with analytics"
    echo -e "  • ${GREEN}Daily at 2 AM${NC}: Maintenance and cleanup tasks"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Monitor Data Factory runs in Azure Portal"
    echo -e "  2. Check Function App logs for data collection"
    echo -e "  3. Verify database is receiving train data every 5 minutes"
    echo -e "  4. Set up monitoring alerts if needed"
    echo ""
    
    echo -e "${BLUE}Monitoring Commands:${NC}"
    echo -e "  • Check pipeline runs: ${CYAN}az datafactory pipeline-run query-by-factory --factory-name $DATA_FACTORY_NAME --resource-group $RESOURCE_GROUP${NC}"
    echo -e "  • Test Function App: ${CYAN}./scripts/test-irail-functions.sh${NC}"
    echo ""
}

cleanup_on_error() {
    if [[ $? -ne 0 ]]; then
        print_error "Deployment failed. Cleaning up..."
        
        # Restore backup if it exists
        if [[ -f "$TERRAFORM_DIR/main.tf.backup" ]]; then
            mv "$TERRAFORM_DIR/main.tf.backup" "$TERRAFORM_DIR/main.tf"
            print_success "Restored main.tf from backup"
        fi
    fi
}

# Set trap for cleanup
trap cleanup_on_error EXIT

main() {
    print_header
    
    # Execute deployment steps
    check_prerequisites
    create_backend_infrastructure
    configure_terraform_backend
    initialize_terraform
    validate_and_plan
    deploy_infrastructure
    activate_triggers
    validate_deployment
    show_summary
    
    # Disable trap on successful completion
    trap - EXIT
    
    # Clean up backup file
    if [[ -f "$TERRAFORM_DIR/main.tf.backup" ]]; then
        rm "$TERRAFORM_DIR/main.tf.backup"
    fi
    
    print_success "Deployment completed successfully!"
}

# Run the main function
main "$@"
