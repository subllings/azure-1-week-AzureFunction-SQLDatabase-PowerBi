#!/bin/bash
# 🧪 Test Azure DevOps Pipeline Configuration
# Script pour valider la configuration avant déploiement

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
ORGANIZATION_URL="${AZURE_DEVOPS_ORG:-https://dev.azure.com/votre-org}"
PROJECT_NAME="${PROJECT_NAME:-traindata-function-deployment}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-traindata-rg}"

echo -e "${BLUE}🧪 Testing Azure DevOps Configuration${NC}"
echo "======================================"

# Test Azure CLI et connexion
test_azure_connection() {
    echo -e "${YELLOW}🔍 Testing Azure connection...${NC}"
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure${NC}"
        return 1
    fi
    
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    echo -e "${GREEN}✅ Azure connection OK${NC}"
    echo "   Subscription: $SUBSCRIPTION_NAME"
    echo "   ID: $SUBSCRIPTION_ID"
}

# Test Azure DevOps connexion
test_devops_connection() {
    echo -e "${YELLOW}🔍 Testing Azure DevOps connection...${NC}"
    
    if ! az devops project show --project "$PROJECT_NAME" --organization "$ORGANIZATION_URL" &> /dev/null; then
        echo -e "${RED}❌ Cannot access project '$PROJECT_NAME'${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Azure DevOps connection OK${NC}"
    echo "   Project: $PROJECT_NAME"
}

# Test des ressources Azure
test_azure_resources() {
    echo -e "${YELLOW}🔍 Testing Azure resources...${NC}"
    
    # Resource Group
    if ! az group show --name "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        echo -e "${RED}❌ Resource group '$AZURE_RESOURCE_GROUP' not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Resource group exists${NC}"
    
    # Container Registry
    if ! az acr show --name traindataacr1754421294 --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        echo -e "${RED}❌ Container registry 'traindataacr1754421294' not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Container registry exists${NC}"
    
    # Function App
    if ! az functionapp show --name traindata-function-app --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        echo -e "${YELLOW}⚠️ Function app 'traindata-function-app' not found (will be created)${NC}"
    else
        echo -e "${GREEN}✅ Function app exists${NC}"
    fi
    
    # Storage Account
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$AZURE_RESOURCE_GROUP" --query "[].name" -o tsv)
    if [ -z "$STORAGE_ACCOUNTS" ]; then
        echo -e "${YELLOW}⚠️ No storage accounts found (might be needed)${NC}"
    else
        echo -e "${GREEN}✅ Storage accounts found: $STORAGE_ACCOUNTS${NC}"
    fi
}

# Test des Variable Groups
test_variable_groups() {
    echo -e "${YELLOW}🔍 Testing Variable Groups...${NC}"
    
    # function-config
    if ! az pipelines variable-group list --query "[?name=='function-config']" -o tsv | grep -q function-config; then
        echo -e "${RED}❌ Variable group 'function-config' not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Variable group 'function-config' exists${NC}"
    
    # azure-secrets
    if ! az pipelines variable-group list --query "[?name=='azure-secrets']" -o tsv | grep -q azure-secrets; then
        echo -e "${RED}❌ Variable group 'azure-secrets' not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Variable group 'azure-secrets' exists${NC}"
    
    # Vérifier quelques variables importantes
    echo -e "${BLUE}Variable groups content:${NC}"
    az pipelines variable-group list --query "[?name=='function-config'].variables" -o table
}

# Test des Service Connections
test_service_connections() {
    echo -e "${YELLOW}🔍 Testing Service Connections...${NC}"
    
    # Note: Azure CLI ne peut pas facilement lister les service connections
    # Cette fonction guide l'utilisateur pour la vérification manuelle
    
    echo -e "${BLUE}Please verify manually in Azure DevOps portal:${NC}"
    echo "1. Go to Project Settings > Service connections"
    echo "2. Verify 'azure-service-connection' exists and is working"
    echo "3. Verify 'azure-container-registry-connection' exists and is working"
    echo ""
    echo -e "${YELLOW}⚠️ Service connections verification requires manual check${NC}"
}

