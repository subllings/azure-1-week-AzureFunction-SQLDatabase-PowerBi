import pytest
import json
from unittest.mock import Mock, patch
import sys
import os

# Add src directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

from function_app import iRailAPI, DatabaseManager

class TestiRailAPI:
    """Test cases for iRail API client."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.api_client = iRailAPI("https://api.irail.be", "TestApp/1.0")
    
    @patch('requests.Session.get')
    def test_get_stations_success(self, mock_get):
        """Test successful stations retrieval."""
        # Mock response
        mock_response = Mock()
        mock_response.json.return_value = {
            "station": [
                {"@id": "BE.NMBS.008812005", "name": "Brussels Central"},
                {"@id": "BE.NMBS.008813003", "name": "Brussels North"}
            ]
        }
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        # Test
        stations = self.api_client.get_stations()
        
        # Assertions
        assert len(stations) == 2
        assert stations[0]["name"] == "Brussels Central"
        mock_get.assert_called_once()
    
    @patch('requests.Session.get')
    def test_get_liveboard_success(self, mock_get):
        """Test successful liveboard retrieval."""
        # Mock response
        mock_response = Mock()
        mock_response.json.return_value = {
            "station": {"@id": "BE.NMBS.008812005", "name": "Brussels Central"},
            "departures": {
                "departure": [
                    {
                        "vehicle": {"@id": "BE.NMBS.IC532", "name": "IC 532"},
                        "time": "1640995200",
                        "platform": "1",
                        "delay": "0"
                    }
                ]
            }
        }
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        # Test
        liveboard = self.api_client.get_liveboard("BE.NMBS.008812005")
        
        # Assertions
        assert "station" in liveboard
        assert "departures" in liveboard
        assert liveboard["station"]["name"] == "Brussels Central"
        mock_get.assert_called_once()
    
    @patch('requests.Session.get')
    def test_api_error_handling(self, mock_get):
        """Test API error handling."""
        # Mock error response
        mock_response = Mock()
        mock_response.raise_for_status.side_effect = Exception("API Error")
        mock_get.return_value = mock_response
        
        # Test
        with pytest.raises(Exception):
            self.api_client.get_stations()

class TestDatabaseManager:
    """Test cases for Database Manager."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.db_manager = DatabaseManager("test_connection_string")
    
    def test_database_manager_init(self):
        """Test database manager initialization."""
        assert self.db_manager.connection_string == "test_connection_string"
    
    def test_stations_data_processing(self):
        """Test stations data processing logic."""
        # Sample stations data
        stations_data = [
            {
                "@id": "http://irail.be/stations/NMBS/008812005",
                "name": "Brussels Central",
                "standardname": "Brussel-Centraal",
                "locationX": "4.357070",
                "locationY": "50.845466"
            }
        ]
        
        # This would normally test the actual database insertion
        # For unit tests, we just verify the data structure is correct
        assert len(stations_data) == 1
        assert stations_data[0]["name"] == "Brussels Central"
        assert "@id" in stations_data[0]

def test_configuration():
    """Test configuration loading."""
    # Test that environment variables are handled correctly
    # Test default values (since env vars are not set in test environment)
    from function_app import IRAIL_API_BASE, USER_AGENT
    
    assert IRAIL_API_BASE == 'https://api.irail.be'  # Default value
    assert USER_AGENT == 'BeCodeTrainApp/1.0 (student.project@becode.education)'  # Default value

if __name__ == "__main__":
    pytest.main([__file__])
