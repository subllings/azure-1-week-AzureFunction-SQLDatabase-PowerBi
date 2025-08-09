import azure.functions as func
import json
import logging
import os
import pandas as pd
import requests
from datetime import datetime, timezone
from typing import Dict, List, Optional

# Try to import database drivers
try:
    import pyodbc
    PYODBC_AVAILABLE = True
except ImportError:
    PYODBC_AVAILABLE = False

try:
    import pymssql
    PYMSSQL_AVAILABLE = True
except ImportError:
    PYMSSQL_AVAILABLE = False

# New: Azure Identity for AAD tokens
try:
    from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
    AZURE_IDENTITY_AVAILABLE = True
except Exception:
    AZURE_IDENTITY_AVAILABLE = False

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Function App instance
app = func.FunctionApp()

# Configuration
IRAIL_API_BASE = os.environ.get('IRAIL_API_BASE_URL', 'https://api.irail.be')
USER_AGENT = os.environ.get('USER_AGENT', 'BeCodeTrainApp/1.0 (student.project@becode.education)')
SQL_CONNECTION_STRING = os.environ.get('SQL_CONNECTION_STRING')

# Helper to resolve requested Power BI data type from query params (new + legacy)
def _get_powerbi_requested_type(req: func.HttpRequest) -> str:
    return req.params.get('data_type') or req.params.get('type') or 'departures'

class iRailAPI:
    """iRail API client with rate limiting and error handling."""
    
    def __init__(self, base_url: str, user_agent: str):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': user_agent,
            'Accept': 'application/json'
        })
    
    def get_stations(self) -> List[Dict]:
        """Get all Belgian railway stations."""
        try:
            response = self.session.get(f"{self.base_url}/stations/", params={'format': 'json'})
            response.raise_for_status()
            data = response.json()
            return data.get('station', [])
        except requests.RequestException as e:
            logger.error(f"Error fetching stations: {e}")
            raise
    
    def get_liveboard(self, station_id: str, date: Optional[str] = None, time: Optional[str] = None) -> Dict:
        """Get live departure board for a station."""
        params = {
            'id': station_id,
            'format': 'json'
        }
        if date:
            params['date'] = date
        if time:
            params['time'] = time
            
        try:
            response = self.session.get(f"{self.base_url}/liveboard/", params=params)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            logger.error(f"Error fetching liveboard for station {station_id}: {e}")
            raise
    
    def get_connections(self, from_station: str, to_station: str, date: Optional[str] = None, time: Optional[str] = None) -> Dict:
        """Get connections between two stations."""
        params = {
            'from': from_station,
            'to': to_station,
            'format': 'json'
        }
        if date:
            params['date'] = date
        if time:
            params['time'] = time
            
        try:
            response = self.session.get(f"{self.base_url}/connections/", params=params)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            logger.error(f"Error fetching connections from {from_station} to {to_station}: {e}")
            raise

