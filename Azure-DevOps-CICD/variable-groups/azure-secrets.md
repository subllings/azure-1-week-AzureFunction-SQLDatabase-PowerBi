# Variable Groups Configuration

## 🔐 azure-secrets (Variable Group)
**Description**: Variables sensibles pour Azure et base de données
**Security**: Toutes les variables marquées comme "Secret" ⚠️

```yaml
Variables:
  AZURE_CLIENT_ID:
    value: "votre-service-principal-client-id"
    description: "Client ID du Service Principal Azure"
    secret: false
    
  AZURE_CLIENT_SECRET:
    value: "votre-service-principal-secret"
    description: "Secret du Service Principal Azure"
    secret: true ⚠️
    
  AZURE_TENANT_ID:
    value: "votre-tenant-id"
    description: "Tenant ID Azure"
    secret: false
    
  ACR_USERNAME:
    value: "traindataacr1754421294"
    description: "Username pour Azure Container Registry"
    secret: false
    
  ACR_PASSWORD:
    value: "votre-acr-password"
    description: "Password pour Azure Container Registry"
    secret: true ⚠️
    
  SQL_CONNECTION_STRING:
    value: "Server=tcp:traindata-sql-server.database.windows.net,1433;Database=traindata-db;User ID=sqladmin;Password=VotreMotDePasse;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
    description: "Chaîne de connexion SQL Server"
    secret: true ⚠️
    
  APPLICATIONINSIGHTS_CONNECTION_STRING:
    value: "InstrumentationKey=votre-key;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"
    description: "Chaîne de connexion Application Insights"
    secret: true ⚠️
    
  AZURE_WEB_JOBS_STORAGE:
    value: "DefaultEndpointsProtocol=https;AccountName=traindatastorage;AccountKey=votre-key;EndpointSuffix=core.windows.net"
    description: "Storage Account pour Azure Functions"
    secret: true ⚠️
```

## 📋 Commandes Azure CLI pour récupérer les valeurs

### Service Principal (si pas encore créé)
```bash
# Créer un Service Principal
az ad sp create-for-rbac --name "traindata-devops-sp" \
  --role "Contributor" \
  --scopes "/subscriptions/VOTRE-SUBSCRIPTION-ID/resourceGroups/traindata-rg"

# Résultat:
{
  "appId": "AZURE_CLIENT_ID",
  "displayName": "traindata-devops-sp",
  "password": "AZURE_CLIENT_SECRET",
  "tenant": "AZURE_TENANT_ID"
}
```

### Azure Container Registry
```bash
# Activer admin user sur ACR
az acr update --name traindataacr1754421294 --admin-enabled true

# Obtenir les credentials
az acr credential show --name traindataacr1754421294

# Résultat:
{
  "passwords": [
    {
      "name": "password",
      "value": "ACR_PASSWORD"
    }
  ],
  "username": "traindataacr1754421294"
}
```

### SQL Database Connection String
```bash
# Obtenir la chaîne de connexion
az sql db show-connection-string \
  --client ado.net \
  --server traindata-sql-server \
  --name traindata-db

# Remplacer <username> et <password> par vos vraies valeurs
```

### Application Insights
```bash
# Obtenir la connection string
az monitor app-insights component show \
  --app traindata-insights \
  --resource-group traindata-rg \
  --query connectionString -o tsv
```

### Storage Account
```bash
# Obtenir la connection string
az storage account show-connection-string \
  --name traindatastorage \
  --resource-group traindata-rg \
  --query connectionString -o tsv
```

## 🔧 Configuration dans Azure DevOps

### Méthode 1: Via Portal
1. **Azure DevOps** → **Pipelines** → **Library**
2. **+ Variable group**
3. **Variable group name**: `azure-secrets`
4. **Description**: `Variables sensibles pour Azure et base de données`
5. Ajouter chaque variable avec le toggle "Keep this value secret" pour les secrets ⚠️

### Méthode 2: Via REST API
```bash
# Exemple pour créer le Variable Group via API
curl -X POST \
  "https://dev.azure.com/{organization}/{project}/_apis/distributedtask/variablegroups?api-version=7.1-preview.2" \
  -H "Authorization: Bearer $AZURE_DEVOPS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "azure-secrets",
    "description": "Variables sensibles pour Azure",
    "type": "Vsts",
    "variables": {
      "AZURE_CLIENT_ID": {
        "value": "votre-client-id",
        "isSecret": false
      },
      "AZURE_CLIENT_SECRET": {
        "value": "votre-secret",
        "isSecret": true
      }
    }
  }'
```

## 🔒 Sécurité Best Practices

1. **Secrets**: Toujours marquer comme "Secret" dans Azure DevOps
2. **Permissions**: Limiter l'accès aux Variable Groups
3. **Audit**: Activer les logs d'audit pour les modifications
4. **Rotation**: Planifier la rotation régulière des secrets
5. **Least Privilege**: Donner les permissions minimales nécessaires

## 🔗 Key Vault Integration (Optionnel)
Pour une sécurité renforcée, vous pouvez lier les Variable Groups à Azure Key Vault :

```bash
# Créer un Key Vault
az keyvault create \
  --name "traindata-keyvault" \
  --resource-group "traindata-rg" \
  --location "West Europe"

# Ajouter les secrets
az keyvault secret set --vault-name "traindata-keyvault" --name "sql-connection" --value "votre-connection-string"
```

Puis dans Azure DevOps, créer un Variable Group lié au Key Vault.
