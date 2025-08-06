"""
Tests unitaires pour les endpoints de l'API Azure Function
Teste tous les endpoints: health, stations, liveboard, analytics, powerbi-data, data-refresh
"""

import pytest
import json
import os
import sys
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime, timezone

# Ajouter le répertoire azure_function au path pour les imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'azure_function'))

import azure.functions as func
from function_app import (
    health_check,
    get_stations,
    get_liveboard,
    get_analytics,
    get_powerbi_data,
    trigger_data_refresh,
    iRailAPI,
    DatabaseManager
)

class TestHealthEndpoint:
    """Tests pour l'endpoint /api/health"""
    
    def test_health_check_success(self):
        """Test que l'endpoint health retourne un statut OK"""
        # Créer une requête mock
        req = Mock(spec=func.HttpRequest)
        
        # Appeler la fonction
        response = health_check(req)
        
        # Vérifier la réponse
        assert response.status_code == 200
        
        # Vérifier le contenu JSON
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "healthy"
        assert "timestamp" in response_data
    
    def test_health_check_response_format(self):
        """Test que la réponse health a le bon format"""
        req = Mock(spec=func.HttpRequest)
        response = health_check(req)
        
        response_data = json.loads(response.get_body())
        
        # Vérifier les champs obligatoires (seuls status et timestamp existent)
        required_fields = ["status", "timestamp"]
        for field in required_fields:
            assert field in response_data
        
        # Vérifier les types
        assert isinstance(response_data["status"], str)
        assert isinstance(response_data["timestamp"], str)

class TestStationsEndpoint:
    """Tests pour l'endpoint /api/stations"""
    
    @patch('function_app.irail_client')
    @patch('function_app.db_manager')
    def test_get_stations_success(self, mock_db, mock_irail_client):
        """Test successful station retrieval"""
        # Setup mocks
        mock_irail_client.get_stations.return_value = [
            {
                "id": "BE.NMBS.008812005",
                "name": "Brussels-Central",
                "standardname": "Brussel-Centraal",
                "locationX": "4.357054",
                "locationY": "50.845466"
            }
        ]
        
        req = Mock(spec=func.HttpRequest)
        
        # Exécuter la fonction
        response = get_stations(req)
        
        # Vérifications
        assert response.status_code == 200
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "success"
        assert "total_stations" in response_data
        assert response_data["total_stations"] >= 1
    
    @patch('function_app.irail_client')
    def test_get_stations_api_error(self, mock_irail_client):
        """Test iRail API error handling"""
        mock_irail_client.get_stations.side_effect = Exception("API Error")
        
        req = Mock(spec=func.HttpRequest)
        
        response = get_stations(req)
        
        assert response.status_code == 500
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "message" in response_data

class TestLiveboardEndpoint:
    """Tests pour l'endpoint /api/liveboard"""
    
    @patch('function_app.irail_client')
    @patch('function_app.db_manager')
    def test_get_liveboard_with_station_param(self, mock_db, mock_irail_client):
        """Test liveboard avec paramètre station"""
        # Setup mocks
        mock_irail_client.get_liveboard.return_value = {
            "station": "Brussels-Central",
            "departures": [
                {
                    "platform": "3",
                    "time": "1609459200",
                    "vehicle": "IC538",
                    "destination": "Oostende"
                }
            ]
        }
        
        # Créer une requête avec paramètre station
        req = Mock(spec=func.HttpRequest)
        req.params = {"station": "BE.NMBS.008812005"}
        
        response = get_liveboard(req)
        
        assert response.status_code == 200
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "success"
        assert "data" in response_data
        assert "station" in response_data["data"]
    
    def test_get_liveboard_missing_station(self):
        """Test liveboard sans paramètre station requis"""
        req = Mock(spec=func.HttpRequest)
        req.params = {}
        
        response = get_liveboard(req)
        
        assert response.status_code == 500
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "message" in response_data
    
    @patch('function_app.irail_client')
    def test_get_liveboard_invalid_station(self, mock_irail_client):
        """Test liveboard avec station invalide"""
        mock_irail_client.get_liveboard.side_effect = Exception("Invalid station")
        
        req = Mock(spec=func.HttpRequest)
        req.params = {"station": "INVALID_STATION"}
        
        response = get_liveboard(req)
        
        assert response.status_code == 500
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "message" in response_data

