#!/usr/bin/env bash
# Setup Azure DevOps CI/CD to deploy Azure Functions on push
# Usage:
#   ./scripts/setup-azdo-pipeline.sh <ADO_ORG_URL> <ADO_PROJECT_NAME> <REPO_URL> [PIPELINE_NAME] [SERVICE_CONNECTION_NAME] [YAML_PATH]
# Example:
#   ./scripts/setup-azdo-pipeline.sh https://dev.azure.com/yourorg irail-functions-cicd \
#     https://github.com/subllings/azure-1-week-AzureFunction-SQLDatabase-PowerBi \
#     iRail-Functions-Deploy azure-service-connection Azure-DevOps-CICD/azure-pipelines.yml

set -euo pipefail

if [[ ${1-} == "" || ${2-} == "" || ${3-} == "" ]]; then
  echo "Usage: $0 <ADO_ORG_URL> <ADO_PROJECT_NAME> <REPO_URL> [PIPELINE_NAME] [SERVICE_CONNECTION_NAME] [YAML_PATH]"
  exit 1
fi

ADO_ORG_URL="$1"
ADO_PROJECT="$2"
REPO_URL="$3"
PIPELINE_NAME="${4:-iRail-Functions-Deploy}"
SERVICE_CONN_NAME="${5:-azure-service-connection}"
YAML_PATH="${6:-Azure-DevOps-CICD/azure-pipelines.yml}"

# Optional: override subscription
SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-b63db937-8e75-4757-aa10-4571a475c185}"

echo "== Checking Azure CLI and DevOps extension =="
command -v az >/dev/null || { echo "Azure CLI (az) not found"; exit 1; }
az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops

# Configure defaults
az devops configure -d organization="$ADO_ORG_URL" project="$ADO_PROJECT"

# Log in status check
echo "== Azure account context =="
az account show --only-show-errors -o table || { echo "Run: az login"; exit 1; }
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv | tr -d '\r')
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo "Using Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

echo "== Create/Find ARM service connection =="
# Try to find existing service connection by name
set +e
EXISTING_ID=$(az devops service-endpoint list --query "[?name=='$SERVICE_CONN_NAME'].id | [0]" -o tsv 2>/dev/null)
set -e
if [[ -n "${EXISTING_ID:-}" ]]; then
  echo "Service connection already exists: $SERVICE_CONN_NAME ($EXISTING_ID)"
  SERVICE_CONN_ID="$EXISTING_ID"
else
  SERVICE_CONN_ID=$(az devops service-endpoint azurerm create \
    --name "$SERVICE_CONN_NAME" \
    --azure-rm-subscription-id "$SUBSCRIPTION_ID" \
    --azure-rm-subscription-name "$SUBSCRIPTION_NAME" \
    --azure-rm-tenant-id "$TENANT_ID" \
    --query id -o tsv)
  echo "Created service connection: $SERVICE_CONN_NAME ($SERVICE_CONN_ID)"
fi

# Authorize service connection for all pipelines (avoids manual approval)
az devops service-endpoint update --id "$SERVICE_CONN_ID" --enable-for-all true >/dev/null || true

echo "== Create variable groups (if missing) =="
# irail-config-current
set +e
VG_CFG_ID=$(az pipelines variable-group list --query "[?name=='irail-config-current'].id | [0]" -o tsv 2>/dev/null)
set -e
if [[ -z "${VG_CFG_ID:-}" ]]; then
  VG_CFG_ID=$(az pipelines variable-group create \
    --name "irail-config-current" \
    --variables FUNCTION_APP_NAME=func-irail-dev-i6lr9a RESOURCE_GROUP_NAME=rg-irail-dev-i6lr9a AZURE_LOCATION=francecentral APP_SERVICE_PLAN_SKU=Y1 \
    --query id -o tsv)
  echo "Created variable group: irail-config-current ($VG_CFG_ID)"
else
  echo "Variable group already exists: irail-config-current ($VG_CFG_ID)"
fi

# irail-secrets (placeholders, add real values later)
set +e
VG_SEC_ID=$(az pipelines variable-group list --query "[?name=='irail-secrets'].id | [0]" -o tsv 2>/dev/null)
set -e
if [[ -z "${VG_SEC_ID:-}" ]]; then
  VG_SEC_ID=$(az pipelines variable-group create --name "irail-secrets" --query id -o tsv)
  # Add secret variables as placeholders
  az pipelines variable-group variable create --group-id "$VG_SEC_ID" --name APPLICATIONINSIGHTS_CONNECTION_STRING --secret true --value "" >/dev/null || true
  az pipelines variable-group variable create --group-id "$VG_SEC_ID" --name SQL_CONNECTION_STRING --secret true --value "" >/dev/null || true
  az pipelines variable-group variable create --group-id "$VG_SEC_ID" --name AZURE_WEB_JOBS_STORAGE --secret true --value "" >/dev/null || true
  echo "Created variable group: irail-secrets ($VG_SEC_ID)"
else
  echo "Variable group already exists: irail-secrets ($VG_SEC_ID)"
fi

echo "== Create pipeline (YAML) =="
# Detect repository type (GitHub or Azure Repos) by URL
if [[ "$REPO_URL" == https://github.com/* ]]; then
  REPO_TYPE="github"
else
  REPO_TYPE="tfsgit"
fi

# Create pipeline if not exists
set +e
EXISTING_PIPELINE_ID=$(az pipelines list --query "[?name=='$PIPELINE_NAME'].id | [0]" -o tsv 2>/dev/null)
set -e
if [[ -z "${EXISTING_PIPELINE_ID:-}" ]]; then
  az pipelines create \
    --name "$PIPELINE_NAME" \
    --repository "$REPO_URL" \
    --repository-type "$REPO_TYPE" \
    --branch "main" \
    --yaml-path "$YAML_PATH" \
    --skip-run true
  echo "Created pipeline: $PIPELINE_NAME (YAML: $YAML_PATH)"
else
  echo "Pipeline already exists: $PIPELINE_NAME ($EXISTING_PIPELINE_ID)"
fi

echo "== Done =="
echo "Next steps:"
echo "1) In Azure DevOps, edit the pipeline and ensure the service connection '$SERVICE_CONN_NAME' is selected for Azure tasks."
echo "2) Fill variable group 'irail-secrets' with real secret values (from terraform outputs)."
echo "3) Commit to 'main' or 'develop' to trigger the pipeline (see YAML triggers)."
