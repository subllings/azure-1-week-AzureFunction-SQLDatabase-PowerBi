# Azure Functions Performance Optimization & Anti-Timeout Guide

## 🚀 Implemented Solutions for Your iRail Functions

### 1. **Function-Level Optimizations** ✅

#### Connection Pooling
- **Global Connection Pool**: Reuses HTTP sessions across function calls
- **Thread-Safe**: Multiple concurrent requests share optimized connections
- **Auto-Cleanup**: Removes stale connections every 5 minutes

#### New Functions Added:
```python
@app.function_name("warmup")  # /api/warmup
@app.function_name("keep_alive")  # Timer: every 3 minutes
```

### 2. **Infrastructure Optimizations** ✅

#### Enhanced Function App Settings:
```hcl
"WEBSITE_USE_PLACEHOLDER"           = "0"   # Disable placeholder
"WEBSITE_WARMUP_PATH"               = "/api/warmup"  # Warmup endpoint
"WEBSITE_PRELOAD_ENABLED"           = "1"   # Faster cold starts
"WEBSITE_RUN_FROM_PACKAGE"          = "1"   # Better performance
"WEBSITE_HTTPSCALEV2_ENABLED"       = "1"   # HTTP scaling v2
```

#### Flex Consumption Plan (FC1):
- **Better than Y1**: More memory, faster startup
- **Cost-Optimized**: Pay per execution
- **Scale Limit**: Max 5 instances for staging

### 3. **Data Factory Warmup System** ✅

#### New Warmup Pipeline:
- **Function**: `pipeline_irail_function_warmup`
- **Trigger**: Every 3 minutes automatically
- **Activities**: 
  1. Call `/api/warmup` endpoint
  2. Verify `/api/health` response
  3. Test iRail API connectivity

#### Integration with Main Pipeline:
- **Enhanced Pipeline**: Includes warmup step before data collection
- **Wait Time**: 10-second pause after warmup
- **Health Check**: Verifies function readiness

## 🔥 How It Prevents Timeouts

### Cold Start Prevention:
1. **Warmup Trigger**: Runs every 3 minutes (keeps function "warm")
2. **Keep-Alive Timer**: Internal timer runs every 3 minutes
3. **Connection Pool**: Maintains active HTTP sessions
4. **Preloading**: Functions load faster on first call

### iRail API Reliability:
```python
# Connection pooling with keep-alive
session = connection_pool.get_session(timeout=30)
session.headers.update({
    'Connection': 'keep-alive',
    'Cache-Control': 'no-cache'
})

# Retry logic in Data Factory
"policy": {
    "timeout": "00:03:00",
    "retry": 2,
    "retryIntervalInSeconds": 45
}
```

### Timeout Configuration:
- **Function Timeout**: 5 minutes (default for Consumption plan)
- **HTTP Request Timeout**: 30 seconds per request
- **Data Factory Activity Timeout**: 3 minutes per activity
- **Retry Policy**: 2 retries with 45-second intervals

## 📊 Monitoring & Performance

### New Endpoints:
- **`GET /api/warmup`**: Manual warmup + performance report
- **`GET /api/health`**: Quick health check
- **`GET /api/debug`**: Detailed diagnostics

### Warmup Response Example:
```json
{
  "status": "warm",
  "warmup_duration_seconds": 0.856,
  "components": {
    "database": "connected",
    "http_connections": "ready", 
    "irail_api": "connected (145 stations available)"
  },
  "performance": {
    "active_sessions": 3,
    "function_memory_mb": 89.2
  },
  "next_warmup_recommended": "2024-12-10T14:07:00Z"
}
```

## 🎯 Expected Results

### Before Optimization:
- ❌ Cold starts: 10-30 seconds
- ❌ Random timeouts on iRail API calls  
- ❌ Inconsistent performance
- ❌ Data Factory failures

### After Optimization:
- ✅ Warm functions: < 2 seconds response
- ✅ Reliable iRail API connections
- ✅ Consistent 99%+ success rate
- ✅ Data Factory runs smoothly every 5 minutes

## 🛠️ Usage Instructions

### Deploy the Enhanced Infrastructure:
```bash
./scripts/deploy-staging.sh  # Includes all optimizations
```

### Manual Function Warmup:
```bash
curl https://your-function-app.azurewebsites.net/api/warmup
```

### Monitor Performance:
1. **Application Insights**: View function execution times
2. **Data Factory**: Monitor pipeline success rates
3. **Log Analytics**: Query detailed performance metrics

### Useful Queries (Log Analytics):
```kql
// Function execution times
requests 
| where name == "warmup" or name == "health"
| summarize avg(duration) by name
| order by avg_duration desc

// Data Factory pipeline success rate  
ADFPipelineRun
| where TimeGenerated > ago(24h)
| summarize 
    Total=count(),
    Success=countif(Status=="Succeeded"),
    Failed=countif(Status=="Failed")
| extend SuccessRate = (Success*100.0)/Total
```

## 🚨 Troubleshooting

### If Functions Still Timeout:

1. **Check Warmup Status**:
   ```bash
   curl https://your-function-app.azurewebsites.net/api/warmup
   ```

2. **Verify Data Factory Triggers**:
   - Warmup trigger should run every 3 minutes
   - Check trigger history in Azure Portal

3. **Monitor Application Insights**:
   - Look for "Function Timeout" errors
   - Check average execution times

4. **Increase Timeout (if needed)**:
   ```hcl
   # In azure-functions.tf
   "FUNCTIONS_EXTENSION_VERSION" = "~4"
   "AzureWebJobsStorage__functionTimeout" = "00:10:00"  # 10 minutes
   ```

## 📈 Performance Metrics to Monitor

- **Function Cold Start Time**: < 5 seconds
- **Warmup Execution Time**: < 2 seconds  
- **iRail API Response Time**: < 10 seconds
- **Data Factory Success Rate**: > 95%
- **Memory Usage**: < 100 MB per function

Your Azure Functions should now be highly reliable and resistant to timeouts! 🎉