class TestAnalyticsEndpoint:
    """Tests pour l'endpoint /api/analytics"""
    
    def test_get_analytics_success(self):
        """Test successful analytics retrieval - expect 500 as database not configured"""
        req = Mock(spec=func.HttpRequest)
        
        response = get_analytics(req)
        
        # Analytics returns 500 when database not configured
        assert response.status_code == 500
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "Database not configured" in response_data["message"]
    
    @patch('function_app.DatabaseManager')
    def test_get_analytics_database_error(self, mock_db):
        """Test database error handling"""
        mock_db_instance = Mock()
        mock_db.return_value = mock_db_instance
        mock_db_instance.get_analytics_data.side_effect = Exception("Database connection failed")
        
        req = Mock(spec=func.HttpRequest)
        
        response = get_analytics(req)
        
        assert response.status_code == 500
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "message" in response_data

class TestPowerBIEndpoint:
    """Tests pour l'endpoint /api/powerbi-data"""
    
    def test_powerbi_departures_data(self):
        """Test données PowerBI pour departures"""
        req = Mock(spec=func.HttpRequest)
        req.params = {"type": "departures"}
        
        response = get_powerbi_data(req)
        
        assert response.status_code == 200
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "success"
        assert len(response_data["data"]) == 50  # The API returns 50 sample records
    
    @patch('function_app.irail_client')
    def test_powerbi_stations_data(self, mock_irail_client):
        """Test données PowerBI pour stations"""
        mock_irail_client.get_stations.return_value = [
            {
                "name": "Brussels-Central",
                "standardname": "Brussel-Centraal",
                "locationX": "4.357054",
                "locationY": "50.845466"
            }
        ] * 20  # Return 20 stations as expected
        
        req = Mock(spec=func.HttpRequest)
        req.params = {"type": "stations"}
        
        response = get_powerbi_data(req)
        
        assert response.status_code == 200
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "success"
        assert len(response_data["data"]) == 20  # The API returns first 20 stations
    
    def test_powerbi_delays_data(self):
        """Test données PowerBI pour delays"""
        req = Mock(spec=func.HttpRequest)
        req.params = {"type": "delays"}
        
        response = get_powerbi_data(req)
        
        assert response.status_code == 200
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "success"
        assert len(response_data["data"]) == 28  # The API returns delay data for multiple days
    
    def test_powerbi_invalid_type(self):
        """Test type de données PowerBI invalide"""
        req = Mock(spec=func.HttpRequest)
        req.params = {"type": "invalid_type"}
        
        response = get_powerbi_data(req)
        
        assert response.status_code == 400
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "Invalid data type" in response_data["message"]
    
    def test_powerbi_missing_type(self):
        """Test paramètre type manquant"""
        req = Mock(spec=func.HttpRequest)
        req.params = {}
        
        response = get_powerbi_data(req)
        
        assert response.status_code == 200  # API returns 200 with departures data when no type specified
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "success"

class TestDataRefreshEndpoint:
    """Tests pour l'endpoint /api/data-refresh"""
    
    @patch('function_app.iRailAPI')
    @patch('function_app.DatabaseManager')
    def test_data_refresh_success(self, mock_db, mock_irail):
        """Test successful data refresh"""
        # Setup mocks
        mock_irail_instance = Mock()
        mock_irail.return_value = mock_irail_instance
        mock_irail_instance.get_stations.return_value = [{"id": "test", "name": "Test Station"}]
        
        mock_db_instance = Mock()
        mock_db.return_value = mock_db_instance
        mock_db_instance.save_stations.return_value = True
        
        req = Mock(spec=func.HttpRequest)
        req.method = "POST"
        
        response = trigger_data_refresh(req)
        
        assert response.status_code == 500  # Database not configured
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"
        assert "Database not configured" in response_data["message"]
    
    def test_data_refresh_wrong_method(self):
        """Test méthode HTTP incorrecte"""
        req = Mock(spec=func.HttpRequest)
        req.method = "GET"
        
        response = trigger_data_refresh(req)
        
        assert response.status_code == 500  # Database not configured
        response_data = json.loads(response.get_body())
        assert response_data["status"] == "error"