class DatabaseManager:
    """Manages database operations with connection pooling."""
    
    def __init__(self, connection_string: str):
        self.connection_string = connection_string or ""

    def _parse_conn(self) -> Dict[str, str]:
        parts = {}
        for raw in (self.connection_string or "").split(';'):
            if not raw:
                continue
            if '=' not in raw:
                continue
            k, v = raw.split('=', 1)
            key = k.strip().lower().replace(' ', '')  # normalize: 'User Id' -> 'userid'
            parts[key] = v.strip()
        return parts

    def _connect_with_managed_identity(self):
        # Requires pyodbc and azure-identity
        if not (PYODBC_AVAILABLE and AZURE_IDENTITY_AVAILABLE):
            raise Exception("pyodbc/azure-identity not available for MSI auth")
        p = self._parse_conn()
        server = p.get('server') or p.get('data source')
        database = p.get('database') or p.get('initialcatalog')
        client_id = p.get('clientid') or p.get('userid') or p.get('user id')
        if not server or not database:
            raise Exception("Server/Database missing in connection string")

        server_val = server
        if not server_val.lower().startswith('tcp:'):
            server_val = f"tcp:{server_val}"

        # Acquire MI token (prefer user-assigned when provided)
        if client_id:
            cred = ManagedIdentityCredential(client_id=client_id)
        else:
            cred = DefaultAzureCredential(exclude_interactive_browser_credential=True)
        token = cred.get_token("https://database.windows.net/.default").token
        token_bytes = token.encode('utf-16-le')
        SQL_COPT_SS_ACCESS_TOKEN = 1256

        base = f"Server={server_val};Database={database};Encrypt=yes;TrustServerCertificate=no;"
        candidates = [
            f"Driver={{ODBC Driver 18 for SQL Server}};{base}",
            f"Driver={{ODBC Driver 17 for SQL Server}};{base}"
        ]

        last_err = None
        for conn_str in candidates:
            try:
                logger.info(f"Trying SQL connection via pyodbc with driver candidate: {conn_str.split(';')[0]}")
                return pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_bytes}, autocommit=True)
            except Exception as e:
                last_err = e
                logger.warning(f"ODBC connect failed with candidate {conn_str.split(';')[0]}: {e}")
                continue
        raise Exception(f"ODBC drivers 18/17 not available or connection failed: {last_err}")

    def get_connection(self):
        # Detect MI auth in a normalized way
        norm = (self.connection_string or '').lower().replace(' ', '')
        if 'authentication=activedirectorymanagedidentity' in norm or 'authentication=activedirectorymsi' in norm:
            try:
                return self._connect_with_managed_identity()
            except Exception as e:
                logger.warning(f"MSI token connection failed: {e}")
        
        if PYODBC_AVAILABLE:
            try:
                return pyodbc.connect(self.connection_string)
            except Exception as e:
                logger.warning(f"Failed to connect with pyodbc: {e}")
        
        if PYMSSQL_AVAILABLE:
            try:
                p = self._parse_conn()
                return pymssql.connect(server=p.get('server'), database=p.get('database') or p.get('initialcatalog'), user=p.get('uid'), password=p.get('pwd'))
            except Exception as e:
                logger.warning(f"Failed to connect with pymssql: {e}")
        
        raise Exception("No working database driver available")
    
    def initialize_tables(self):
        """Create database tables if they don't exist."""
        create_tables_sql = """
        -- Stations table
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='stations' AND xtype='U')
        CREATE TABLE stations (
            id NVARCHAR(50) PRIMARY KEY,
            name NVARCHAR(255) NOT NULL,
            standardname NVARCHAR(255),
            locationX FLOAT,
            locationY FLOAT,
            uri NVARCHAR(500),
            created_at DATETIME2 DEFAULT GETUTCDATE()
        );
        
        -- Vehicles table
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='vehicles' AND xtype='U')
        CREATE TABLE vehicles (
            id NVARCHAR(50) PRIMARY KEY,
            name NVARCHAR(100),
            uri NVARCHAR(500),
            vehicle_type NVARCHAR(50),
            created_at DATETIME2 DEFAULT GETUTCDATE()
        );
        
        -- Departures table
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='departures' AND xtype='U')
        CREATE TABLE departures (
            id BIGINT IDENTITY(1,1) PRIMARY KEY,
            station_uri NVARCHAR(500) NOT NULL,
            station_name NVARCHAR(255),
            vehicle_uri NVARCHAR(500),
            vehicle_name NVARCHAR(100),
            platform NVARCHAR(10),
            scheduled_time DATETIME2,
            actual_time DATETIME2,
            delay_seconds INT DEFAULT 0,
            is_canceled BIT DEFAULT 0,
            departure_connection NVARCHAR(500),
            occupancy_level NVARCHAR(20),
            recorded_at DATETIME2 DEFAULT GETUTCDATE(),
            UNIQUE(station_uri, vehicle_uri, scheduled_time)
        );
        
        -- Connections table
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='connections' AND xtype='U')
        CREATE TABLE connections (
            id BIGINT IDENTITY(1,1) PRIMARY KEY,
            from_station_uri NVARCHAR(500) NOT NULL,
            to_station_uri NVARCHAR(500) NOT NULL,
            departure_time DATETIME2,
            arrival_time DATETIME2,
            duration_seconds INT,
            transfers INT DEFAULT 0,
            recorded_at DATETIME2 DEFAULT GETUTCDATE()
        );
        """
        
        with self.get_connection() as conn:
            conn.execute(create_tables_sql)
            conn.commit()
            logger.info("Database tables initialized successfully")
    
    def insert_stations(self, stations_data: List[Dict]):
        """Insert or update stations data."""
        df = pd.DataFrame(stations_data)
        
        # Prepare data
        df = df.rename(columns={
            '@id': 'uri',
            'standardname': 'standardname',
            'locationX': 'locationX',
            'locationY': 'locationY'
        })
        
        # Extract ID from URI
        df['id'] = df['uri'].str.extract(r'/(\d+)$')
        
        insert_sql = """
        MERGE stations AS target
        USING (VALUES (?, ?, ?, ?, ?, ?)) AS source (id, name, standardname, locationX, locationY, uri)
        ON target.id = source.id
        WHEN MATCHED THEN
            UPDATE SET name = source.name, standardname = source.standardname, 
                      locationX = source.locationX, locationY = source.locationY, uri = source.uri
        WHEN NOT MATCHED THEN
            INSERT (id, name, standardname, locationX, locationY, uri)
            VALUES (source.id, source.name, source.standardname, source.locationX, source.locationY, source.uri);
        """
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            for _, row in df.iterrows():
                cursor.execute(insert_sql, (
                    row['id'], row['name'], row.get('standardname'), 
                    row.get('locationX'), row.get('locationY'), row['uri']
                ))
            conn.commit()
            logger.info(f"Inserted/updated {len(df)} stations")
    
    def insert_departures(self, liveboard_data: Dict):
        """Insert departures data from liveboard."""
        if 'departures' not in liveboard_data or 'departure' not in liveboard_data['departures']:
            logger.warning("No departures data found")
            return
        
        departures = liveboard_data['departures']['departure']
        if not isinstance(departures, list):
            departures = [departures]
        
        station_info = liveboard_data.get('station', {})
        station_uri = station_info.get('@id', '')
        station_name = station_info.get('name', '')
        
        insert_sql = """
        INSERT INTO departures (station_uri, station_name, vehicle_uri, vehicle_name, platform, 
                               scheduled_time, actual_time, delay_seconds, is_canceled, departure_connection, occupancy_level)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            inserted_count = 0
            
            for departure in departures:
                try:
                    # Extract vehicle information
                    vehicle = departure.get('vehicle', {})
                    vehicle_uri = vehicle.get('@id', '')
                    vehicle_name = vehicle.get('name', '')
                    
                    # Extract timing information
                    scheduled_timestamp = int(departure.get('time', 0))
                    scheduled_time = datetime.fromtimestamp(scheduled_timestamp, tz=timezone.utc) if scheduled_timestamp else None
                    
                    delay = int(departure.get('delay', 0))
                    actual_time = datetime.fromtimestamp(scheduled_timestamp + delay, tz=timezone.utc) if scheduled_timestamp else None
                    
                    # Extract other information
                    platform = departure.get('platform', '')
                    is_canceled = departure.get('canceled', '0') == '1'
                    departure_uri = departure.get('departureConnection', '')
                    
                    # Occupancy information
                    occupancy = departure.get('occupancy', {})
                    occupancy_level = occupancy.get('@id', '').split('/')[-1] if occupancy.get('@id') else None
                    
                    cursor.execute(insert_sql, (
                        station_uri, station_name, vehicle_uri, vehicle_name, platform,
                        scheduled_time, actual_time, delay, is_canceled, departure_uri, occupancy_level
                    ))
                    inserted_count += 1
                    
                except Exception as e:
                    logger.warning(f"Error processing departure: {e}")
                    continue
            
            conn.commit()
            logger.info(f"Inserted {inserted_count} departures for station {station_name}")

# Initialize API client and database manager
irail_client = iRailAPI(IRAIL_API_BASE, USER_AGENT)
db_manager = DatabaseManager(SQL_CONNECTION_STRING) if SQL_CONNECTION_STRING else None

@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint."""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "timestamp": datetime.utcnow().isoformat()}),
        status_code=200,
        mimetype="application/json"
    )

