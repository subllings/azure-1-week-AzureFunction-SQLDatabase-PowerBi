#!/bin/bash
# 🚀 Setup Azure DevOps Project and Configuration
# Script pour automatiser la configuration complète du projet Azure DevOps

set -euo pipefail

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuration
ORGANIZATION_URL="${AZURE_DEVOPS_ORG:-https://dev.azure.com/votre-org}"
PROJECT_NAME="${PROJECT_NAME:-traindata-function-deployment}"
REPO_URL="${REPO_URL:-https://github.com/becodeorg/azure-1-week-subllings}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-traindata-rg}"

echo -e "${BLUE}🚀 Azure DevOps Setup for TrainData Function Deployment${NC}"
echo "=================================================="

# Vérifier les prérequis
check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
    
    # Azure CLI
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI not found. Please install it first.${NC}"
        exit 1
    fi
    
    # Azure DevOps extension
    if ! az extension list | grep -q azure-devops; then
        echo -e "${YELLOW}📦 Installing Azure DevOps extension...${NC}"
        az extension add --name azure-devops
    fi
    
    # Login Azure
    if ! az account show &> /dev/null; then
        echo -e "${YELLOW}🔐 Please login to Azure...${NC}"
        az login
    fi
    
    # Login Azure DevOps
    echo -e "${YELLOW}🔐 Please login to Azure DevOps...${NC}"
    az devops login --organization "$ORGANIZATION_URL"
    
    echo -e "${GREEN}✅ Prerequisites checked${NC}"
}

# Créer le projet Azure DevOps
create_project() {
    echo -e "${YELLOW}📋 Creating Azure DevOps project...${NC}"
    
    # Vérifier si le projet existe déjà
    if az devops project show --project "$PROJECT_NAME" --organization "$ORGANIZATION_URL" &> /dev/null; then
        echo -e "${YELLOW}⚠️ Project '$PROJECT_NAME' already exists${NC}"
    else
        az devops project create \
            --name "$PROJECT_NAME" \
            --description "Automated deployment for TrainData Azure Functions with containers" \
            --organization "$ORGANIZATION_URL" \
            --source-control git \
            --visibility private
        echo -e "${GREEN}✅ Project created: $PROJECT_NAME${NC}"
    fi
}

