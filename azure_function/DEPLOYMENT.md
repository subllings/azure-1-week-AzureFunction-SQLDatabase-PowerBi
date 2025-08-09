# Azure Function Deployment Guide

## Deploying Your iRail Train Data Function

### Method 1: Deploy via Azure Portal (Recommended for Beginners)

1. **Go to your Function App** in Azure Portal
   - Navigate to `traindata-function-app`
   - Click on "Functions" in the left menu

2. **Create a new Function**
   - Click "Create" → "HTTP trigger"
   - Name: `fetch_train_data`
   - Authorization level: Anonymous (for testing)

3. **Replace the default code**
   - Copy the content from `function_app.py`
   - Paste it into the Code + Test editor
   - Click "Save"

4. **Add Application Settings**
   - Go to "Configuration" → "Application settings"
   - Add these settings:
     ```
     SQL_CONNECTION_STRING = Server=tcp:traindata-sql-subllings.database.windows.net,1433;Initial Catalog=traindata-db;Persist Security Info=False;User ID=sqladmin;Password=MiLolita421+;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
     IRAIL_API_BASE_URL = https://api.irail.be
     IRAIL_API_FORMAT = json
     IRAIL_API_LANG = en
     ```

5. **Install Python packages**
   - The Function App will automatically install packages from `requirements.txt`
   - Or manually install via Console: `pip install azure-functions requests pyodbc pandas`

### Method 2: Deploy via VS Code (Advanced)

1. **Install VS Code Extensions**
   - Azure Functions
   - Python

2. **Open the azure_function folder**
   - Open VS Code in the `azure_function` directory

3. **Deploy**
   - Press F1 → "Azure Functions: Deploy to Function App"
   - Select your subscription and Function App
   - Confirm deployment

### Testing Your Function

#### Test the HTTP Trigger:
```bash
# Basic test (Brussels-Central)
GET https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net/api/fetch_train_data

# Test with specific station
GET https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net/api/fetch_train_data?station=Antwerp-Central

# Get statistics
GET https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net/api/get_train_stats
```

#### Expected Response:
```json
{
  "status": "success",
  "message": "Successfully processed 15 train records for Brussels-Central",
  "rows_inserted": 15,
  "timestamp": "2025-08-04T10:30:00Z",
  "station": "Brussels-Central"
}
```

### Monitoring and Debugging

1. **Check Function Logs**
   - Go to Functions → fetch_train_data → Monitor
   - View execution logs and errors

2. **Application Insights**
   - Check the Application Insights resource
   - View performance metrics and error traces

3. **Database Verification**
   - Connect to your SQL Database
   - Query: `SELECT TOP 10 * FROM train_departures ORDER BY created_at DESC`

### Scheduled Execution

The function includes a timer trigger that runs every 30 minutes:
- Fetches data from 5 major Belgian stations
- Stores all data in the SQL database
- Logs detailed execution information

### Troubleshooting

**Common Issues:**

1. **Connection String Error**
   - Verify SQL_CONNECTION_STRING in Application Settings
   - Test SQL connection manually

2. **iRail API Rate Limiting**
   - Function respects 3 requests/second limit
   - Check User-Agent header

3. **Package Import Errors**
   - Ensure requirements.txt is properly configured
   - Check Function App runtime version (Python 3.10)

4. **Database Permissions**
   - Verify SQL firewall allows Azure services
   - Check SQL authentication credentials

## Power BI Implementation

### PowerBI File Location
PowerBI `.pbix` file is located in the `./powerbi/` directory.

### Required Data Connections

The Power BI dashboard connects to the Azure Function's PowerBI API endpoint with different data types:

#### Connection 1: Departures Data
```
URL: https://func-irail-dev-i6lr9a.azurewebsites.net/api/powerbi?data_type=departures
```

#### Connection 2: Stations Data  
```
URL: https://func-irail-dev-i6lr9a.azurewebsites.net/api/powerbi?data_type=stations
```

#### Connection 3: Delays Data
```
URL: https://func-irail-dev-i6lr9a.azurewebsites.net/api/powerbi?data_type=delays
```

#### Connection 4: Peak Hours Data
```
URL: https://func-irail-dev-i6lr9a.azurewebsites.net/api/powerbi?data_type=peak_hours
```

#### Connection 5: Vehicles Data
```
URL: https://func-irail-dev-i6lr9a.azurewebsites.net/api/powerbi?data_type=vehicles
```

#### Connection 6: Connections Data
```
URL: https://func-irail-dev-i6lr9a.azurewebsites.net/api/powerbi?data_type=connections
```

### Data Endpoints for Analytics

These URLs provide structured data specifically formatted for Power BI analytics and visualization:

- **Departures**: Real-time and historical departure information
- **Stations**: Station metadata and usage statistics  
- **Delays**: Delay patterns and statistics across the network
- **Peak Hours**: Traffic patterns by time of day and location
- **Vehicles**: Rolling stock information and utilization
- **Connections**: Route connectivity and transfer data

### Setting Up Power BI Connections

1. **Open Power BI Desktop**
2. **Get Data** → **Web** → **Advanced**
3. **Enter the URL** for each data type above
4. **Configure refresh settings** for real-time data updates
5. **Create relationships** between tables based on common fields (station_id, vehicle_id, etc.)

### Next Steps

1. **Test the Function** - Verify data appears in SQL database
2. **Create Power BI Dashboard** - Connect to your SQL database
3. **Add Error Handling** - Enhance robustness
4. **Implement CI/CD** - Use the GitHub Actions pipeline for automation

Your Azure Function is now ready to collect Belgian train data!