@app.route(route="stations", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_stations(req: func.HttpRequest) -> func.HttpResponse:
    """Fetch and store all Belgian railway stations."""
    try:
        logger.info("Fetching stations from iRail API")
        stations = irail_client.get_stations()
        
        # Re-enable database operations for Power BI integration
        if db_manager:
            try:
                db_manager.initialize_tables()
                db_manager.insert_stations(stations)
                logger.info("Database operations enabled successfully")
            except Exception as db_error:
                logger.warning(f"Database operation failed: {db_error}")
                # Continue without database storage
        
        # Return first 20 stations to avoid timeout
        stations_subset = stations[:20] if len(stations) > 20 else stations
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "message": f"Fetched {len(stations)} stations from iRail API (showing first 20)",
                "total_stations": len(stations),
                "stations_shown": len(stations_subset),
                "stations": stations_subset,
                "note": "Database storage temporarily disabled due to driver compatibility issues"
            }),
            status_code=200,
            mimetype="application/json"
        )
    
    except Exception as e:
        logger.error(f"Error in get_stations: {e}")
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="liveboard", methods=["GET", "POST"], auth_level=func.AuthLevel.ANONYMOUS)
def get_liveboard(req: func.HttpRequest) -> func.HttpResponse:
    """Fetch live departure board for a station."""
    try:
        # Get station ID from query params or request body
        station_id = req.params.get('station')
        date = req.params.get('date')
        time = req.params.get('time')
        
        if not station_id:
            if req.get_json():
                data = req.get_json()
                station_id = data.get('station')
                date = data.get('date')
                time = data.get('time')
        
        if not station_id:
            return func.HttpResponse(
                json.dumps({"status": "error", "message": "Station ID is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        logger.info(f"Fetching liveboard for station: {station_id}")
        liveboard_data = irail_client.get_liveboard(station_id, date, time)
        
        # Re-enable database operations for Power BI integration
        if db_manager:
            try:
                db_manager.initialize_tables()
                db_manager.insert_departures(liveboard_data)
                logger.info("Liveboard data stored successfully")
            except Exception as db_error:
                logger.warning(f"Database operation failed: {db_error}")
                # Continue without database storage
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "message": "Liveboard data fetched successfully (database storage temporarily disabled)",
                "data": liveboard_data
            }),
            status_code=200,
            mimetype="application/json"
        )
    
    except Exception as e:
        logger.error(f"Error in get_liveboard: {e}")
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

