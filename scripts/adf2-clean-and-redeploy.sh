#!/bin/bash
set -euo pipefail

# Clean ADF2 and redeploy via Terraform
# Usage: bash ./scripts/adf2-clean-and-redeploy.sh

SUBSCRIPTION_ID="b63db937-8e75-4757-aa10-4571a475c185"
RESOURCE_GROUP="rg-irail-dev-i6lr9a"

info()  { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success(){ echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()   { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

# Azure login check
if ! command -v az >/dev/null 2>&1; then
  err "Azure CLI (az) not found. Please install and run az login."
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  err "Not logged in. Run: az login"
  exit 1
fi

info "Setting subscription: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"
az account show --query "{name:name,id:id,isDefault:isDefault}" -o table || true

# Detect ADF2 factories by naming pattern
info "Detecting ADF2 in $RESOURCE_GROUP"
ADF2_LIST=$(az datafactory list -g "$RESOURCE_GROUP" --query "[?starts_with(name, 'df2-') || starts_with(name, 'df-irail-data-v2-')].name" -o tsv || true)

if [ -z "${ADF2_LIST:-}" ]; then
  warn "No ADF2 factory found in $RESOURCE_GROUP (patterns: df2-*, df-irail-data-v2-*)"
else
  echo "Found ADF2 factories:" && echo "$ADF2_LIST" | sed 's/^/ - /'
  for ADF2 in $ADF2_LIST; do
    info "Cleaning ADF2: $ADF2"

    info "Stopping triggers"
    for T in $(az datafactory trigger list -g "$RESOURCE_GROUP" --factory-name "$ADF2" --query "[].name" -o tsv || true); do
      az datafactory trigger stop -g "$RESOURCE_GROUP" --factory-name "$ADF2" --name "$T" || true
    done

    info "Deleting triggers"
    for T in $(az datafactory trigger list -g "$RESOURCE_GROUP" --factory-name "$ADF2" --query "[].name" -o tsv || true); do
      az datafactory trigger delete -g "$RESOURCE_GROUP" --factory-name "$ADF2" --name "$T" -y || true
    done

    info "Deleting pipelines"
    for P in $(az datafactory pipeline list -g "$RESOURCE_GROUP" --factory-name "$ADF2" --query "[].name" -o tsv || true); do
      az datafactory pipeline delete -g "$RESOURCE_GROUP" --factory-name "$ADF2" --name "$P" -y || true
    done

    info "Deleting datasets"
    for D in $(az datafactory dataset list -g "$RESOURCE_GROUP" --factory-name "$ADF2" --query "[].name" -o tsv || true); do
      az datafactory dataset delete -g "$RESOURCE_GROUP" --factory-name "$ADF2" --name "$D" -y || true
    done

    info "Deleting linked services"
    for L in $(az datafactory linked-service list -g "$RESOURCE_GROUP" --factory-name "$ADF2" --query "[].name" -o tsv || true); do
      az datafactory linked-service delete -g "$RESOURCE_GROUP" --factory-name "$ADF2" --name "$L" -y || true
    done

    info "Deleting factory $ADF2"
    az datafactory delete -g "$RESOURCE_GROUP" -n "$ADF2" -y || true

    info "Verify deletion"
    if az datafactory show -g "$RESOURCE_GROUP" -n "$ADF2" >/dev/null 2>&1; then
      warn "Factory $ADF2 still exists or requires portal cleanup"
    else
      success "Factory $ADF2 removed"
    fi
  done
fi

# Redeploy via Terraform
info "Redeploying infra (including ADF2) with Terraform"
if [ ! -f "infrastructure/main.tf" ]; then
  err "Run this script from repo root"
  exit 1
fi

pushd infrastructure >/dev/null
if ! command -v terraform >/dev/null 2>&1; then
  err "Terraform not found. Install Terraform first."
  exit 1
fi

terraform init
terraform plan -var-file="staging.tfvars" -out="staging.tfplan"
info "Applying Terraform plan"
terraform apply -auto-approve "staging.tfplan"

# Try to find new ADF2 name
NEW_ADF2=$(az datafactory list -g "$RESOURCE_GROUP" --query "[?starts_with(name, 'df2-') || starts_with(name, 'df-irail-data-v2-')].name | [0]" -o tsv || true)
popd >/dev/null

if [ -n "${NEW_ADF2:-}" ]; then
  success "ADF2 redeployed: $NEW_ADF2"
  info "Starting v2 triggers and running collection pipeline"
  az datafactory trigger start -g "$RESOURCE_GROUP" --factory-name "$NEW_ADF2" --name trigger_irail_collection_every_5min_v2 || true
  az datafactory trigger start -g "$RESOURCE_GROUP" --factory-name "$NEW_ADF2" --name trigger_irail_function_warmup_3min_v2 || true
  az datafactory pipeline create-run -g "$RESOURCE_GROUP" --factory-name "$NEW_ADF2" --name pipeline_irail_train_data_collection_v2 --parameters "{}" || true
else
  warn "Could not locate ADF2 after Terraform apply. Check Terraform state and outputs."
fi

success "ADF2 clean + Terraform redeploy completed"
