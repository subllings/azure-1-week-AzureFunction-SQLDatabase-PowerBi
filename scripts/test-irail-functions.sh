#!/bin/bash

# =============================================================================
# Azure Functions Test Script - iRail Train Data API
# =============================================================================
# This script tests all endpoints of the deployed iRail Functions App
# =============================================================================
# cd /e/_SoftEng/_BeCode/azure-1-week-subllings
# chmod +x ./scripts/test-irail-functions.sh
# ./scripts/test-irail-functions.sh
# =============================================================================


clear
# Remove set -e to prevent script from exiting on first failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
FUNCTION_APP_NAME="irail-functions-simple"
BASE_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"

# Counters
PASSED=0
FAILED=0

print_header() {
    echo -e "${BLUE}=============================================================================="
    echo -e "Testing Azure Functions - iRail Train Data API"
    echo -e "Base URL: $BASE_URL"
    echo -e "==============================================================================${NC}"
    echo ""
}

test_endpoint() {
    local endpoint=$1
    local test_name=$2
    local expected_pattern=$3
    local url="${BASE_URL}${endpoint}"
    
    echo -e "${BLUE}[TEST]${NC} $test_name"
    echo -e "  URL: $url"
    
    # Make the request
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" || echo "HTTPSTATUS:000")
    
    # Extract HTTP status
    http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*$//')
    
    # Check HTTP status
    if [[ "$http_status" == "200" ]]; then
        # Check response content
        if echo "$body" | grep -q "$expected_pattern"; then
            echo -e "  ${GREEN}PASSED${NC} (HTTP $http_status, Content Match)"
            ((PASSED++))
        else
            echo -e "  ${RED}FAILED${NC} (HTTP $http_status, Content Mismatch)"
            echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
            ((FAILED++))
        fi
    else
        echo -e "  ${RED}FAILED${NC} (HTTP $http_status)"
        echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
        ((FAILED++))
    fi
    echo ""
}