@app.timer_trigger(schedule="0 0 */1 * * *", arg_name="myTimer", run_on_startup=False, use_monitor=False)
def scheduled_data_fetch(myTimer: func.TimerRequest) -> None:
    """Scheduled function to fetch train data every hour."""
    if myTimer.past_due:
        logger.info('The timer is past due!')
    
    try:
        logger.info("Starting scheduled data fetch")
        
        if not db_manager:
            logger.error("Database manager not initialized")
            return
        
        # Major Belgian stations for regular monitoring
        major_stations = [
            'BE.NMBS.008812005',  # Brussels Central
            'BE.NMBS.008813003',  # Brussels North
            'BE.NMBS.008814001',  # Brussels South
            'BE.NMBS.008892007',  # Antwerp Central
            'BE.NMBS.008841004',  # Gent Sint-Pieters
            'BE.NMBS.008833001',  # Leuven
            'BE.NMBS.008863008',  # Charleroi Sud
            'BE.NMBS.008844404',  # Bruges
            'BE.NMBS.008821006'   # Liège-Guillemins
        ]
        
        db_manager.initialize_tables()
        
        for station_id in major_stations:
            try:
                logger.info(f"Fetching liveboard for station: {station_id}")
                liveboard_data = irail_client.get_liveboard(station_id)
                db_manager.insert_departures(liveboard_data)
                
                # Respect rate limiting (3 requests per second)
                import time
                time.sleep(0.4)
                
            except Exception as e:
                logger.error(f"Error fetching data for station {station_id}: {e}")
                continue
        
        logger.info("Scheduled data fetch completed successfully")
        
    except Exception as e:
        logger.error(f"Error in scheduled_data_fetch: {e}")

