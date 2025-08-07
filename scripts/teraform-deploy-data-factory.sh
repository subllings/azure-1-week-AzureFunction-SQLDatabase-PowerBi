#!/bin/bash

# =============================================================================
# Azure Data Factory Deployment Script - iRail Train Data Collection
# =============================================================================
# This script automatically deploys Azure Data Factory with all pipelines,
# triggers, and monitoring for reliable train data collection every 5 minutes
#
# cd /e/_SoftEng/_BeCode/azure-1-week-subllings
# chmod +x ./scripts/deploy-data-factory.sh
# ./scripts/deploy-data-factory.sh
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRASTRUCTURE_DIR="$PROJECT_ROOT/infrastructure"

print_header() {
    echo -e "${BLUE}=============================================================================="
    echo -e "Azure Data Factory Deployment - iRail Train Data Collection"
    echo -e "Deploying reliable automation for train data collection every 5 minutes"
    echo -e "==============================================================================${NC}"
    echo ""
}

print_section() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_section "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if infrastructure directory exists
    if [ ! -d "$INFRASTRUCTURE_DIR" ]; then
        print_error "Infrastructure directory not found at $INFRASTRUCTURE_DIR"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

get_current_subscription() {
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_section "Current Azure subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

initialize_terraform() {
    print_section "Initializing Terraform..."
    
    cd "$INFRASTRUCTURE_DIR"
    
    # Initialize Terraform
    terraform init
    
    if [ $? -eq 0 ]; then
        print_success "Terraform initialized successfully"
    else
        print_error "Terraform initialization failed"
        exit 1
    fi
}

plan_deployment() {
    print_section "Planning Data Factory deployment..."
    
    # Create terraform plan
    terraform plan \
        -var="environment=production" \
        -out="data-factory.tfplan"
    
    if [ $? -eq 0 ]; then
        print_success "Terraform plan created successfully"
        
        # Show what will be created
        echo ""
        print_section "Resources to be created:"
        terraform show -json data-factory.tfplan | jq -r '.planned_values.root_module.resources[].type' | sort | uniq -c
    else
        print_error "Terraform planning failed"
        exit 1
    fi
}

deploy_infrastructure() {
    print_section "Deploying Azure Data Factory infrastructure..."
    
    # Apply the terraform plan
    terraform apply "data-factory.tfplan"
    
    if [ $? -eq 0 ]; then
        print_success "Data Factory infrastructure deployed successfully"
    else
        print_error "Infrastructure deployment failed"
        exit 1
    fi
}

get_deployment_outputs() {
    print_section "Getting deployment outputs..."
    
    # Get and display terraform outputs
    DATA_FACTORY_NAME=$(terraform output -raw data_factory_info | jq -r '.name')
    RESOURCE_GROUP_NAME=$(terraform output -raw data_factory_info | jq -r '.resource_group_name')
    MANAGEMENT_URL=$(terraform output -raw data_factory_info | jq -r '.management_url')
    MONITORING_URL=$(terraform output -raw data_factory_info | jq -r '.monitoring_url')
    
    echo ""
    print_success "Deployment completed successfully!"
    echo ""
    echo -e "${BLUE}Data Factory Details:${NC}"
    echo -e "  • Name: ${GREEN}$DATA_FACTORY_NAME${NC}"
    echo -e "  • Resource Group: ${GREEN}$RESOURCE_GROUP_NAME${NC}"
    echo -e "  • Management Studio: ${CYAN}$MANAGEMENT_URL${NC}"
    echo -e "  • Monitoring Dashboard: ${CYAN}$MONITORING_URL${NC}"
}

validate_deployment() {
    print_section "Validating Data Factory deployment..."
    
    # Check if Data Factory exists
    if az datafactory show --name "$DATA_FACTORY_NAME" --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
        print_success "Data Factory exists and is accessible"
    else
        print_error "Data Factory validation failed"
        return 1
    fi
    
    # Check if triggers are created
    TRIGGER_COUNT=$(az datafactory trigger list --factory-name "$DATA_FACTORY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" -o tsv)
    if [ "$TRIGGER_COUNT" -gt 0 ]; then
        print_success "Found $TRIGGER_COUNT trigger(s)"
    else
        print_warning "No triggers found - this might be expected"
    fi
    
    # Check if pipelines are created
    PIPELINE_COUNT=$(az datafactory pipeline list --factory-name "$DATA_FACTORY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" -o tsv)
    if [ "$PIPELINE_COUNT" -gt 0 ]; then
        print_success "Found $PIPELINE_COUNT pipeline(s)"
    else
        print_error "No pipelines found"
        return 1
    fi
}

test_pipeline_connectivity() {
    print_section "Testing pipeline connectivity to Azure Functions..."
    
    # Test the Azure Functions endpoints that Data Factory will call
    FUNCTIONS_BASE_URL="https://irail-functions-simple.azurewebsites.net"
    
    # Test health endpoint
    if curl -s --fail "$FUNCTIONS_BASE_URL/api/health" > /dev/null; then
        print_success "Health endpoint is accessible"
    else
        print_warning "Health endpoint test failed - please verify Functions are running"
    fi
    
    # Test data collection endpoint
    if curl -s --fail "$FUNCTIONS_BASE_URL/api/powerbi-data" > /dev/null; then
        print_success "Data collection endpoint is accessible"
    else
        print_warning "Data collection endpoint test failed"
    fi
    
    # Test analytics endpoint
    if curl -s --fail "$FUNCTIONS_BASE_URL/api/analytics" > /dev/null; then
        print_success "Analytics endpoint is accessible"
    else
        print_warning "Analytics endpoint test failed"
    fi
}

start_triggers() {
    print_section "Starting Data Factory triggers..."
    
    # Get list of triggers
    TRIGGERS=$(az datafactory trigger list --factory-name "$DATA_FACTORY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "[].name" -o tsv)
    
    for trigger in $TRIGGERS; do
        # Check if trigger is already started
        TRIGGER_STATE=$(az datafactory trigger show --factory-name "$DATA_FACTORY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "$trigger" --query "properties.runtimeState" -o tsv)
        
        if [ "$TRIGGER_STATE" = "Started" ]; then
            print_success "Trigger '$trigger' is already started"
        else
            print_section "Starting trigger: $trigger"
            az datafactory trigger start --factory-name "$DATA_FACTORY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "$trigger"
            
            if [ $? -eq 0 ]; then
                print_success "Trigger '$trigger' started successfully"
            else
                print_warning "Failed to start trigger '$trigger'"
            fi
        fi
    done
}

display_management_info() {
    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}Data Factory Management Information${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""
    
    echo -e "${YELLOW}🎯 Quick Access Links:${NC}"
    echo -e "  • Data Factory Studio: ${CYAN}$MANAGEMENT_URL${NC}"
    echo -e "  • Monitoring Dashboard: ${CYAN}$MONITORING_URL${NC}"
    echo -e "  • Azure Portal: ${CYAN}https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DataFactory/factories/$DATA_FACTORY_NAME${NC}"
    echo ""
    
    echo -e "${YELLOW}🔍 Monitoring Commands:${NC}"
    echo -e "  # List recent pipeline runs"
    echo -e "  ${GREEN}az datafactory pipeline-run query --factory-name '$DATA_FACTORY_NAME' --resource-group '$RESOURCE_GROUP_NAME' --last-updated-after '$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)'${NC}"
    echo ""
    echo -e "  # List trigger runs"
    echo -e "  ${GREEN}az datafactory trigger-run query --factory-name '$DATA_FACTORY_NAME' --resource-group '$RESOURCE_GROUP_NAME' --last-updated-after '$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)'${NC}"
    echo ""
    
    echo -e "${YELLOW}⚙️ Management Commands:${NC}"
    echo -e "  # Stop main trigger"
    echo -e "  ${GREEN}az datafactory trigger stop --factory-name '$DATA_FACTORY_NAME' --resource-group '$RESOURCE_GROUP_NAME' --name 'trigger_irail_collection_every_5min'${NC}"
    echo ""
    echo -e "  # Start main trigger"
    echo -e "  ${GREEN}az datafactory trigger start --factory-name '$DATA_FACTORY_NAME' --resource-group '$RESOURCE_GROUP_NAME' --name 'trigger_irail_collection_every_5min'${NC}"
    echo ""
    echo -e "  # Manually trigger pipeline"
    echo -e "  ${GREEN}az datafactory pipeline create-run --factory-name '$DATA_FACTORY_NAME' --resource-group '$RESOURCE_GROUP_NAME' --name 'pipeline_irail_train_data_collection'${NC}"
    echo ""
    
    echo -e "${YELLOW}📊 What happens next:${NC}"
    echo -e "  1. Data Factory will automatically trigger every 5 minutes"
    echo -e "  2. Each run will call your Azure Functions to collect train data"
    echo -e "  3. Data will be stored in your SQL database"
    echo -e "  4. You can monitor all runs in the Data Factory Studio"
    echo ""
    
    echo -e "${GREEN}✅ Data Factory deployment completed successfully!${NC}"
    echo -e "${GREEN}🚄 Train data collection automation is now active!${NC}"
    echo ""
}

cleanup_on_error() {
    if [ $? -ne 0 ]; then
        print_error "Deployment failed. Cleaning up..."
        cd "$INFRASTRUCTURE_DIR"
        
        # Optional: Destroy resources on failure
        # Uncomment if you want automatic cleanup on failure
        # terraform destroy -auto-approve -var="environment=production"
        
        exit 1
    fi
}

# Main execution
main() {
    trap cleanup_on_error ERR
    
    print_header
    check_prerequisites
    get_current_subscription
    initialize_terraform
    plan_deployment
    
    # Ask for confirmation before deploying
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user"
        exit 0
    fi
    
    deploy_infrastructure
    get_deployment_outputs
    validate_deployment
    test_pipeline_connectivity
    start_triggers
    display_management_info
}

# Run the main function
main "$@"
