#!/bin/bash

# FC1 Deployment Verification Script
# Verifies that FC1 Flex Consumption plan is working correctly
# =============================================================

set -e

echo "FC1 Deployment Verification"
echo "==========================="
echo ""

# Check if we're in the infrastructure directory
if [ ! -f "main.tf" ]; then
    echo "Switching to infrastructure directory..."
    cd infrastructure
fi

# Get deployment outputs
echo "📊 Checking deployment outputs..."
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
FUNCTION_APP_NAME=$(terraform output -raw function_app_name 2>/dev/null || echo "")
FUNCTION_URL=$(terraform output -raw function_app_default_hostname 2>/dev/null || echo "")
APP_SERVICE_PLAN=$(terraform output -raw app_service_plan_name 2>/dev/null || echo "")

if [[ -z "$RESOURCE_GROUP" || -z "$FUNCTION_APP_NAME" ]]; then
    echo "❌ Could not get deployment outputs. Make sure terraform has been applied successfully."
    exit 1
fi

echo "✓ Resource Group: $RESOURCE_GROUP"
echo "✓ Function App: $FUNCTION_APP_NAME"
echo "✓ App Service Plan: $APP_SERVICE_PLAN"
echo ""

# Verify FC1 configuration
echo "🔍 Verifying FC1 configuration..."

# Check App Service Plan SKU
SKU_INFO=$(az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" --query "{name: sku.name, tier: sku.tier, family: sku.family}" -o json 2>/dev/null)

if [[ ! -z "$SKU_INFO" ]]; then
    SKU_NAME=$(echo "$SKU_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'])")
    SKU_TIER=$(echo "$SKU_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['tier'])")
    SKU_FAMILY=$(echo "$SKU_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['family'])")
    
    if [[ "$SKU_NAME" == "FC1" && "$SKU_TIER" == "FlexConsumption" ]]; then
        echo "✅ FC1 Flex Consumption plan confirmed!"
        echo "   SKU: $SKU_NAME | Tier: $SKU_TIER | Family: $SKU_FAMILY"
    else
        echo "⚠️  Expected FC1 but found: $SKU_NAME ($SKU_TIER)"
    fi
else
    echo "❌ Could not retrieve App Service Plan information"
fi

# Check Function App status
echo ""
echo "🔍 Checking Function App status..."
FUNC_STATUS=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null)

if [[ "$FUNC_STATUS" == "Running" ]]; then
    echo "✅ Function App is running"
else
    echo "⚠️  Function App status: $FUNC_STATUS"
fi

# Check Function App location
FUNC_LOCATION=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "location" -o tsv 2>/dev/null)
echo "✓ Location: $FUNC_LOCATION"

# Test function endpoints if available
if [[ ! -z "$FUNCTION_URL" ]]; then
    echo ""
    echo "🧪 Testing Function App endpoints..."
    
    # Test health/root endpoint
    echo "Testing root endpoint..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$FUNCTION_URL" --max-time 30 || echo "000")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ Root endpoint responding (HTTP $HTTP_CODE)"
    elif [[ "$HTTP_CODE" == "404" ]]; then
        echo "✓ Root endpoint accessible (HTTP $HTTP_CODE - expected for Function Apps)"
    else
        echo "⚠️  Root endpoint returned HTTP $HTTP_CODE"
    fi
    
    # Test specific API endpoints
    echo "Testing /api/stations endpoint..."
    STATIONS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$FUNCTION_URL/api/stations" --max-time 30 || echo "000")
    
    if [[ "$STATIONS_CODE" == "200" ]]; then
        echo "✅ Stations endpoint working (HTTP $STATIONS_CODE)"
    else
        echo "⚠️  Stations endpoint returned HTTP $STATIONS_CODE"
        echo "   This may be expected if functions haven't been deployed yet"
    fi
    
    echo ""
    echo "🔗 Available endpoints:"
    echo "   • https://$FUNCTION_URL"
    echo "   • https://$FUNCTION_URL/api/stations"
    echo "   • https://$FUNCTION_URL/api/departures?station=008892007"
fi

# Check FC1 specific capabilities
echo ""
echo "⚡ FC1 Flex Consumption Capabilities:"
echo "===================================="
echo "✓ Execution time: Up to 10 minutes (600 seconds)"
echo "✓ Memory: Up to 4 GB"
echo "✓ Auto-scaling: Event-driven with flexible scaling"
echo "✓ Cold start: Optimized for better performance than Y1"
echo "✓ Cost model: Pay for execution time and memory"
echo ""

# Show monitoring information
echo "📊 Monitoring & Logs:"
echo "===================="
echo "• Azure Portal: https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
echo "• Application Insights: Check logs and performance metrics"
echo "• Kudu console: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
echo ""

echo "🎉 FC1 Verification completed!"
echo "=============================="
echo ""
echo "If all checks passed, your FC1 Flex Consumption deployment is working correctly!"
echo "You can now deploy your Python functions and test the 10-minute execution capability."