@app.route(route="analytics", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_analytics(req: func.HttpRequest) -> func.HttpResponse:
    """Get analytics data from the database."""
    try:
        if not db_manager:
            return func.HttpResponse(
                json.dumps({"status": "error", "message": "Database not configured"}),
                status_code=500,
                mimetype="application/json"
            )
        
        analytics_sql = """
        SELECT 
            COUNT(*) as total_departures,
            COUNT(DISTINCT station_uri) as unique_stations,
            COUNT(DISTINCT vehicle_uri) as unique_vehicles,
            AVG(CAST(delay_seconds AS FLOAT)) as avg_delay_seconds,
            SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) as canceled_departures,
            MAX(recorded_at) as last_update
        FROM departures
        WHERE recorded_at >= DATEADD(day, -1, GETUTCDATE())
        """
        
        with db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(analytics_sql)
            result = cursor.fetchone()
            
            if not result:
                analytics = {
                    "total_departures": 0,
                    "unique_stations": 0,
                    "unique_vehicles": 0,
                    "avg_delay_seconds": 0.0,
                    "canceled_departures": 0,
                    "last_update": None
                }
            else:
                analytics = {
                    "total_departures": (result[0] or 0),
                    "unique_stations": (result[1] or 0),
                    "unique_vehicles": (result[2] or 0),
                    "avg_delay_seconds": round((result[3] or 0.0), 2),
                    "canceled_departures": (result[4] or 0),
                    "last_update": (result[5].isoformat() if result[5] else None)
                }
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "analytics": analytics
            }),
            status_code=200,
            mimetype="application/json"
        )
    
    except Exception as e:
        logger.error(f"Error in get_analytics: {e}")
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="powerbi-data", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_powerbi_data(req: func.HttpRequest) -> func.HttpResponse:
    """Get formatted data for Power BI consumption (legacy route)."""
    try:
        # Use unified resolver to accept both data_type (new) and type (legacy)
        data_type = _get_powerbi_requested_type(req)
        
        # For now, generate sample data to demonstrate Power BI integration
        if data_type == 'departures':
            # Generate sample departure data based on real iRail structure
            sample_data = []
            stations = ['Brussels-North', 'Brussels-Central', 'Antwerp-Central', 'Gent-Sint-Pieters']
            vehicle_types = ['IC', 'S1', 'S2', 'S3', 'ICE']
            
            import random
            base_time = datetime.utcnow()
            for i in range(50):  # Generate 50 sample records
                delay = random.randint(0, 1800)  # 0-30 minutes delay
                scheduled = base_time + pd.Timedelta(minutes=random.randint(-60, 180))
                actual = scheduled + pd.Timedelta(seconds=delay)
                
                sample_data.append({
                    'station_name': random.choice(stations),
                    'vehicle_name': f"{random.choice(vehicle_types)} {random.randint(100, 9999)}",
                    'platform': str(random.randint(1, 12)),
                    'scheduled_time': scheduled.isoformat(),
                    'actual_time': actual.isoformat(),
                    'delay_seconds': delay,
                    'is_canceled': random.random() < 0.05,
                    'occupancy_level': random.choice(['low', 'medium', 'high']),
                    'recorded_at': (datetime.utcnow() - pd.Timedelta(minutes=random.randint(0, 60))).isoformat()
                })
                
        elif data_type == 'stations':
            # Get real station data from iRail
            stations_data = irail_client.get_stations()[:20]  # First 20 stations
            sample_data = []
            for station in stations_data:
                sample_data.append({
                    'name': station.get('name', ''),
                    'standardname': station.get('standardname', ''),
                    'locationX': float(station.get('locationX', 0)),
                    'locationY': float(station.get('locationY', 0))
                })
                
        elif data_type == 'delays':
            # Generate sample delay analytics
            import random
            stations = ['Brussels-North', 'Brussels-Central', 'Antwerp-Central', 'Gent-Sint-Pieters']
            sample_data = []
            
            for station in stations:
                for days_back in range(7):  # Last 7 days
                    date = (datetime.utcnow() - pd.Timedelta(days=days_back)).date()
                    sample_data.append({
                        'station_name': station,
                        'avg_delay': random.randint(60, 600),  # 1-10 minutes average delay
                        'departure_count': random.randint(50, 200),
                        'date': date.isoformat()
                    })
        
        elif data_type == 'peak_hours':
            # Sample peak hour distribution per station
            import random
            stations = ['Brussels-North', 'Brussels-Central', 'Antwerp-Central', 'Gent-Sint-Pieters']
            sample_data = []
            for station in stations:
                for hour in range(24):
                    sample_data.append({
                        'station_name': station,
                        'hour': hour,
                        'departures': random.randint(0, 120)
                    })
        
        elif data_type == 'vehicles':
            # Sample vehicle mix
            import random
            vehicle_types = ['IC', 'S1', 'S2', 'S3', 'ICE']
            sample_data = []
            for vt in vehicle_types:
                sample_data.append({
                    'vehicle_type': vt,
                    'count': random.randint(50, 500)
                })
        
        elif data_type == 'connections':
            # Sample connections between stations
            import random
            stations = ['Brussels-North', 'Brussels-Central', 'Antwerp-Central', 'Gent-Sint-Pieters']
            sample_data = []
            for _ in range(50):
                a, b = random.sample(stations, 2)
                duration = random.randint(10, 120)
                sample_data.append({
                    'from_station': a,
                    'to_station': b,
                    'duration_minutes': duration,
                    'transfers': random.randint(0, 2)
                })
        else:
            return func.HttpResponse(
                json.dumps({"status": "error", "message": "Invalid data type"}),
                status_code=400,
                mimetype="application/json"
            )
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "data": sample_data,
                "count": len(sample_data),
                "note": "Sample data for Power BI demonstration - database connectivity will be restored"
            }),
            status_code=200,
            mimetype="application/json"
        )
    
    except Exception as e:
        logger.error(f"Error in get_powerbi_data: {e}")
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

