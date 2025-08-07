#!/bin/bash

# Deploy Azure Functions to FC1 Plan
# Optimized for Flex Consumption deployment
# =========================================

set -e

echo "Deploy Functions to FC1 Plan"
echo "============================="
echo ""

# Check if we're in the right directory
if [ ! -f "azure_function/function_app.py" ]; then
    echo "❌ This script must be executed from the project root"
    exit 1
fi

# Get Function App details from terraform
cd infrastructure

RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
FUNCTION_APP_NAME=$(terraform output -raw function_app_name 2>/dev/null || echo "")

if [[ -z "$RESOURCE_GROUP" || -z "$FUNCTION_APP_NAME" ]]; then
    echo "❌ Could not get deployment details. Run terraform apply first."
    exit 1
fi

cd ..

echo "📋 Deployment Details:"
echo "======================"
echo "Function App: $FUNCTION_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Verify FC1 configuration
echo "🔍 Verifying FC1 setup..."
SKU_NAME=$(az appservice plan show --name "$(cd infrastructure && terraform output -raw app_service_plan_name)" --resource-group "$RESOURCE_GROUP" --query "sku.name" -o tsv 2>/dev/null)

if [[ "$SKU_NAME" == "FC1" ]]; then
    echo "✅ FC1 Flex Consumption plan confirmed"
else
    echo "⚠️  Warning: Expected FC1 but found $SKU_NAME"
fi

# Check Function App status
FUNC_STATUS=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null)
if [[ "$FUNC_STATUS" != "Running" ]]; then
    echo "⚠️  Function App is not running (status: $FUNC_STATUS)"
    echo "   Starting Function App..."
    az functionapp start --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP"
    sleep 10
fi

# Prepare function code
echo ""
echo "📦 Preparing function code for FC1..."
echo "====================================="

# Create deployment package
TEMP_DIR=$(mktemp -d)
echo "Creating deployment package in $TEMP_DIR"

# Copy function code
cp -r azure_function/* "$TEMP_DIR/"

# Ensure requirements.txt is optimized for FC1
echo "Checking requirements.txt for FC1 compatibility..."
if ! grep -q "azure-functions" "$TEMP_DIR/requirements.txt"; then
    echo "azure-functions>=1.18.0" >> "$TEMP_DIR/requirements.txt"
fi

# Create .funcignore if it doesn't exist
if [ ! -f "$TEMP_DIR/.funcignore" ]; then
    cat > "$TEMP_DIR/.funcignore" << 'EOF'
.git*
.vscode
__azurite_db*__.json
__blobstorage__
__queuestorage__
local.settings.json
test
.env
EOF
fi

# Update host.json for FC1 (10-minute timeout)
cat > "$TEMP_DIR/host.json" << 'EOF'
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  },
  "functionTimeout": "00:10:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "retry": {
    "strategy": "exponentialBackoff",
    "maxRetryCount": 3,
    "minimumInterval": "00:00:02",
    "maximumInterval": "00:00:10"
  }
}
EOF

echo "✅ Function code prepared with FC1 optimizations:"
echo "   • 10-minute timeout configured"
echo "   • Retry policy enabled"
echo "   • Application Insights sampling optimized"

# Deploy functions
echo ""
echo "🚀 Deploying functions to FC1..."
echo "================================="

cd "$TEMP_DIR"

# Use Azure CLI to deploy (better for FC1 than func tools)
echo "Deploying via Azure CLI (recommended for FC1)..."

# Create zip package
zip -r ../function-app.zip . > /dev/null
cd ..

# Deploy the zip
echo "Uploading function package..."
if az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --src "function-app.zip"; then
    
    echo "✅ Functions deployed successfully to FC1!"
    
    # Wait for deployment to complete
    echo ""
    echo "⏳ Waiting for deployment to complete..."
    sleep 30
    
    # Verify deployment
    echo ""
    echo "🔍 Verifying deployment..."
    FUNC_STATUS=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv)
    
    if [[ "$FUNC_STATUS" == "Running" ]]; then
        echo "✅ Function App is running"
        
        # List functions
        echo ""
        echo "📋 Deployed functions:"
        az functionapp function list --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o table 2>/dev/null || echo "Functions list not available yet"
        
        # Get function URL
        FUNCTION_URL=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "defaultHostName" -o tsv)
        
        echo ""
        echo "🎉 FC1 Function Deployment Complete!"
        echo "===================================="
        echo "Function App URL: https://$FUNCTION_URL"
        echo "Test endpoints:"
        echo "  • https://$FUNCTION_URL/api/stations"
        echo "  • https://$FUNCTION_URL/api/departures?station=008892007"
        echo ""
        echo "🚀 FC1 Features Available:"
        echo "  • 10-minute execution time"
        echo "  • Up to 4 GB memory"
        echo "  • Flexible auto-scaling"
        echo "  • Optimized cold start"
        echo ""
        echo "💡 Monitor your functions:"
        echo "  • Azure Portal: https://portal.azure.com"
        echo "  • Application Insights for detailed telemetry"
        echo "  • Kudu console: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
        
    else
        echo "⚠️  Function App status: $FUNC_STATUS"
        echo "   Check Azure Portal for deployment details"
    fi
    
else
    echo "❌ Function deployment failed"
    echo "   Check the error messages above"
    exit 1
fi

# Cleanup
echo ""
echo "🧹 Cleaning up..."
rm -rf "$TEMP_DIR" function-app.zip
echo "✅ Cleanup completed"
