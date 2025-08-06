import azure.functions as func
import json
import logging
import os
import pandas as pd
import pyodbc
import requests
from datetime import datetime, timezone
from typing import Dict, List, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Function App instance
app = func.FunctionApp()

# Configuration
IRAIL_API_BASE = os.environ.get('IRAIL_API_BASE_URL', 'https://api.irail.be')
USER_AGENT = os.environ.get('USER_AGENT', 'BeCodeTrainApp/1.0 (student.project@becode.education)')
SQL_CONNECTION_STRING = os.environ.get('SQL_CONNECTION_STRING')

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
        self.connection_string = connection_string
    
    def get_connection(self):
        """Get database connection."""
        return pyodbc.connect(self.connection_string)
    
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

@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint."""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "timestamp": datetime.utcnow().isoformat()}),
        status_code=200,
        mimetype="application/json"
    )

@app.route(route="stations", methods=["GET"])
def get_stations(req: func.HttpRequest) -> func.HttpResponse:
    """Fetch and store all Belgian railway stations."""
    try:
        logger.info("Fetching stations from iRail API")
        stations = irail_client.get_stations()
        
        if db_manager:
            db_manager.initialize_tables()
            db_manager.insert_stations(stations)
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "message": f"Fetched and stored {len(stations)} stations",
                "stations_count": len(stations)
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

@app.route(route="liveboard", methods=["GET", "POST"])
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
        
        if db_manager:
            db_manager.initialize_tables()
            db_manager.insert_departures(liveboard_data)
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "message": "Liveboard data fetched and stored successfully",
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

@app.route(route="analytics", methods=["GET"])
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
            
            analytics = {
                "total_departures": result[0] or 0,
                "unique_stations": result[1] or 0,
                "unique_vehicles": result[2] or 0,
                "avg_delay_seconds": round(result[3] or 0, 2),
                "canceled_departures": result[4] or 0,
                "last_update": result[5].isoformat() if result[5] else None
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