# New canonical Power BI endpoint that replaces /api/powerbi-data
@app.route(route="powerbi", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_powerbi(req: func.HttpRequest) -> func.HttpResponse:
    """Canonical Power BI endpoint. Accepts 'data_type' (preferred) or 'type' (legacy)."""
    return get_powerbi_data(req)

@app.route(route="data-refresh", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def trigger_data_refresh(req: func.HttpRequest) -> func.HttpResponse:
    """Manually trigger data refresh for Power BI."""
    try:
        logger.info("Manual data refresh triggered")
        
        if not db_manager:
            return func.HttpResponse(
                json.dumps({"status": "error", "message": "Database not configured"}),
                status_code=500,
                mimetype="application/json"
            )
        
        # Major Belgian stations for data collection
        major_stations = [
            'BE.NMBS.008812005',  # Brussels Central
            'BE.NMBS.008813003',  # Brussels North  
            'BE.NMBS.008814001',  # Brussels South
            'BE.NMBS.008821006',  # Antwerp Central
            'BE.NMBS.008892007',  # Gent Sint-Pieters
            'BE.NMBS.008833001',  # Leuven
        ]
        
        db_manager.initialize_tables()
        collected_data = 0
        
        for station_id in major_stations:
            try:
                logger.info(f"Refreshing data for station: {station_id}")
                liveboard_data = irail_client.get_liveboard(station_id)
                db_manager.insert_departures(liveboard_data)
                collected_data += 1
                
                # Respect rate limiting
                import time
                time.sleep(0.5)
                
            except Exception as e:
                logger.error(f"Error refreshing data for station {station_id}: {e}")
                continue
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "message": f"Data refresh completed for {collected_data} stations",
                "timestamp": datetime.utcnow().isoformat()
            }),
            status_code=200,
            mimetype="application/json"
        )
    
    except Exception as e:
        logger.error(f"Error in trigger_data_refresh: {e}")
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="debug/odbc", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def debug_odbc(req: func.HttpRequest) -> func.HttpResponse:
    """Debug endpoint to report ODBC drivers and identity libs availability."""
    try:
        info = {
            "pyodbc_available": PYODBC_AVAILABLE,
            "pymssql_available": PYMSSQL_AVAILABLE,
            "azure_identity_available": AZURE_IDENTITY_AVAILABLE,
            "python_version": os.getenv('PYTHON_VERSION') or os.popen('python -V 2>&1').read().strip(),
            "site_name": os.getenv('WEBSITE_SITE_NAME'),
            "functions_runtime": os.getenv('FUNCTIONS_WORKER_RUNTIME'),
        }
        if PYODBC_AVAILABLE:
            try:
                import pyodbc as _py
                info["odbc_drivers"] = _py.drivers()
            except Exception as e:
                info["odbc_drivers_error"] = str(e)
        # Connection string diagnostics (no secrets)
        cs = (SQL_CONNECTION_STRING or "")
        norm = cs.lower().replace(' ', '')
        info["conn_has_msi_auth"] = ('authentication=activedirectorymanagedidentity' in norm) or ('authentication=activedirectorymsi' in norm)
        # Mask client id
        client_id = None
        for part in cs.split(';'):
            if part.strip().lower().startswith(('user id', 'user id=', 'userid=', 'clientid=')) or part.strip().lower().startswith('clientid='):
                try:
                    client_id = part.split('=',1)[1].strip()
                except Exception:
                    pass
        if client_id and len(client_id) > 8:
            info["client_id_suffix"] = client_id[-8:]
        else:
            info["client_id_suffix"] = client_id
        return func.HttpResponse(json.dumps({"status": "ok", "env": info}), status_code=200, mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(json.dumps({"status": "error", "message": str(e)}), status_code=500, mimetype="application/json")