# Configurer les Variable Groups
create_variable_groups() {
    echo -e "${YELLOW}📦 Creating Variable Groups...${NC}"
    
    # Obtenir des informations Azure
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    TENANT_ID=$(az account show --query tenantId -o tsv)
    
    # Variable Group: function-config (non-secrets)
    echo -e "${BLUE}Creating function-config variable group...${NC}"
    
    # Supprimer s'il existe déjà
    az pipelines variable-group delete \
        --group-id $(az pipelines variable-group list --query "[?name=='function-config'].id | [0]" -o tsv) \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME" --yes &> /dev/null || true
    
    # Créer le nouveau
    VG_CONFIG_ID=$(az pipelines variable-group create \
        --name "function-config" \
        --description "Configuration applicative pour traindata functions" \
        --variables \
            AZURE_FUNCTION_APP_NAME="traindata-function-app" \
            AZURE_RESOURCE_GROUP="$AZURE_RESOURCE_GROUP" \
            AZURE_LOCATION="West Europe" \
            CONTAINER_REGISTRY_URL="traindataacr1754421294.azurecr.io" \
            DOCKER_IMAGE_NAME="traindata-function" \
            ENVIRONMENT="production" \
            PYTHON_VERSION="3.12" \
            FUNCTIONS_EXTENSION_VERSION="~4" \
            FUNCTIONS_WORKER_RUNTIME="python" \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME" \
        --query id -o tsv)
    
    echo -e "${GREEN}✅ function-config Variable Group created (ID: $VG_CONFIG_ID)${NC}"
    
    # Variable Group: azure-secrets (avec secrets)
    echo -e "${BLUE}Creating azure-secrets variable group...${NC}"
    
    # Supprimer s'il existe déjà
    az pipelines variable-group delete \
        --group-id $(az pipelines variable-group list --query "[?name=='azure-secrets'].id | [0]" -o tsv) \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME" --yes &> /dev/null || true
    
    # Créer le Service Principal si nécessaire
    echo -e "${BLUE}Creating/Getting Service Principal...${NC}"
    SP_JSON=$(az ad sp create-for-rbac \
        --name "traindata-devops-sp-$(date +%s)" \
        --role "Contributor" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP" \
        --output json)
    
    CLIENT_ID=$(echo $SP_JSON | jq -r .appId)
    CLIENT_SECRET=$(echo $SP_JSON | jq -r .password)
    
    # Obtenir les credentials ACR
    echo -e "${BLUE}Getting ACR credentials...${NC}"
    az acr update --name traindataacr1754421294 --admin-enabled true > /dev/null
    ACR_CREDS=$(az acr credential show --name traindataacr1754421294)
    ACR_USERNAME=$(echo $ACR_CREDS | jq -r .username)
    ACR_PASSWORD=$(echo $ACR_CREDS | jq -r .passwords[0].value)
    
    # Créer le Variable Group avec secrets
    VG_SECRETS_ID=$(az pipelines variable-group create \
        --name "azure-secrets" \
        --description "Variables sensibles pour Azure et base de données" \
        --variables \
            AZURE_CLIENT_ID="$CLIENT_ID" \
            AZURE_TENANT_ID="$TENANT_ID" \
            ACR_USERNAME="$ACR_USERNAME" \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME" \
        --query id -o tsv)
    
    # Ajouter les secrets (nécessite des appels séparés)
    az pipelines variable-group variable create \
        --group-id "$VG_SECRETS_ID" \
        --name "AZURE_CLIENT_SECRET" \
        --value "$CLIENT_SECRET" \
        --secret \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME"
    
    az pipelines variable-group variable create \
        --group-id "$VG_SECRETS_ID" \
        --name "ACR_PASSWORD" \
        --value "$ACR_PASSWORD" \
        --secret \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME"
    
    echo -e "${GREEN}✅ azure-secrets Variable Group created (ID: $VG_SECRETS_ID)${NC}"
    
    # Afficher les informations importantes
    echo -e "${YELLOW}📋 Service Principal Information:${NC}"
    echo "Client ID: $CLIENT_ID"
    echo "Tenant ID: $TENANT_ID"
    echo -e "${RED}⚠️ Client Secret créé et stocké dans azure-secrets Variable Group${NC}"
}

# Créer les Service Connections
create_service_connections() {
    echo -e "${YELLOW}🔗 Creating Service Connections...${NC}"
    
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    # Azure Resource Manager Service Connection
    echo -e "${BLUE}Creating Azure RM Service Connection...${NC}"
    
    # Note: La création de Service Connections via CLI est limitée
    # Elle nécessite souvent une configuration manuelle via le portal
    
    echo -e "${YELLOW}⚠️ Service Connections doivent être créées manuellement via le portal Azure DevOps:${NC}"
    echo "1. Aller dans Project Settings > Service connections"
    echo "2. Créer 'azure-service-connection' (Azure Resource Manager)"
    echo "3. Créer 'azure-container-registry-connection' (Docker Registry)"
    echo "4. Utiliser le Service Principal créé : $CLIENT_ID"
}

# Créer le pipeline
create_pipeline() {
    echo -e "${YELLOW}⚙️ Creating Pipeline...${NC}"
    
    # Créer le pipeline à partir du YAML
    PIPELINE_ID=$(az pipelines create \
        --name "TrainData-Function-Container-Deploy" \
        --description "Déploiement containerisé Azure Functions TrainData" \
        --repository "$REPO_URL" \
        --repository-type github \
        --branch main \
        --yaml-path "/Azure-DevOps-CICD/azure-pipelines.yml" \
        --organization "$ORGANIZATION_URL" \
        --project "$PROJECT_NAME" \
        --query id -o tsv) || true
    
    if [ -n "$PIPELINE_ID" ]; then
        echo -e "${GREEN}✅ Pipeline created (ID: $PIPELINE_ID)${NC}"
    else
        echo -e "${YELLOW}⚠️ Pipeline creation might need manual setup${NC}"
        echo "Configure manually in Azure DevOps > Pipelines > New pipeline"
    fi
}

# Fonction principale
main() {
    echo -e "${BLUE}Starting Azure DevOps setup...${NC}"
    
    check_prerequisites
    create_project
    create_variable_groups
    create_service_connections
    create_pipeline
    
    echo -e "${GREEN}🎉 Azure DevOps setup completed!${NC}"
    echo ""
    echo -e "${YELLOW}📋 Next Steps:${NC}"
    echo "1. Configure Service Connections manually in Azure DevOps portal"
    echo "2. Review Variable Groups for any missing secrets"
    echo "3. Run the pipeline to test deployment"
    echo "4. Configure any missing application settings"
    echo ""
    echo -e "${BLUE}Azure DevOps Portal: ${ORGANIZATION_URL}/${PROJECT_NAME}${NC}"
}

# Gestion des arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo "Environment variables:"
        echo "  AZURE_DEVOPS_ORG: Azure DevOps organization URL"
        echo "  PROJECT_NAME: Name of the Azure DevOps project"
        echo "  REPO_URL: GitHub repository URL"
        echo "  AZURE_SUBSCRIPTION_ID: Azure subscription ID"
        echo "  AZURE_RESOURCE_GROUP: Azure resource group name"
        exit 0
        ;;
    *)
        main
        ;;
esac
