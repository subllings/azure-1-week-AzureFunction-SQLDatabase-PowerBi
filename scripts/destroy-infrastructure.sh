#!/bin/bash

# Destroy/Cleanup Terraform Infrastructure
# =============================================================================
# chmod +x ./scripts/destroy-infrastructure.sh
# ./scripts/destroy-infrastructure.sh [staging|production]

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

# Environment parameter (staging or production)
ENVIRONMENT=${1:-staging}

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
    print_error "Invalid environment. Use: staging or production"
    echo "Usage: ./scripts/destroy-infrastructure.sh [staging|production]"
    exit 1
fi

echo "Destroy $ENVIRONMENT Infrastructure"
echo "=================================="
echo ""

# Check if we're in the right directory
if [ ! -f "infrastructure/main.tf" ]; then
    echo "Error: This script must be executed from the project root"
    exit 1
fi

# Navigate to infrastructure directory
cd infrastructure

# Check if Terraform state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    print_warning "No Terraform state found. Nothing to destroy."
    exit 0
fi

# Check if the environment tfvars file exists
if [ ! -f "$ENVIRONMENT.tfvars" ]; then
    print_error "$ENVIRONMENT.tfvars not found"
    exit 1
fi

# Check Azure authentication
echo "Checking Azure authentication..."
if ! az account show &> /dev/null; then
    echo "❌ You are not logged in to Azure. Run: az login"
    exit 1
fi

CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
print_success "Azure authentication OK"
echo "  Subscription: $CURRENT_SUBSCRIPTION"
echo ""

# Check Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed"
    exit 1
fi

# Initialize Terraform
print_info "Initializing Terraform..."
if ! terraform init -upgrade; then
    print_error "Terraform initialization failed"
    exit 1
fi
print_success "Terraform initialized"

# Show what will be destroyed
echo ""
print_info "Planning destruction of $ENVIRONMENT infrastructure..."
terraform plan -destroy -var-file="$ENVIRONMENT.tfvars" -out="$ENVIRONMENT-destroy.tfplan"

# Show resources to be destroyed
echo ""
echo "Resources to be DESTROYED:"
terraform show -no-color "$ENVIRONMENT-destroy.tfplan" | grep -E "^\s*[#-]" | head -20
echo ""

# Destruction confirmation
print_warning "🚨 DESTRUCTION WARNING 🚨"
echo "=========================="
echo "You are about to DESTROY the $ENVIRONMENT environment!"
echo "This will:"
echo "  • Delete ALL Azure resources in the $ENVIRONMENT environment"
echo "  • Remove the Function App and all its data"
echo "  • Delete the SQL Database and all its data"
echo "  • Remove the App Service Plan"
echo "  • Delete monitoring and logging resources"
echo "  • This action CANNOT be undone!"
echo ""

if [[ "$ENVIRONMENT" == "production" ]]; then
    echo "🔥 PRODUCTION DESTRUCTION WARNING 🔥"
    echo "====================================="
    echo "You are about to destroy PRODUCTION resources!"
    echo "This will result in:"
    echo "  • Complete loss of production data"
    echo "  • Service interruption for users"
    echo "  • Potential data recovery costs"
    echo ""
    read -p "Type 'DESTROY-PRODUCTION' to confirm production destruction: " PRODUCTION_CONFIRM
    
    if [ "$PRODUCTION_CONFIRM" != "DESTROY-PRODUCTION" ]; then
        echo "Production destruction cancelled by user"
        exit 0
    fi
else
    read -p "Type 'DESTROY' to confirm $ENVIRONMENT destruction: " STAGING_CONFIRM
    
    if [ "$STAGING_CONFIRM" != "DESTROY" ]; then
        echo "$ENVIRONMENT destruction cancelled by user"
        exit 0
    fi
fi

# Final confirmation
echo ""
print_warning "FINAL CONFIRMATION"
echo "=================="
read -p "Are you absolutely sure you want to destroy $ENVIRONMENT? Type 'YES': " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "YES" ]; then
    echo "Destruction cancelled by user"
    exit 0
fi

# Perform destruction
echo ""
print_info "🔥 Destroying $ENVIRONMENT infrastructure..."
echo "==========================================="
START_TIME=$(date +%s)

if terraform apply "$ENVIRONMENT-destroy.tfplan"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    print_success "🎯 $ENVIRONMENT INFRASTRUCTURE DESTROYED"
    echo "========================================"
    echo "Destruction completed in ${DURATION} seconds"
    echo ""
    
    # Clean up plan files
    rm -f "$ENVIRONMENT-destroy.tfplan"
    rm -f "$ENVIRONMENT.tfplan"
    
    print_info "Cleanup completed"
    echo ""
    echo "What was destroyed:"
    echo "  ✓ Function App and all functions"
    echo "  ✓ App Service Plan (FC1)"
    echo "  ✓ SQL Database and Server"
    echo "  ✓ Storage Account"
    echo "  ✓ Application Insights"
    echo "  ✓ Resource Group (if empty)"
    echo ""
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        print_warning "Production environment has been destroyed"
        echo "Consider:"
        echo "  • Notifying stakeholders of the service interruption"
        echo "  • Checking if any data backup/recovery is needed"
        echo "  • Updating any external systems that depended on this infrastructure"
    fi
    
else
    print_error "Destruction failed"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check the Terraform error messages above"
    echo "2. Some resources might have dependencies preventing deletion"
    echo "3. You might need to manually delete some resources in Azure Portal"
    echo "4. Run terraform refresh and try again"
    
    exit 1
fi

# Return to project root
cd ..

print_success "$ENVIRONMENT infrastructure destruction completed"