# Test Docker et ACR
test_docker_acr() {
    echo -e "${YELLOW}🔍 Testing Docker and ACR access...${NC}"
    
    # Test Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Docker available${NC}"
    
    # Test ACR login
    if az acr login --name traindataacr1754421294 &> /dev/null; then
        echo -e "${GREEN}✅ ACR login successful${NC}"
    else
        echo -e "${RED}❌ ACR login failed${NC}"
        return 1
    fi
    
    # Test image pull (optionnel)
    if docker pull traindataacr1754421294.azurecr.io/traindata-function:latest &> /dev/null; then
        echo -e "${GREEN}✅ Can pull existing images${NC}"
    else
        echo -e "${YELLOW}⚠️ No existing images (normal for first deployment)${NC}"
    fi
}

# Test du pipeline YAML
test_pipeline_yaml() {
    echo -e "${YELLOW}🔍 Testing Pipeline YAML...${NC}"
    
    YAML_PATH="../azure-pipelines.yml"
    
    if [ ! -f "$YAML_PATH" ]; then
        echo -e "${RED}❌ Pipeline YAML not found at $YAML_PATH${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Pipeline YAML exists${NC}"
    
    # Validation basique du YAML
    if command -v python3 &> /dev/null; then
        python3 -c "
import yaml
try:
    with open('$YAML_PATH', 'r') as f:
        yaml.safe_load(f)
    print('✅ YAML syntax valid')
except Exception as e:
    print(f'❌ YAML syntax error: {e}')
    exit(1)
        " || return 1
    fi
}

# Test de connectivité réseau
test_network_connectivity() {
    echo -e "${YELLOW}🔍 Testing network connectivity...${NC}"
    
    # Test Azure endpoints
    if curl -s --max-time 5 https://management.azure.com/ > /dev/null; then
        echo -e "${GREEN}✅ Azure management endpoint reachable${NC}"
    else
        echo -e "${RED}❌ Cannot reach Azure management endpoint${NC}"
    fi
    
    # Test ACR endpoint
    if curl -s --max-time 5 https://traindataacr1754421294.azurecr.io/v2/ > /dev/null; then
        echo -e "${GREEN}✅ ACR endpoint reachable${NC}"
    else
        echo -e "${RED}❌ Cannot reach ACR endpoint${NC}"
    fi
    
    # Test Azure DevOps endpoint
    if curl -s --max-time 5 "$ORGANIZATION_URL" > /dev/null; then
        echo -e "${GREEN}✅ Azure DevOps endpoint reachable${NC}"
    else
        echo -e "${RED}❌ Cannot reach Azure DevOps endpoint${NC}"
    fi
}

# Rapport final
generate_report() {
    echo ""
    echo -e "${BLUE}📊 Test Summary${NC}"
    echo "==============="
    
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! Configuration is ready for deployment.${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Run the pipeline in Azure DevOps"
        echo "2. Monitor the deployment logs"
        echo "3. Test the deployed function endpoints"
    else
        echo -e "${RED}❌ Some tests failed:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "   - $test"
        done
        echo ""
        echo -e "${YELLOW}Please fix the issues before proceeding with deployment.${NC}"
    fi
}

# Fonction principale
main() {
    FAILED_TESTS=()
    
    echo -e "${BLUE}Starting comprehensive configuration test...${NC}"
    echo ""
    
    # Exécuter tous les tests
    test_azure_connection || FAILED_TESTS+=("Azure connection")
    echo ""
    
    test_devops_connection || FAILED_TESTS+=("Azure DevOps connection")
    echo ""
    
    test_azure_resources || FAILED_TESTS+=("Azure resources")
    echo ""
    
    test_variable_groups || FAILED_TESTS+=("Variable groups")
    echo ""
    
    test_service_connections || FAILED_TESTS+=("Service connections")
    echo ""
    
    test_docker_acr || FAILED_TESTS+=("Docker/ACR access")
    echo ""
    
    test_pipeline_yaml || FAILED_TESTS+=("Pipeline YAML")
    echo ""
    
    test_network_connectivity || FAILED_TESTS+=("Network connectivity")
    echo ""
    
    generate_report
}

# Gestion des arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo "Test the complete Azure DevOps configuration for deployment readiness"
        echo ""
        echo "Environment variables:"
        echo "  AZURE_DEVOPS_ORG: Azure DevOps organization URL"
        echo "  PROJECT_NAME: Name of the Azure DevOps project"
        echo "  AZURE_RESOURCE_GROUP: Azure resource group name"
        exit 0
        ;;
    *)
        main
        ;;
esac
