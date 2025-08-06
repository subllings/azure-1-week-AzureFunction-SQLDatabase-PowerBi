# GitHub Secrets Configuration pour CI/CD Azure

## 🔐 Secrets requis dans GitHub

Allez dans votre repo GitHub : `Settings` > `Secrets and variables` > `Actions`

### Secrets Azure requis :

```bash
# Azure Service Principal
AZURE_CLIENT_ID=<votre-client-id>
AZURE_CLIENT_SECRET=<votre-client-secret>
AZURE_SUBSCRIPTION_ID=b63db937-8e75-4757-aa10-4571a475c185
AZURE_TENANT_ID=<votre-tenant-id>

# Configuration spécifique
AZURE_RESOURCE_GROUP=rg-irail-dev-i6lr9a
AZURE_FUNCTION_APP_NAME=irail-functions-simple
SQL_CONNECTION_STRING=<votre-connection-string-sql>

# Terraform Backend (optionnel)
TF_BACKEND_STORAGE_ACCOUNT=<storage-account-name>
TF_BACKEND_CONTAINER_NAME=tfstate
TF_BACKEND_KEY=terraform.tfstate
```

## 🛠️ Commandes pour créer le Service Principal

```bash
# 1. Se connecter à Azure
az login

# 2. Créer le Service Principal
az ad sp create-for-rbac \
  --name "github-actions-irail" \
  --role contributor \
  --scopes /subscriptions/b63db937-8e75-4757-aa10-4571a475c185 \
  --sdk-auth

# 3. Copier la sortie JSON dans le secret AZURE_CREDENTIALS
```

La sortie ressemblera à :
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "b63db937-8e75-4757-aa10-4571a475c185",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

## 📋 Permissions supplémentaires requises

```bash
# Donner les permissions Data Factory au Service Principal
az role assignment create \
  --assignee <CLIENT_ID> \
  --role "Data Factory Contributor" \
  --scope /subscriptions/b63db937-8e75-4757-aa10-4571a475c185/resourceGroups/rg-irail-dev-i6lr9a

# Permissions SQL Database
az role assignment create \
  --assignee <CLIENT_ID> \
  --role "SQL DB Contributor" \
  --scope /subscriptions/b63db937-8e75-4757-aa10-4571a475c185/resourceGroups/rg-irail-dev-i6lr9a
```