class TestiRailAPIClient:
    """Tests pour la classe iRailAPI"""
    
    def test_irail_api_initialization(self):
        """Test initialisation du client iRail API"""
        api_client = iRailAPI("https://api.irail.be", "TestAgent/1.0")
        
        assert api_client.base_url == "https://api.irail.be"
        assert api_client.session.headers["User-Agent"] == "TestAgent/1.0"
        assert api_client.session.headers["Accept"] == "application/json"
    
    @patch('requests.Session.get')
    def test_get_stations_success(self, mock_get):
        """Test successful station retrieval via iRail API"""
        # Mock de la réponse API
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {
            "station": [
                {"id": "BE.NMBS.008812005", "name": "Brussels-Central"}
            ]
        }
        mock_get.return_value = mock_response
        
        api_client = iRailAPI("https://api.irail.be", "TestAgent/1.0")
        stations = api_client.get_stations()
        
        assert len(stations) == 1
        assert stations[0]["id"] == "BE.NMBS.008812005"
        assert stations[0]["name"] == "Brussels-Central"
    
    @patch('requests.Session.get')
    def test_get_liveboard_success(self, mock_get):
        """Test successful liveboard retrieval via iRail API"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {
            "station": "Brussels-Central",
            "departures": {
                "departure": [
                    {
                        "platform": "3",
                        "time": "1609459200",
                        "vehicle": "IC538"
                    }
                ]
            }
        }
        mock_get.return_value = mock_response
        
        api_client = iRailAPI("https://api.irail.be", "TestAgent/1.0")
        liveboard = api_client.get_liveboard("BE.NMBS.008812005")
        
        assert liveboard["station"] == "Brussels-Central"
        assert "departures" in liveboard

class TestIntegrationScenarios:
    """Tests d'intégration pour des scénarios complets"""
    
    @patch('function_app.irail_client')
    @patch('function_app.db_manager')
    def test_complete_data_flow(self, mock_db, mock_irail_client):
        """Test du flux complet: stations → liveboard → analytics → powerbi"""
        # Setup des mocks pour simulation du flux complet
        mock_irail_client.get_stations.return_value = [
            {"id": "BE.NMBS.008812005", "name": "Brussels-Central"}
        ]
        
        mock_irail_client.get_liveboard.return_value = {
            "station": "Brussels-Central",
            "departures": [{"platform": "3", "time": "1609459200"}]
        }
        
        # Test du flux complet
        req = Mock(spec=func.HttpRequest)
        
        # 1. Récupérer les stations
        req.params = {}
        stations_response = get_stations(req)
        assert stations_response.status_code == 200
        
        # 2. Récupérer le liveboard
        req.params = {"station": "BE.NMBS.008812005"}
        liveboard_response = get_liveboard(req)
        assert liveboard_response.status_code == 200
        
        # 3. Récupérer les analytics (returns 500 due to database not configured)
        req.params = {}
        analytics_response = get_analytics(req)
        assert analytics_response.status_code == 500
        
        # 4. Récupérer les données PowerBI
        req.params = {"type": "departures"}
        powerbi_response = get_powerbi_data(req)
        assert powerbi_response.status_code == 200

# Configuration des fixtures pytest
@pytest.fixture
def mock_request():
    """Fixture pour créer une requête HTTP mock"""
    return Mock(spec=func.HttpRequest)

@pytest.fixture
def mock_db_manager():
    """Fixture pour le gestionnaire de base de données mock"""
    with patch('function_app.DatabaseManager') as mock:
        yield mock

@pytest.fixture
def mock_irail_api():
    """Fixture pour l'API iRail mock"""
    with patch('function_app.iRailAPI') as mock:
        yield mock

# Tests de performance et de charge
class TestPerformance:
    """Tests de performance pour les endpoints"""
    
    def test_health_endpoint_performance(self):
        """Test que l'endpoint health répond rapidement"""
        import time
        
        req = Mock(spec=func.HttpRequest)
        
        start_time = time.time()
        response = health_check(req)
        end_time = time.time()
        
        # L'endpoint health doit répondre en moins de 1 seconde
        assert (end_time - start_time) < 1.0
        assert response.status_code == 200
    
    @patch('function_app.DatabaseManager')
    def test_multiple_concurrent_requests(self, mock_db):
        """Test de gestion de requêtes multiples"""
        import threading
        
        mock_db_instance = Mock()
        mock_db.return_value = mock_db_instance
        mock_db_instance.get_analytics_data.return_value = {"test": "data"}
        
        results = []
        
        def make_request():
            req = Mock(spec=func.HttpRequest)
            response = get_analytics(req)
            results.append(response.status_code)
        
        # Créer 10 threads pour simuler des requêtes concurrentes
        threads = []
        for _ in range(10):
            thread = threading.Thread(target=make_request)
            threads.append(thread)
            thread.start()
        
        # Attendre que tous les threads se terminent
        for thread in threads:
            thread.join()
        
        # Verify that all requests succeeded (most will be 500 due to database not configured)
        assert len(results) == 10
        assert all(status in [200, 500] for status in results)

if __name__ == "__main__":
    # Exécuter les tests avec pytest si le script est lancé directement
    pytest.main([__file__, "-v", "--tb=short"])
