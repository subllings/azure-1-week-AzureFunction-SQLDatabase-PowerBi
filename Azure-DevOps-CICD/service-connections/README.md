# Service Connections Guide

## 🔗 Azure Resource Manager Service Connection

### Configuration via Portal
1. **Azure DevOps** → **Project Settings** → **Service connections**
2. **New service connection** → **Azure Resource Manager**
3. **Authentication method**: Service principal (automatic)
4. **Scope level**: Subscription
5. **Subscription**: Sélectionner votre subscription Azure
6. **Resource group**: `traindata-rg`
7. **Service connection name**: `azure-service-connection`
8. **Grant access permission to all pipelines**: ✅ Coché

### Configuration Manuelle (Service Principal)
Si vous préférez créer le Service Principal manuellement :

```bash
# 1. Créer le Service Principal
az ad sp create-for-rbac --name "traindata-devops-sp" \
  --role "Contributor" \
  --scopes "/subscriptions/VOTRE-SUBSCRIPTION-ID"

# Résultat à noter :
{
  "appId": "CLIENT_ID",
  "displayName": "traindata-devops-sp",
  "password": "CLIENT_SECRET",
  "tenant": "TENANT_ID"
}

# 2. Ajouter des rôles spécifiques si nécessaire
az role assignment create \
  --assignee CLIENT_ID \
  --role "Azure Kubernetes Service Contributor" \
  --scope "/subscriptions/VOTRE-SUBSCRIPTION-ID/resourceGroups/traindata-rg"
```

Puis dans Azure DevOps :
1. **Service principal (manual)**
2. Remplir avec les valeurs obtenues
3. **Verify connection** pour tester

## 🐳 Azure Container Registry Service Connection

### Configuration via Portal
1. **Azure DevOps** → **Project Settings** → **Service connections**
2. **New service connection** → **Docker Registry**
3. **Registry type**: Azure Container Registry
4. **Authentication Type**: Service Principal
5. **Azure subscription**: Sélectionner votre subscription
6. **Azure container registry**: `traindataacr1754421294`
7. **Service connection name**: `azure-container-registry-connection`

### Configuration Alternative (Username/Password)
Si vous préférez utiliser les credentials Admin :

```bash
# Activer l'admin user sur ACR
az acr update --name traindataacr1754421294 --admin-enabled true

# Obtenir les credentials
az acr credential show --name traindataacr1754421294
```

Puis :
1. **Registry type**: Others
2. **Docker Registry**: `https://traindataacr1754421294.azurecr.io`
3. **Docker ID**: `traindataacr1754421294`
4. **Password**: Le password obtenu avec la commande ci-dessus

## 🔒 Permissions Requises

### Service Principal pour Azure Resource Manager
Le Service Principal doit avoir ces rôles sur votre subscription/resource group :

```bash
# Rôles de base
az role assignment create --assignee CLIENT_ID --role "Contributor" --scope "/subscriptions/SUBSCRIPTION_ID"

# Rôles spécifiques pour Azure Functions
az role assignment create --assignee CLIENT_ID --role "Website Contributor" --scope "/subscriptions/SUBSCRIPTION_ID"

# Pour Azure Container Registry
az role assignment create --assignee CLIENT_ID --role "AcrPush" --scope "/subscriptions/SUBSCRIPTION_ID/resourceGroups/traindata-rg/providers/Microsoft.ContainerRegistry/registries/traindataacr1754421294"
```

### Vérification des Permissions
```bash
# Lister les rôles assignés
az role assignment list --assignee CLIENT_ID --output table

# Tester l'accès aux ressources
az functionapp list --resource-group traindata-rg
az acr repository list --name traindataacr1754421294
```

## 🧪 Test des Service Connections

### Script de Test Complet
```bash
#!/bin/bash
echo "🔍 Testing Service Connections..."

# Test Azure Resource Manager
echo "Testing Azure RM connection..."
az account show --query "name" -o tsv

# Test Function App access
echo "Testing Function App access..."
az functionapp show --name traindata-function-app --resource-group traindata-rg --query "name" -o tsv

# Test Container Registry
echo "Testing ACR access..."
az acr login --name traindataacr1754421294
docker pull traindataacr1754421294.azurecr.io/traindata-function:latest || echo "No image found (normal for first run)"

echo "✅ All tests completed!"
```

## 🚨 Troubleshooting

### Erreur : "The subscription is not registered"
```bash
# Enregistrer les providers nécessaires
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Insights
```

### Erreur : "Insufficient privileges"
```bash
# Vérifier les rôles
az role assignment list --assignee CLIENT_ID --all

# Ajouter le rôle manquant
az role assignment create --assignee CLIENT_ID --role "User Access Administrator" --scope "/subscriptions/SUBSCRIPTION_ID"
```

### Erreur : "Container Registry not found"
```bash
# Vérifier que l'ACR existe
az acr show --name traindataacr1754421294 --resource-group traindata-rg

# Vérifier les permissions
az acr check-health --name traindataacr1754421294
```

## 📋 Service Connection Summary

| Connection Name | Type | Purpose | Authentication |
|---|---|---|---|
| `azure-service-connection` | Azure RM | Déploiement ressources Azure | Service Principal |
| `azure-container-registry-connection` | Docker Registry | Push/Pull images Docker | Service Principal ou Admin |

## 🔄 Pipeline Usage

Dans votre pipeline, référencez les service connections :

```yaml
- task: AzureFunctionAppContainer@1
  inputs:
    azureSubscription: 'azure-service-connection'  # ← Service Connection
    appName: '$(AZURE_FUNCTION_APP_NAME)'

- task: Docker@2
  inputs:
    containerRegistry: 'azure-container-registry-connection'  # ← Service Connection
    command: 'push'
```

## 🔐 Sécurité Best Practices

1. **Principe du moindre privilège** : Ne donnez que les permissions nécessaires
2. **Rotation des secrets** : Planifiez la rotation des Service Principal secrets
3. **Audit** : Activez les logs d'audit Azure AD
4. **Environnements séparés** : Utilisez des Service Connections différents pour dev/prod
5. **Expiration** : Configurez une expiration sur les secrets de Service Principal

```bash
# Exemple de rotation de secret
az ad sp credential reset --id CLIENT_ID --display-name "New credential $(date +%Y%m%d)"
```