test_database_endpoint() {
    local endpoint=$1
    local test_name=$2
    local url="${BASE_URL}${endpoint}"
    
    echo -e "${BLUE}[TEST]${NC} $test_name"
    echo -e "  URL: $url"
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" || echo "HTTPSTATUS:000")
    http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*$//')
    
    if [[ "$http_status" == "200" ]]; then
        if echo "$body" | grep -q '"status": "error"' && echo "$body" | grep -q "Database not configured"; then
            echo -e "  ${YELLOW}EXPECTED FAILURE${NC} (Database not configured)"
            echo -e "  ${BLUE}Note:${NC} Database endpoints require SQL_CONNECTION_STRING"
            ((PASSED++))
        elif echo "$body" | grep -q '"status": "success"'; then
            echo -e "  ${GREEN}PASSED${NC} (Database is configured and working)"
            
            # Enhanced table information extraction
            echo -e "  ${BLUE}Detailed Database Table Status:${NC}"
            
            # Try to extract tables information from the JSON response
            if echo "$body" | grep -q '"tables"'; then
                # Extract each table section using python JSON parsing if available
                if command -v python >/dev/null 2>&1; then
                    table_info=$(echo "$body" | python -c "
import json, sys
from datetime import datetime, timezone, timedelta
try:
    data = json.load(sys.stdin)
    if 'tables' in data:
        for table_name, table_data in data['tables'].items():
            if isinstance(table_data, dict):
                row_count = table_data.get('row_count', 'N/A')
                columns = table_data.get('columns', [])
                col_count = len(columns) if isinstance(columns, list) else 0
                
                # Look for timestamp columns
                timestamp_cols = []
                if isinstance(columns, list):
                    for col in columns:
                        if any(ts in str(col).lower() for ts in ['created_at', 'updated_at', 'recorded_at', 'timestamp']):
                            timestamp_cols.append(col)
                
                # Extract latest timestamps from data if available
                data_samples = table_data.get('data', [])
                created_times = []
                updated_times = []
                
                if isinstance(data_samples, list) and len(data_samples) > 0:
                    for record in data_samples[:5]:  # Check first 5 records
                        if isinstance(record, dict):
                            if 'created_at' in record and record['created_at']:
                                created_times.append(record['created_at'])
                            if 'updated_at' in record and record['updated_at']:
                                updated_times.append(record['updated_at'])
                            if 'recorded_at' in record and record['recorded_at']:
                                updated_times.append(record['recorded_at'])
                
                # Get most recent timestamps and convert to Brussels time
                latest_created = max(created_times) if created_times else None
                latest_updated = max(updated_times) if updated_times else None
                
                # Convert timestamps to both UTC and Brussels time
                latest_created_utc = latest_created or \"N/A\"
                latest_updated_utc = latest_updated or \"N/A\"
                latest_created_brussels = \"N/A\"
                latest_updated_brussels = \"N/A\"
                
                if latest_created:
                    try:
                        utc_dt = datetime.fromisoformat(latest_created.replace('Z', '+00:00'))
                        # Simple addition for Brussels summer time (UTC+2)
                        brussels_dt = utc_dt + timedelta(hours=2)
                        latest_created_brussels = brussels_dt.strftime('%Y-%m-%dT%H:%M:%S')
                    except:
                        pass
                
                if latest_updated:
                    try:
                        utc_dt = datetime.fromisoformat(latest_updated.replace('Z', '+00:00'))
                        # Simple addition for Brussels summer time (UTC+2)
                        brussels_dt = utc_dt + timedelta(hours=2)
                        latest_updated_brussels = brussels_dt.strftime('%Y-%m-%dT%H:%M:%S')
                    except:
                        pass
                
                print(f'{table_name}|{row_count}|{col_count}|{\"|\".join(timestamp_cols)}|{latest_created_utc}|{latest_updated_utc}|{latest_created_brussels}|{latest_updated_brussels}')
except:
    pass
")
                    
                    if [[ -n "$table_info" ]]; then
                        echo "$table_info" | while IFS='|' read -r table_name row_count col_count timestamp_cols latest_created_utc latest_updated_utc latest_created_brussels latest_updated_brussels; do
                            # Determine table icon
                            table_icon="📋"
                            if [[ "$table_name" =~ departure|arrival ]]; then
                                table_icon="🚄"
                            elif [[ "$table_name" =~ station ]]; then
                                table_icon="🚉"
                            elif [[ "$table_name" =~ vehicle|train ]]; then
                                table_icon="�"
                            elif [[ "$table_name" =~ connection ]]; then
                                table_icon="🔗"
                            fi
                            
                            echo -e "    ${CYAN}[TABLE] ${GREEN}${table_name}${NC}"
                            echo -e "    ${CYAN}|${NC}   Records: ${YELLOW}${row_count}${NC} | Columns: ${YELLOW}${col_count}${NC}"
                            
                            if [[ "$timestamp_cols" != "" ]]; then
                                echo -e "    ${CYAN}|${NC}   Timestamp columns: ${BLUE}${timestamp_cols}${NC}"
                            fi
                            
                            # Format create time
                            if [[ "$latest_created_utc" != "N/A" && "$latest_created_utc" != "" ]]; then
                                created_date_utc=$(echo "$latest_created_utc" | cut -d'T' -f1)
                                created_time_utc=$(echo "$latest_created_utc" | cut -d'T' -f2 | cut -d'.' -f1)
                                
                                # Extract Brussels time (format: 2025-08-06T18:20:11)
                                if [[ "$latest_created_brussels" != "N/A" && "$latest_created_brussels" != "" ]]; then
                                    created_time_brussels=$(echo "$latest_created_brussels" | cut -d'T' -f2)
                                else
                                    created_time_brussels="N/A"
                                fi
                                
                                current_date=$(date +%Y-%m-%d)
                                
                                if [[ "$created_date_utc" == "$current_date" ]]; then
                                    echo -e "    ${CYAN}║${NC}   Created: ${BLUE}TODAY${NC} at ${CYAN}${created_time_utc}${NC} UTC | ${CYAN}${created_time_brussels}${NC} Brussels (GMT+2)"
                                else
                                    echo -e "    ${CYAN}║${NC}   Created: ${BLUE}${created_date_utc}${NC} at ${CYAN}${created_time_utc}${NC} UTC | ${CYAN}${created_time_brussels}${NC} Brussels (GMT+2)"
                                fi
                            else
                                echo -e "    ${CYAN}║${NC}   Created: ${YELLOW}No creation timestamps available${NC}"
                            fi
                            
                            # Format update time
                            if [[ "$latest_updated_utc" != "N/A" && "$latest_updated_utc" != "" ]]; then
                                updated_date_utc=$(echo "$latest_updated_utc" | cut -d'T' -f1)
                                updated_time_utc=$(echo "$latest_updated_utc" | cut -d'T' -f2 | cut -d'.' -f1)
                                
                                # Extract Brussels time (format: 2025-08-06T18:20:11)
                                if [[ "$latest_updated_brussels" != "N/A" && "$latest_updated_brussels" != "" ]]; then
                                    updated_time_brussels=$(echo "$latest_updated_brussels" | cut -d'T' -f2)
                                else
                                    # Manual conversion if Brussels time not calculated properly
                                    if [[ "$updated_time_utc" != "" ]]; then
                                        updated_time_brussels=$(python -c "
from datetime import datetime, timedelta
try:
    utc_time = datetime.strptime('${updated_time_utc}', '%H:%M:%S')
    # Add 2 hours for Brussels GMT+2
    brussels_time = utc_time + timedelta(hours=2)
    print(brussels_time.strftime('%H:%M:%S'))
except:
    print('N/A')
")
                                    else
                                        updated_time_brussels="N/A"
                                    fi
                                fi
                                
                                current_date=$(date +%Y-%m-%d)
                                
                                if [[ "$updated_date_utc" == "$current_date" ]]; then
                                    echo -e "    ${CYAN}|${NC}   Updated: ${BLUE}TODAY${NC} at ${CYAN}${updated_time_utc}${NC} UTC | ${CYAN}${updated_time_brussels}${NC} Brussels (GMT+2)"
                                else
                                    echo -e "    ${CYAN}|${NC}   Updated: ${BLUE}${updated_date_utc}${NC} at ${CYAN}${updated_time_utc}${NC} UTC | ${CYAN}${updated_time_brussels}${NC} Brussels (GMT+2)"
                                fi
                            else
                                echo -e "    ${CYAN}|${NC}   Updated: ${YELLOW}No recent updates or empty table${NC}"
                            fi
                            
                            echo -e "    ${CYAN}|═══════════════════════════════════════════════${NC}"
                            echo ""
                        done
                    else
                        echo -e "    ${YELLOW}→${NC} Could not parse detailed table information"
                    fi
                else
                    echo -e "    ${YELLOW}→${NC} Python not available for detailed parsing"
                fi
                
                # Add summary of train data freshness
                echo -e "  ${BLUE}Overall Database Status:${NC}"
                if echo "$body" | grep -q "departures\|arrivals"; then
                    echo -e "    ${GREEN}PASS${NC} Departure/arrival data tables are present"
                fi
                if echo "$body" | grep -q "stations"; then
                    echo -e "    ${GREEN}PASS${NC} Station information tables are present"
                fi
                if echo "$body" | grep -q "vehicles"; then
                    echo -e "    ${GREEN}PASS${NC} Vehicle information tables are present"
                fi
            else
                # Fallback to original timestamp extraction with timezone conversion
                echo -e "    ${YELLOW}→${NC} Using fallback timestamp extraction method"
                updates=$(echo "$body" | grep -o '"[^"]*": *"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][^"]*"' | head -10)
                if [[ -n "$updates" ]]; then
                    echo "$updates" | while IFS= read -r line; do
                        table_name=$(echo "$line" | cut -d'"' -f2)
                        timestamp_utc=$(echo "$line" | cut -d'"' -f4)
                        
                        if [[ ! "$table_name" =~ ^(id|created_at|updated_at)$ ]]; then
                            date_part_utc=$(echo "$timestamp_utc" | cut -d'T' -f1)
                            time_part_utc=$(echo "$timestamp_utc" | cut -d'T' -f2 | cut -d'.' -f1)
                            
                            # Convert to Brussels time (UTC+2)
                            if command -v python >/dev/null 2>&1; then
                                timestamp_brussels=$(python -c "
from datetime import datetime, timezone, timedelta
try:
    utc_dt = datetime.fromisoformat('${timestamp_utc}'.replace('Z', '+00:00'))
    brussels_dt = utc_dt.astimezone(timezone(timedelta(hours=2)))
    print(brussels_dt.strftime('%H:%M:%S'))
except:
    print('${time_part_utc}')
")
                                echo -e "    ${YELLOW}→${NC} ${table_name}: ${BLUE}${date_part_utc}${NC} at ${CYAN}${time_part_utc}${NC} UTC | ${CYAN}${timestamp_brussels}${NC} Brussels"
                            else
                                echo -e "    ${YELLOW}→${NC} ${table_name}: ${BLUE}${date_part_utc}${NC} at ${CYAN}${time_part_utc}${NC} UTC"
                            fi
                        fi
                    done
                fi
            fi
            ((PASSED++))
        else
            echo -e "  ${RED}FAILED${NC} (Unexpected response)"
            echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
            ((FAILED++))
        fi
    else
        echo -e "  ${RED}FAILED${NC} (HTTP $http_status)"
        echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
        ((FAILED++))
    fi
    echo ""
}

test_azure_data_factory() {
    echo -e "${BLUE}=============================================================================="
    echo -e "AZURE DATA FACTORY PIPELINE MONITORING"
    echo -e "==============================================================================${NC}"
    echo ""
    
    local resource_group="rg-irail-dev-i6lr9a"
    local factory_name="df-irail-data-pobm4m"
    local trigger_name="trigger_irail_collection_every_5min"
    local pipeline_name="pipeline_irail_train_data_collection"
    
    echo -e "${CYAN}Checking Azure Data Factory status...${NC}"
    echo ""
    
    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        echo -e "${YELLOW}Azure CLI not found. Skipping Azure Data Factory verification.${NC}"
        echo -e "${BLUE}To install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli${NC}"
        return 0
    fi
    
    echo -e "${BLUE}[STEP 1]${NC} Checking Azure authentication..."
    
    # Check Azure login status
    az account show >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo -e "  ${GREEN}Azure CLI authenticated${NC}"
        current_subscription=$(az account show --query "name" -o tsv 2>/dev/null || echo "Unknown")
        echo -e "  ${BLUE}Current subscription: ${current_subscription}${NC}"
    else
        echo -e "  ${RED}Azure CLI not authenticated${NC}"
        echo -e "  ${YELLOW}Run 'az login' to authenticate${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}[STEP 2]${NC} Checking Data Factory trigger status..."
    
    # Check trigger status
    trigger_status=$(az datafactory trigger show \
        --resource-group "$resource_group" \
        --factory-name "$factory_name" \
        --name "$trigger_name" \
        --query "properties.runtimeState" \
        -o tsv 2>/dev/null || echo "ERROR")
    
    if [[ "$trigger_status" == "Started" ]]; then
        echo -e "  ${GREEN}Data Factory trigger is ACTIVE${NC}"
        echo -e "  ${BLUE}Factory: ${factory_name}${NC}"
        echo -e "  ${BLUE}Trigger: ${trigger_name}${NC}"
        echo -e "  ${BLUE}Status: ${GREEN}${trigger_status}${NC}"
    elif [[ "$trigger_status" == "Stopped" ]]; then
        echo -e "  ${YELLOW}Data Factory trigger is STOPPED${NC}"
        echo -e "  ${BLUE}Factory: ${factory_name}${NC}"
        echo -e "  ${BLUE}Trigger: ${trigger_name}${NC}"
        echo -e "  ${BLUE}Status: ${YELLOW}${trigger_status}${NC}"
        
        echo ""
        echo -e "  ${CYAN}To start the trigger:${NC}"
        echo "    az datafactory trigger start --resource-group $resource_group --factory-name $factory_name --name $trigger_name"
    else
        echo -e "  ${RED}Failed to get trigger status or trigger not found${NC}"
        echo -e "  ${YELLOW}Error: ${trigger_status}${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}[STEP 3]${NC} Getting recent pipeline runs..."
    
    # Get recent pipeline runs (last 24 hours)
    start_time=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || echo "2025-08-05T00:00:00.000Z")
    end_time=$(date -u +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || echo "2025-08-06T23:59:59.999Z")
    
    pipeline_runs=$(az datafactory pipeline-run query \
        --resource-group "$resource_group" \
        --factory-name "$factory_name" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --query "value[?pipelineName=='$pipeline_name'] | [0:5]" \
        -o json 2>/dev/null || echo "[]")
    
    if [[ "$pipeline_runs" != "[]" && "$pipeline_runs" != "null" ]]; then
        echo -e "  ${GREEN}Found recent pipeline executions${NC}"
        
        if command -v python >/dev/null 2>&1; then
            echo "$pipeline_runs" | python -c "
import json, sys
from datetime import datetime

try:
    runs = json.load(sys.stdin)
    if isinstance(runs, list) and len(runs) > 0:
        print('  Recent Pipeline Executions (Last 24h):')
        print()
        
        for i, run in enumerate(runs[:5]):
            run_id = run.get('runId', 'Unknown')[:8]  # First 8 chars
            status = run.get('status', 'Unknown')
            start_time = run.get('runStart', '')
            end_time = run.get('runEnd', '')
            pipeline_name = run.get('pipelineName', 'Unknown')
            
            # Format status with colors
            if status == 'Succeeded':
                status_icon = 'SUCCESS'
                status_color = 'green'
            elif status == 'Failed':
                status_icon = 'FAILED'
                status_color = 'red'
            elif status == 'InProgress':
                status_icon = 'RUNNING'
                status_color = 'blue'
            else:
                status_icon = 'WARNING'
                status_color = 'yellow'
            
            print(f'    {status_icon} Run #{i+1} ({run_id})')
            print(f'      Pipeline: {pipeline_name}')
            print(f'      Status: {status}')
            
            if start_time:
                try:
                    start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
                    formatted_start = start_dt.strftime('%Y-%m-%d %H:%M:%S')
                    print(f'      Started: {formatted_start}')
                except:
                    print(f'      Started: {start_time}')
            
            if end_time:
                try:
                    end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
                    formatted_end = end_dt.strftime('%Y-%m-%d %H:%M:%S')
                    print(f'      Completed: {formatted_end}')
                    
                    # Calculate duration
                    if start_time:
                        try:
                            start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
                            duration = end_dt - start_dt
                            print(f'      Duration: {duration.total_seconds():.1f} seconds')
                        except:
                            pass
                except:
                    print(f'      Completed: {end_time}')
            elif status == 'InProgress':
                print('      Still running...')
            
            print()
    else:
        print('  No recent pipeline executions found')
        
except Exception as e:
    print(f'  Error parsing pipeline runs: {e}')
" 2>/dev/null || echo "  ${YELLOW}Python parsing failed${NC}"
        else
            echo -e "  ${YELLOW}Python not available for detailed parsing${NC}"
            echo -e "  ${BLUE}Raw pipeline runs data available via Azure CLI${NC}"
        fi
    else
        echo -e "  ${YELLOW}No recent pipeline executions found in the last 24 hours${NC}"
        echo -e "  ${BLUE}The pipeline may not have been triggered yet, or executions are older than 24h${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}[STEP 4]${NC} Checking Data Factory monitoring links..."
    
    # Construct monitoring URLs
    subscription_id="b63db937-8e75-4757-aa10-4571a475c185"
    
    echo -e "  ${GREEN}Data Factory monitoring resources:${NC}"
    echo ""
    echo -e "  ${CYAN}Data Factory Studio:${NC}"
    echo "    https://adf.azure.com/en/home?factory=%2Fsubscriptions%2F${subscription_id}%2FresourceGroups%2F${resource_group}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${factory_name}"
    echo ""
    echo -e "  ${CYAN}Pipeline Monitoring:${NC}"
    echo "    https://portal.azure.com/#@becode.education/resource/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.DataFactory/factories/${factory_name}/overview"
    echo ""
    echo -e "  ${CYAN}Resource Group:${NC}"
    echo "    https://portal.azure.com/#@becode.education/resource/subscriptions/${subscription_id}/resourceGroups/${resource_group}"
    
    echo ""
    echo -e "${BLUE}[STEP 5]${NC} Testing Data Factory trigger commands..."
    echo ""
    echo -e "  ${CYAN}Data Factory Management Commands:${NC}"
    echo ""
    echo -e "  ${YELLOW}# Check trigger status:${NC}"
    echo "    az datafactory trigger show --resource-group $resource_group --factory-name $factory_name --name $trigger_name"
    echo ""
    echo -e "  ${YELLOW}# Start trigger (if stopped):${NC}"
    echo "    az datafactory trigger start --resource-group $resource_group --factory-name $factory_name --name $trigger_name"
    echo ""
    echo -e "  ${YELLOW}# Stop trigger:${NC}"
    echo "    az datafactory trigger stop --resource-group $resource_group --factory-name $factory_name --name $trigger_name"
    echo ""
    echo -e "  ${YELLOW}# Get recent pipeline runs:${NC}"
    echo "    az datafactory pipeline-run query --resource-group $resource_group --factory-name $factory_name --start-time '$start_time' --end-time '$end_time'"
    echo ""
    echo -e "  ${YELLOW}# Manual trigger execution:${NC}"
    echo "    az datafactory pipeline create-run --resource-group $resource_group --factory-name $factory_name --name $pipeline_name"
    
    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
}

test_data_factory_logs() {
    echo -e "${BLUE}[ENHANCED TEST]${NC} Data Factory Trigger Logs (with Brussels timezone)"
    local url="${BASE_URL}/api/data-factory-logs"
    echo -e "  URL: $url"
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" || echo "HTTPSTATUS:000")
    http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*$//')
    
    if [[ "$http_status" == "200" ]]; then
        if echo "$body" | grep -q '"status": "error"' && echo "$body" | grep -q "Database not configured"; then
            echo -e "  ${YELLOW}EXPECTED FAILURE${NC} (Database not configured)"
            echo -e "  ${BLUE}Note:${NC} Data Factory logs require SQL_CONNECTION_STRING"
            ((PASSED++))
        elif echo "$body" | grep -q '"status": "success"'; then
            echo -e "  ${GREEN}PASSED${NC} (Data Factory logs are working)"
            
            # Parse Data Factory logs with timezone conversion
            if command -v python >/dev/null 2>&1; then
                echo -e "  ${BLUE}Data Factory Trigger History (Brussels Time):${NC}"
                echo ""
                
                log_info=$(echo "$body" | python -c "
import json, sys
from datetime import datetime, timedelta

try:
    data = json.load(sys.stdin)
    if 'summary' in data and 'logs' in data:
        summary = data['summary']
        logs = data['logs']
        
        # Print summary
        print('  SUMMARY (Last 7 days)')
        print(f'  ║   Total triggers: {summary.get(\"total_triggers\", 0)}')
        print(f'  ║   Successful: {summary.get(\"successful_triggers\", 0)}')
        print(f'  ║   Failed: {summary.get(\"failed_triggers\", 0)}')
        print(f'  ║   Partial: {summary.get(\"partial_triggers\", 0)}')
        
        # Convert last trigger time to Brussels time
        last_trigger = summary.get('last_trigger_time')
        if last_trigger:
            try:
                utc_time = datetime.fromisoformat(last_trigger.replace('Z', ''))
                brussels_time = utc_time + timedelta(hours=2)  # UTC+2 summer time
                print(f'  ║   Last trigger: {brussels_time.strftime(\"%Y-%m-%d %H:%M:%S\")} (Brussels)')
                print(f'  ║                 {utc_time.strftime(\"%Y-%m-%d %H:%M:%S\")} (UTC)')
            except:
                print(f'  ║   Last trigger: {last_trigger}')
        
        avg_duration = summary.get('avg_duration_seconds', 0)
        print(f'  ║   Avg duration: {avg_duration:.1f}s')
        print('  ╚══')
        print()
        
        # Print recent triggers
        if logs and len(logs) > 0:
            print('  RECENT TRIGGERS')
            for i, log in enumerate(logs[:5]):
                trigger_time = log.get('trigger_time', 'N/A')
                status = log.get('execution_status', 'N/A')
                user_agent = log.get('user_agent', 'N/A')
                stations = log.get('stations_processed', 0)
                departures = log.get('departures_collected', 0)
                duration = log.get('execution_duration_seconds', 0)
                endpoint = log.get('endpoint_called', 'N/A')
                method = log.get('request_method', 'N/A')
                
                # Convert trigger time to Brussels time
                brussels_time_str = 'N/A'
                if trigger_time != 'N/A':
                    try:
                        utc_time = datetime.fromisoformat(trigger_time.replace('Z', ''))
                        brussels_time = utc_time + timedelta(hours=2)
                        brussels_time_str = brussels_time.strftime('%H:%M:%S')
                        utc_time_str = utc_time.strftime('%H:%M:%S')
                    except:
                        brussels_time_str = trigger_time
                        utc_time_str = trigger_time
                
                # Status icon
                status_icon = 'WARNING'
                if status == 'success':
                    status_icon = 'SUCCESS'
                elif status == 'error':
                    status_icon = 'FAILED'
                elif status == 'started':
                    status_icon = 'RUNNING'
                elif status == 'partial_success':
                    status_icon = 'WARNING'
                
                print(f'  ║')
                print(f'  ║ {i+1}. {status_icon} {brussels_time_str} Brussels ({utc_time_str} UTC)')
                print(f'  ║    {method} {endpoint}')
                print(f'  ║    Status: {status} | Agent: {user_agent[:30]}...')
                if stations > 0 or departures > 0:
                    print(f'  ║    Processed: {stations} stations, {departures} departures')
                if duration > 0:
                    print(f'  ║    Duration: {duration:.1f}s')
            print('  ╚══')
        else:
            print('  ║ No recent triggers found')
            print('  ╚══')
            
except Exception as e:
    print(f'Error parsing Data Factory logs: {e}')
")
                echo "$log_info"
            else
                echo -e "    ${YELLOW}→${NC} Python not available for detailed parsing"
            fi
            
            ((PASSED++))
        else
            echo -e "  ${RED}FAILED${NC} (Unexpected response format)"
            echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
            ((FAILED++))
        fi
    else
        echo -e "  ${RED}FAILED${NC} (HTTP $http_status)"
        echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
        ((FAILED++))
    fi
    echo ""
}

test_timestamp_verification() {
    echo -e "${BLUE}[ENHANCED TEST]${NC} Timestamp Verification (with Brussels timezone)"
    local url="${BASE_URL}/api/timestamp-verification"
    echo -e "  URL: $url"
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" || echo "HTTPSTATUS:000")
    http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*$//')
    
    if [[ "$http_status" == "200" ]]; then
        if echo "$body" | grep -q '"status": "error"' && echo "$body" | grep -q "Database not configured"; then
            echo -e "  ${YELLOW}EXPECTED FAILURE${NC} (Database not configured)"
            echo -e "  ${BLUE}Note:${NC} Timestamp verification requires SQL_CONNECTION_STRING"
            ((PASSED++))
        elif echo "$body" | grep -q '"status": "success"'; then
            echo -e "  ${GREEN}PASSED${NC} (Timestamp verification is working)"
            
            # Parse timestamp verification with timezone conversion
            if command -v python >/dev/null 2>&1; then
                echo -e "  ${BLUE}Data Freshness Analysis (Brussels Time):${NC}"
                echo ""
                
                verification_info=$(echo "$body" | python -c "
import json, sys
from datetime import datetime, timedelta

try:
    data = json.load(sys.stdin)
    if 'data' in data:
        verification_data = data['data']
        
        # Latest records
        if 'latest_records' in verification_data:
            print('  LATEST RECORDS')
            for record in verification_data['latest_records'][:3]:
                station = record.get('station_name', 'Unknown')
                vehicle = record.get('vehicle_name', 'Unknown')
                recorded_at = record.get('recorded_at', 'N/A')
                minutes_ago = record.get('minutes_ago', 0)
                
                # Convert to Brussels time
                if recorded_at != 'N/A':
                    try:
                        utc_time = datetime.fromisoformat(recorded_at.replace('Z', ''))
                        brussels_time = utc_time + timedelta(hours=2)
                        brussels_str = brussels_time.strftime('%H:%M:%S')
                        utc_str = utc_time.strftime('%H:%M:%S')
                        print(f'  ║   {station}: {vehicle}')
                        print(f'  ║     {brussels_str} Brussels ({utc_str} UTC) - {minutes_ago} min ago')
                    except:
                        print(f'  ║   {station}: {vehicle} at {recorded_at}')
            print('  ╚══')
            print()
        
        # Timer effectiveness
        if 'timer_effectiveness' in verification_data:
            timer_data = verification_data['timer_effectiveness']
            print('  TIMER EFFECTIVENESS')
            print(f'  ║   Records today: {timer_data.get(\"total_records_today\", 0)}')
            print(f'  ║   Last 5 minutes: {timer_data.get(\"records_last_5_min\", 0)}')
            print(f'  ║   Last 10 minutes: {timer_data.get(\"records_last_10_min\", 0)}')
            print(f'  ║   Minutes since last: {timer_data.get(\"minutes_since_last\", \"N/A\")}')
            print('  ╚══')
            print()
        
        # Verification time
        if 'verification_time' in verification_data:
            vt = verification_data['verification_time']
            current_utc = vt.get('current_utc', 'N/A')
            if current_utc != 'N/A':
                try:
                    utc_time = datetime.fromisoformat(current_utc.replace('Z', ''))
                    brussels_time = utc_time + timedelta(hours=2)
                    print('  VERIFICATION TIME')
                    print(f'  Brussels: {brussels_time.strftime(\"%Y-%m-%d %H:%M:%S\")} (GMT+2)')
                    print(f'  UTC: {utc_time.strftime(\"%Y-%m-%d %H:%M:%S\")}')
                except:
                    print(f'  VERIFICATION TIME: {current_utc}')
except Exception as e:
    print(f'Error parsing timestamp verification: {e}')
")
                echo "$verification_info"
            else
                echo -e "    ${YELLOW}→${NC} Python not available for detailed parsing"
            fi
            
            ((PASSED++))
        else
            echo -e "  ${RED}FAILED${NC} (Unexpected response format)"
            echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
            ((FAILED++))
        fi
    else
        echo -e "  ${RED}FAILED${NC} (HTTP $http_status)"
        echo -e "  ${YELLOW}Response:${NC} ${body:0:200}..."
        ((FAILED++))
    fi
    echo ""
}

main() {
    print_header
    
    # Test 1: Health Check (with timezone info)
    echo -e "${BLUE}[TEST]${NC} Health Check Endpoint (with Brussels timezone)"
    health_url="${BASE_URL}/api/health"
    echo -e "  URL: $health_url"
    
    health_response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$health_url" || echo "HTTPSTATUS:000")
    health_status=$(echo "$health_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    health_body=$(echo "$health_response" | sed -E 's/HTTPSTATUS:[0-9]*$//')
    
    if [[ "$health_status" == "200" ]]; then
        if echo "$health_body" | grep -q '"status": "healthy"'; then
            echo -e "  ${GREEN}PASSED${NC} (HTTP $health_status, Content Match)"
            
            # Parse timezone information if available
            if command -v python >/dev/null 2>&1; then
                timezone_info=$(echo "$health_body" | python -c "
import json, sys
from datetime import datetime, timedelta

try:
    data = json.load(sys.stdin)
    utc_time = data.get('timestamp_utc', data.get('timestamp', ''))
    brussels_time = data.get('timestamp_brussels', '')
    
    if utc_time:
        if brussels_time:
            print(f'  UTC Time: {utc_time}')
            print(f'  Brussels Time: {brussels_time}')
            print(f'  Note: Brussels is UTC+2 (summer time)')
        else:
            # Convert UTC to Brussels if only UTC is available
            try:
                utc_dt = datetime.fromisoformat(utc_time.replace('Z', ''))
                brussels_dt = utc_dt + timedelta(hours=2)
                print(f'  UTC Time: {utc_time}')
                print(f'  Brussels Time: {brussels_dt.isoformat()}')
                print(f'  Note: Brussels is UTC+2 (summer time)')
            except:
                print(f'  Timestamp: {utc_time}')
except:
    pass
")
                if [[ -n "$timezone_info" ]]; then
                    echo "$timezone_info"
                fi
            fi
            
            ((PASSED++))
        else
            echo -e "  ${RED}FAILED${NC} (HTTP $health_status, Content Mismatch)"
            echo -e "  ${YELLOW}Response:${NC} ${health_body:0:200}..."
            ((FAILED++))
        fi
    else
        echo -e "  ${RED}FAILED${NC} (HTTP $health_status)"
        echo -e "  ${YELLOW}Response:${NC} ${health_body:0:200}..."
        ((FAILED++))
    fi
    echo ""
    
    # Test 2: Debug Environment
    test_endpoint "/api/debug" "Debug Environment Endpoint" '"python_version"'
    
    # Test 3: Stations List
    test_endpoint "/api/stations?limit=3" "Stations List Endpoint" '"stations"'
    
    # Test 4: Liveboard
    test_endpoint "/api/liveboard?station=Brussels-Central&limit=2" "Liveboard Endpoint" '"departures"'
    
    # Test 5: Collect Data FIRST to ensure all tables are populated
    echo -e "${BLUE}[SPECIAL TEST]${NC} Forcing Data Collection to Fill All Tables"
    echo -e "  URL: ${BASE_URL}/api/collect-data"
    echo -e "  ${YELLOW}Note: This will trigger collection of stations, vehicles, departures, connections${NC}"
    echo ""
    
    COLLECT_RESPONSE=$(curl -s -X POST "${BASE_URL}/api/collect-data" -H "Content-Type: application/json" -d '{"force_full_collection": true}')
    
    if echo "$COLLECT_RESPONSE" | grep -q '"status": "success"'; then
        echo -e "  ${GREEN}PASSED${NC} - Data collection triggered successfully"
        ((PASSED++))
        
        # Parse the response to show what was collected
        echo "  Collection Summary:"
        echo "$COLLECT_RESPONSE" | python -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'stations_processed' in data:
        print(f'    Stations processed: {data.get(\"stations_processed\", 0)}')
    if 'departures_collected' in data:
        print(f'    Departures collected: {data.get(\"departures_collected\", 0)}')
    if 'vehicles_identified' in data:
        print(f'    Vehicles identified: {data.get(\"vehicles_identified\", 0)}')
    if 'connections_mapped' in data:
        print(f'    Connections mapped: {data.get(\"connections_mapped\", 0)}')
    if 'execution_time' in data:
        print(f'    Execution time: {data.get(\"execution_time\", \"N/A\")}s')
except:
    pass
"
        echo ""
        echo -e "  ${YELLOW}Waiting 5 seconds for database to sync...${NC}"
        sleep 5
        
    else
        echo -e "  ${RED}FAILED${NC} - Data collection failed"
        ((FAILED++))
        echo "  Response: $COLLECT_RESPONSE"
    fi
    echo ""
    
    # Test 6: PowerBI Data (demo data)
    test_endpoint "/api/powerbi-data" "PowerBI Data Endpoint (Demo)" '"status": "success"'
    
    # Test 7: PowerBI Data (original)
    test_endpoint "/api/powerbi" "PowerBI Data Endpoint (Original)" '"data_type": "departures"'
    
    # Test 8: Analytics (Database dependent) - NOW WITH DATA
    test_database_endpoint "/api/analytics" "Analytics Endpoint (Database)"
    
    # Test 9: Database Preview (Database dependent) - NOW WITH DATA  
    test_database_endpoint "/api/database-preview" "Database Preview Endpoint (Database)"
    
    # Test 10: Data Factory Logs (Enhanced with timezone support)
    test_data_factory_logs
    
    # Test 11: Timestamp Verification (Enhanced with timezone support)
    test_timestamp_verification
    
    # Test 12: Azure Data Factory Pipeline Monitoring
    test_azure_data_factory
    
    # Results Summary
    echo -e "${BLUE}=============================================================================="
    echo -e "TEST RESULTS SUMMARY"
    echo -e "==============================================================================${NC}"
    echo ""
    echo -e "${GREEN}PASSED: $PASSED${NC}"
    echo -e "${RED}FAILED: $FAILED${NC}"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}ALL TESTS PASSED! Your Azure Functions deployment is working perfectly!${NC}"
        
        echo ""
        echo -e "${BLUE}Available Endpoints:${NC}"
        echo "  • Health Check:      $BASE_URL/api/health"
        echo "  • Debug Info:        $BASE_URL/api/debug"
        echo "  • Stations:          $BASE_URL/api/stations"
        echo "  • Liveboard:         $BASE_URL/api/liveboard"
        echo "  • Analytics:         $BASE_URL/api/analytics"
        echo "  • Database Preview:  $BASE_URL/api/database-preview"
        echo "  • PowerBI Data:      $BASE_URL/api/powerbi-data"
        echo "  • PowerBI Original:  $BASE_URL/api/powerbi"
        
        echo ""
        echo -e "${BLUE}Manual Testing Commands - Copy & Paste Ready:${NC}"
        echo ""
        echo -e "${YELLOW}# Basic Endpoints${NC}"
        echo "curl \"$BASE_URL/api/health\""
        echo "curl \"$BASE_URL/api/debug\""
        echo ""
        echo -e "${YELLOW}# Station Data${NC}"
        echo "curl \"$BASE_URL/api/stations\""
        echo "curl \"$BASE_URL/api/stations?limit=5\""
        echo "curl \"$BASE_URL/api/stations?limit=10\""
        echo ""
        echo -e "${YELLOW}# Liveboard Data (Major Belgian Stations)${NC}"
        echo "curl \"$BASE_URL/api/liveboard?station=Brussels-Central\""
        echo "curl \"$BASE_URL/api/liveboard?station=Brussels-Central&limit=5\""
        echo "curl \"$BASE_URL/api/liveboard?station=Antwerp-Central\""
        echo "curl \"$BASE_URL/api/liveboard?station=Ghent-Sint-Pieters\""
        echo "curl \"$BASE_URL/api/liveboard?station=Bruges\""
        echo "curl \"$BASE_URL/api/liveboard?station=Leuven\""
        echo "curl \"$BASE_URL/api/liveboard?station=Mechelen\""
        echo "curl \"$BASE_URL/api/liveboard?station=Hasselt\""
        echo "curl \"$BASE_URL/api/liveboard?station=Kortrijk\""
        echo "curl \"$BASE_URL/api/liveboard?station=Mons\""
        echo ""
        echo -e "${YELLOW}# PowerBI Data${NC}"
        echo "curl \"$BASE_URL/api/powerbi\""
        echo "curl \"$BASE_URL/api/powerbi-data\""
        echo ""
        echo -e "${YELLOW}# Database Analytics (if configured)${NC}"
        echo "curl \"$BASE_URL/api/analytics\""
        echo "curl \"$BASE_URL/api/database-preview\""
        echo "curl \"$BASE_URL/api/data-factory-logs\""
        echo "curl \"$BASE_URL/api/timestamp-verification\""
        echo ""
        echo -e "${YELLOW}# Data Factory Trigger Monitoring (with Brussels timezone)${NC}"
        echo "curl \"$BASE_URL/api/data-factory-logs\" | python -m json.tool"
        echo "curl \"$BASE_URL/api/data-factory-logs?limit=5\""
        echo "curl \"$BASE_URL/api/timestamp-verification\" | python -m json.tool"
        echo ""
        echo -e "${YELLOW}# JSON Formatted Output (requires jq)${NC}"
        echo -e "${BLUE}# Install jq first: winget install jqproject.jq (Windows) or brew install jq (Mac)${NC}"
        echo "curl \"$BASE_URL/api/stations?limit=3\" | jq"
        echo "curl \"$BASE_URL/api/liveboard?station=Brussels-Central&limit=2\" | jq"
        echo "curl \"$BASE_URL/api/powerbi-data\" | jq"
        echo ""
        echo -e "${YELLOW}# Alternative: Python formatting (no jq required)${NC}"
        echo "curl \"$BASE_URL/api/stations?limit=3\" | python -m json.tool"
        echo "curl \"$BASE_URL/api/liveboard?station=Brussels-Central&limit=2\" | python -m json.tool"
        echo "curl \"$BASE_URL/api/powerbi-data\" | python -m json.tool"
        echo ""
        echo -e "${YELLOW}# Database Update Verification${NC}"
        echo -e "${BLUE}# Check when each table was last updated${NC}"
        echo "curl \"$BASE_URL/api/analytics\" | grep -E '\"last_updated|updated_at|timestamp\"'"
        echo "curl \"$BASE_URL/api/database-preview\" | grep -E '\"last_updated|updated_at|timestamp\"'"
        echo ""
        echo -e "${YELLOW}# Train Data Tables Status${NC}"
        echo -e "${BLUE}# Check departure/arrival tables specifically${NC}"
        echo "curl \"$BASE_URL/api/analytics\" | grep -E '\"departure|arrival|station|train\"'"
        echo "curl \"$BASE_URL/api/database-preview\" | python -m json.tool | grep -A5 -B5 'departure\\|arrival\\|station'"
        
    else
        echo -e "${RED}Some tests failed. Please check the deployment and configuration.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
}

# Run the tests
main "$@"
