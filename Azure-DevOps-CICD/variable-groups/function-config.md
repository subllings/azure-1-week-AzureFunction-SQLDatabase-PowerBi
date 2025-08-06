# Variable Groups Configuration

## ⚙️ function-config (Variable Group)
**Description**: Configuration applicative et environnement (non-sensible)
**Security**: Toutes les variables publiques

```yaml
Variables:
  AZURE_FUNCTION_APP_NAME:
    value: "traindata-function-app"
    description: "Nom de l'Azure Function App"
    secret: false
    
  AZURE_RESOURCE_GROUP:
    value: "traindata-rg"
    description: "Resource Group principal"
    secret: false
    
  AZURE_LOCATION:
    value: "West Europe"
    description: "Région Azure pour le déploiement"
    secret: false
    
  CONTAINER_REGISTRY_URL:
    value: "traindataacr1754421294.azurecr.io"
    description: "URL du Container Registry"
    secret: false
    
  DOCKER_IMAGE_NAME:
    value: "traindata-function"
    description: "Nom de l'image Docker"
    secret: false
    
  ENVIRONMENT:
    value: "production"
    description: "Environnement de déploiement"
    secret: false
    
  PYTHON_VERSION:
    value: "3.12"
    description: "Version Python utilisée"
    secret: false
    
  FUNCTIONS_EXTENSION_VERSION:
    value: "~4"
    description: "Version du runtime Azure Functions"
    secret: false
    
  FUNCTIONS_WORKER_RUNTIME:
    value: "python"
    description: "Runtime worker pour Azure Functions"
    secret: false
    
  HEALTH_CHECK_TIMEOUT:
    value: "30"
    description: "Timeout pour les health checks (secondes)"
    secret: false
    
  API_RATE_LIMIT:
    value: "1000"
    description: "Limite de requêtes par minute"
    secret: false
```

## 📋 Configuration dans Azure DevOps

### Méthode Portal
1. **Azure DevOps** → **Pipelines** → **Library**
2. **+ Variable group**
3. **Variable group name**: `function-config`
4. **Description**: `Configuration applicative pour traindata functions`
5. Ajouter chaque variable (toutes publiques, pas de secrets)

### Méthode REST API
```bash
curl -X POST \
  "https://dev.azure.com/{organization}/{project}/_apis/distributedtask/variablegroups?api-version=7.1-preview.2" \
  -H "Authorization: Bearer $AZURE_DEVOPS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "function-config",
    "description": "Configuration applicative traindata",
    "type": "Vsts",
    "variables": {
      "AZURE_FUNCTION_APP_NAME": {
        "value": "traindata-function-app",
        "isSecret": false
      },
      "AZURE_RESOURCE_GROUP": {
        "value": "traindata-rg",
        "isSecret": false
      },
      "AZURE_LOCATION": {
        "value": "West Europe",
        "isSecret": false
      },
      "CONTAINER_REGISTRY_URL": {
        "value": "traindataacr1754421294.azurecr.io",
        "isSecret": false
      }
    }
  }'
```

## 🌍 Gestion Multi-Environnement

Pour gérer plusieurs environnements (dev, staging, prod), créez des Variable Groups séparés :

### function-config-dev
```yaml
AZURE_FUNCTION_APP_NAME: "traindata-function-app-dev"
ENVIRONMENT: "development"
API_RATE_LIMIT: "100"
```

### function-config-staging
```yaml
AZURE_FUNCTION_APP_NAME: "traindata-function-app-staging"
ENVIRONMENT: "staging"
API_RATE_LIMIT: "500"
```

### function-config-prod
```yaml
AZURE_FUNCTION_APP_NAME: "traindata-function-app"
ENVIRONMENT: "production"
API_RATE_LIMIT: "1000"
```

## 🔄 Pipeline Usage
Dans votre `azure-pipelines.yml`, référencez le Variable Group :

```yaml
variables:
- group: function-config
- group: azure-secrets

stages:
- stage: Deploy
  jobs:
  - job: DeployFunction
    steps:
    - script: |
        echo "Deploying to: $(AZURE_FUNCTION_APP_NAME)"
        echo "Resource Group: $(AZURE_RESOURCE_GROUP)"
        echo "Environment: $(ENVIRONMENT)"
```

## 📊 Variables de Runtime Calculées

Certaines variables peuvent être calculées dynamiquement :

```yaml
variables:
- group: function-config
- name: BUILD_TAG
  value: '$(Build.BuildId)-$(Date:yyyyMMdd)'
- name: FULL_IMAGE_NAME
  value: '$(CONTAINER_REGISTRY_URL)/$(DOCKER_IMAGE_NAME):$(BUILD_TAG)'
```

## 🔍 Validation et Testing

Script de validation pour vérifier les Variable Groups :

```bash
# Test de connectivité Azure
az account show --query "name" -o tsv

# Test de l'ACR
az acr login --name $(echo $CONTAINER_REGISTRY_URL | cut -d'.' -f1)

# Test de la Function App
az functionapp show --name $AZURE_FUNCTION_APP_NAME --resource-group $AZURE_RESOURCE_GROUP
```
