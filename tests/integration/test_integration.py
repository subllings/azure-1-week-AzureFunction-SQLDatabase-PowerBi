import pytest
import requests
import os
import time

# Configuration
FUNCTION_APP_URL = os.environ.get('FUNCTION_APP_URL', 'http://localhost:7071')
TIMEOUT = 30

class TestFunctionAppIntegration:
    """Integration tests for the deployed Function App."""
    
    def test_health_endpoint(self):
        """Test the health check endpoint."""
        response = requests.get(f"{FUNCTION_APP_URL}/api/health", timeout=TIMEOUT)
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data
    
    def test_stations_endpoint(self):
        """Test the stations endpoint."""
        response = requests.get(f"{FUNCTION_APP_URL}/api/stations", timeout=TIMEOUT)
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert "stations_count" in data
        assert data["stations_count"] > 0
    
    def test_liveboard_endpoint(self):
        """Test the liveboard endpoint with Brussels Central station."""
        # Brussels Central station ID
        station_id = "BE.NMBS.008812005"
        
        response = requests.get(
            f"{FUNCTION_APP_URL}/api/liveboard",
            params={"station": station_id},
            timeout=TIMEOUT
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert "data" in data
        assert "station" in data["data"]
    
    def test_liveboard_endpoint_post(self):
        """Test the liveboard endpoint with POST request."""
        # Brussels North station ID
        station_id = "BE.NMBS.008813003"
        
        response = requests.post(
            f"{FUNCTION_APP_URL}/api/liveboard",
            json={"station": station_id},
            headers={"Content-Type": "application/json"},
            timeout=TIMEOUT
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
    
    def test_liveboard_endpoint_error(self):
        """Test the liveboard endpoint with missing station parameter."""
        response = requests.get(f"{FUNCTION_APP_URL}/api/liveboard", timeout=TIMEOUT)
        
        assert response.status_code == 400
        data = response.json()
        assert data["status"] == "error"
        assert "Station ID is required" in data["message"]
    
    def test_analytics_endpoint(self):
        """Test the analytics endpoint."""
        # First, ensure we have some data by calling liveboard
        self.test_liveboard_endpoint()
        
        # Wait a moment for data to be processed
        time.sleep(2)
        
        response = requests.get(f"{FUNCTION_APP_URL}/api/analytics", timeout=TIMEOUT)
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert "analytics" in data
        
        analytics = data["analytics"]
        assert "total_departures" in analytics
        assert "unique_stations" in analytics
        assert "unique_vehicles" in analytics
        assert "avg_delay_seconds" in analytics
        assert "canceled_departures" in analytics

class TestDataQuality:
    """Test data quality and consistency."""
    
    def test_stations_data_quality(self):
        """Test that stations data has required fields."""
        response = requests.get(f"{FUNCTION_APP_URL}/api/stations", timeout=TIMEOUT)
        assert response.status_code == 200
        
        # Fetch a liveboard to verify data structure
        station_id = "BE.NMBS.008812005"
        liveboard_response = requests.get(
            f"{FUNCTION_APP_URL}/api/liveboard",
            params={"station": station_id},
            timeout=TIMEOUT
        )
        
        assert liveboard_response.status_code == 200
        data = liveboard_response.json()
        
        # Verify data structure
        assert "data" in data
        station_data = data["data"]["station"]
        assert "@id" in station_data
        assert "name" in station_data
    
    def test_departure_data_consistency(self):
        """Test that departure data is consistent."""
        station_id = "BE.NMBS.008812005"
        response = requests.get(
            f"{FUNCTION_APP_URL}/api/liveboard",
            params={"station": station_id},
            timeout=TIMEOUT
        )
        
        assert response.status_code == 200
        data = response.json()
        
        if "departures" in data["data"] and "departure" in data["data"]["departures"]:
            departures = data["data"]["departures"]["departure"]
            if not isinstance(departures, list):
                departures = [departures]
            
            for departure in departures:
                # Check required fields
                assert "vehicle" in departure
                assert "time" in departure
                assert "platform" in departure or departure.get("platform") == ""
                
                # Check vehicle data
                vehicle = departure["vehicle"]
                assert "@id" in vehicle
                assert "name" in vehicle

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
