"""
Correctif pour l'erreur de driver de base de données
Améliore la gestion des erreurs et ajoute des diagnostics
"""

import azure.functions as func
import json
import logging
import os
from typing import Dict, Any, Optional

# Configuration du logging améliorée
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Test des drivers disponibles avec diagnostic détaillé
def test_database_drivers():
    """Teste et diagnostique les drivers de base de données disponibles"""
    driver_status = {
        "pyodbc": {"available": False, "error": None},
        "pymssql": {"available": False, "error": None},
        "odbc_drivers": [],
        "environment": os.environ.get("FUNCTIONS_WORKER_RUNTIME", "unknown")
    }
    
    # Test pyodbc
    try:
        import pyodbc
        driver_status["pyodbc"]["available"] = True
        driver_status["odbc_drivers"] = pyodbc.drivers()
        logger.info(f"✅ pyodbc disponible. Drivers ODBC: {pyodbc.drivers()}")
    except ImportError as e:
        driver_status["pyodbc"]["error"] = f"Import failed: {str(e)}"
        logger.warning(f"❌ pyodbc non disponible: {e}")
    except Exception as e:
        driver_status["pyodbc"]["error"] = f"Other error: {str(e)}"
        logger.warning(f"❌ pyodbc erreur: {e}")
    
    # Test pymssql
    try:
        import pymssql
        driver_status["pymssql"]["available"] = True
        logger.info("✅ pymssql disponible")
    except ImportError as e:
        driver_status["pymssql"]["error"] = f"Import failed: {str(e)}"
        logger.warning(f"❌ pymssql non disponible: {e}")
    except Exception as e:
        driver_status["pymssql"]["error"] = f"Other error: {str(e)}"
        logger.warning(f"❌ pymssql erreur: {e}")
    
    return driver_status

# Fonction de diagnostic pour l'endpoint analytics
@func.FunctionApp().route(route="diagnostics", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def diagnostics(req: func.HttpRequest) -> func.HttpResponse:
    """Endpoint de diagnostic pour identifier les problèmes de base de données"""
    logger.info("=== DIAGNOSTIC DES DRIVERS DE BASE DE DONNÉES ===")
    
    try:
        # Test des drivers
        driver_status = test_database_drivers()
        
        # Informations sur l'environnement
        env_info = {
            "python_version": os.sys.version,
            "platform": os.sys.platform,
            "sql_connection_configured": bool(os.environ.get('SQL_CONNECTION_STRING')),
            "azure_functions_runtime": os.environ.get("FUNCTIONS_WORKER_RUNTIME"),
            "functions_version": os.environ.get("FUNCTIONS_EXTENSION_VERSION")
        }
        
        # Tentative de connexion à la base de données
        connection_test = {
            "attempted": False,
            "success": False,
            "error": None
        }
        
        sql_connection_string = os.environ.get('SQL_CONNECTION_STRING')
        if sql_connection_string and (driver_status["pyodbc"]["available"] or driver_status["pymssql"]["available"]):
            connection_test["attempted"] = True
            
            # Essayer pyodbc en premier
            if driver_status["pyodbc"]["available"]:
                try:
                    import pyodbc
                    conn = pyodbc.connect(sql_connection_string, timeout=10)
                    cursor = conn.cursor()
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
                    conn.close()
                    connection_test["success"] = True
                    connection_test["method"] = "pyodbc"
                    logger.info("✅ Connexion DB réussie avec pyodbc")
                except Exception as e:
                    connection_test["error"] = f"pyodbc failed: {str(e)}"
                    logger.warning(f"❌ Connexion pyodbc échouée: {e}")
            
            # Essayer pymssql si pyodbc a échoué
            if not connection_test["success"] and driver_status["pymssql"]["available"]:
                try:
                    import pymssql
                    # Parser la connection string pour pymssql
                    parts = sql_connection_string.split(';')
                    server = database = user = password = None
                    
                    for part in parts:
                        part = part.strip()
                        if part.startswith('Server='):
                            server = part.split('=', 1)[1].replace('tcp:', '').split(',')[0]
                        elif part.startswith('Initial Catalog='):
                            database = part.split('=', 1)[1]
                        elif part.startswith('User ID='):
                            user = part.split('=', 1)[1]
                        elif part.startswith('Password='):
                            password = part.split('=', 1)[1]
                    
                    conn = pymssql.connect(server=server, database=database, user=user, password=password)
                    cursor = conn.cursor()
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
                    conn.close()
                    connection_test["success"] = True
                    connection_test["method"] = "pymssql"
                    logger.info("✅ Connexion DB réussie avec pymssql")
                except Exception as e:
                    if connection_test["error"]:
                        connection_test["error"] += f" | pymssql failed: {str(e)}"
                    else:
                        connection_test["error"] = f"pymssql failed: {str(e)}"
                    logger.warning(f"❌ Connexion pymssql échouée: {e}")
        
        # Recommandations
        recommendations = []
        
        if not driver_status["pyodbc"]["available"] and not driver_status["pymssql"]["available"]:
            recommendations.append("❌ CRITIQUE: Aucun driver de base de données disponible")
            recommendations.append("🔧 Vérifier requirements.txt et redéployer la Function")
        
        if driver_status["pyodbc"]["available"] and not driver_status["odbc_drivers"]:
            recommendations.append("⚠️ pyodbc disponible mais aucun driver ODBC détecté")
            recommendations.append("🔧 Installer Microsoft ODBC Driver for SQL Server")
        
        if connection_test["attempted"] and not connection_test["success"]:
            recommendations.append("❌ Échec de connexion à la base de données")
            recommendations.append("🔧 Vérifier la string de connexion et les règles de firewall")
        
        if not connection_test["attempted"]:
            recommendations.append("⚠️ Test de connexion non effectué")
            recommendations.append("🔧 Configurer SQL_CONNECTION_STRING")
        
        # Réponse du diagnostic
        diagnostic_response = {
            "timestamp": func.HttpResponse.utcnow().isoformat(),
            "status": "success" if connection_test.get("success", False) else "warning",
            "summary": {
                "database_connection": "OK" if connection_test.get("success", False) else "FAILED",
                "drivers_available": any([driver_status["pyodbc"]["available"], driver_status["pymssql"]["available"]]),
                "environment": "Azure Functions" if env_info["azure_functions_runtime"] else "Local"
            },
            "details": {
                "drivers": driver_status,
                "environment": env_info,
                "connection_test": connection_test,
                "recommendations": recommendations
            }
        }
        
        # Log du résumé
        logger.info(f"🔍 Diagnostic terminé: {diagnostic_response['summary']}")
        
        return func.HttpResponse(
            json.dumps(diagnostic_response, indent=2),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logger.error(f"❌ Erreur durant le diagnostic: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                "timestamp": func.HttpResponse.utcnow().isoformat(),
                "status": "error",
                "message": f"Diagnostic failed: {str(e)}",
                "type": "diagnostic_error"
            }),
            status_code=500,
            mimetype="application/json"
        )

# Endpoint analytics amélioré avec fallback
@func.FunctionApp().route(route="analytics-fixed", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def analytics_fixed(req: func.HttpRequest) -> func.HttpResponse:
    """Version améliorée de l'endpoint analytics avec gestion d'erreur robuste"""
    logger.info("🔍 Analytics endpoint (version corrigée) appelé")
    
    try:
        # Test de la disponibilité des drivers
        driver_status = test_database_drivers()
        
        if not (driver_status["pyodbc"]["available"] or driver_status["pymssql"]["available"]):
            # Retourner des données de démonstration si pas de DB
            demo_data = {
                "status": "demo_mode",
                "message": "Database drivers unavailable - showing demo data",
                "data": {
                    "total_departures": 1248,
                    "unique_stations": 28,
                    "avg_delay_minutes": 4.2,
                    "on_time_percentage": 82.5,
                    "most_delayed_station": "Brussels-South",
                    "data_freshness": "Demo data",
                    "note": "This is demonstration data. Database connection failed."
                },
                "debug": {
                    "pyodbc_available": driver_status["pyodbc"]["available"],
                    "pymssql_available": driver_status["pymssql"]["available"],
                    "pyodbc_error": driver_status["pyodbc"]["error"],
                    "pymssql_error": driver_status["pymssql"]["error"]
                }
            }
            
            logger.warning("⚠️ Retour de données de démonstration (pas de driver DB)")
            return func.HttpResponse(
                json.dumps(demo_data),
                status_code=200,
                mimetype="application/json"
            )
        
        # Tentative de connexion réelle à la base de données
        sql_connection_string = os.environ.get('SQL_CONNECTION_STRING')
        if not sql_connection_string:
            return func.HttpResponse(
                json.dumps({
                    "status": "error",
                    "message": "SQL_CONNECTION_STRING not configured",
                    "timestamp": func.HttpResponse.utcnow().isoformat()
                }),
                status_code=500,
                mimetype="application/json"
            )
        
        # Essayer la connexion et récupérer de vraies données
        connection_successful = False
        real_data = {}
        
        # Essayer pyodbc en premier
        if driver_status["pyodbc"]["available"]:
            try:
                import pyodbc
                conn = pyodbc.connect(sql_connection_string, timeout=10)
                cursor = conn.cursor()
                
                # Requête pour les vraies analytics
                cursor.execute("""
                    SELECT 
                        COUNT(*) as total_departures,
                        COUNT(DISTINCT station_name) as unique_stations,
                        AVG(CAST(delay_seconds AS FLOAT)) / 60.0 as avg_delay_minutes,
                        (COUNT(CASE WHEN delay_seconds <= 300 THEN 1 END) * 100.0 / COUNT(*)) as on_time_percentage
                    FROM departures 
                    WHERE recorded_at >= DATEADD(day, -7, GETUTCDATE())
                """)
                
                row = cursor.fetchone()
                if row:
                    real_data = {
                        "total_departures": row[0] or 0,
                        "unique_stations": row[1] or 0,
                        "avg_delay_minutes": round(row[2] or 0, 2),
                        "on_time_percentage": round(row[3] or 0, 2),
                        "data_freshness": func.HttpResponse.utcnow().isoformat(),
                        "source": "real_database_pyodbc"
                    }
                    connection_successful = True
                
                conn.close()
                logger.info("✅ Données analytics récupérées avec pyodbc")
                
            except Exception as e:
                logger.warning(f"❌ Échec récupération avec pyodbc: {e}")
        
        # Essayer pymssql si pyodbc a échoué
        if not connection_successful and driver_status["pymssql"]["available"]:
            try:
                import pymssql
                # Parser connection string pour pymssql
                parts = sql_connection_string.split(';')
                server = database = user = password = None
                
                for part in parts:
                    part = part.strip()
                    if part.startswith('Server='):
                        server = part.split('=', 1)[1].replace('tcp:', '').split(',')[0]
                    elif part.startswith('Initial Catalog='):
                        database = part.split('=', 1)[1]
                    elif part.startswith('User ID='):
                        user = part.split('=', 1)[1]
                    elif part.startswith('Password='):
                        password = part.split('=', 1)[1]
                
                conn = pymssql.connect(server=server, database=database, user=user, password=password)
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT 
                        COUNT(*) as total_departures,
                        COUNT(DISTINCT station_name) as unique_stations,
                        AVG(CAST(delay_seconds AS FLOAT)) / 60.0 as avg_delay_minutes,
                        (COUNT(CASE WHEN delay_seconds <= 300 THEN 1 END) * 100.0 / COUNT(*)) as on_time_percentage
                    FROM departures 
                    WHERE recorded_at >= DATEADD(day, -7, GETUTCDATE())
                """)
                
                row = cursor.fetchone()
                if row:
                    real_data = {
                        "total_departures": row[0] or 0,
                        "unique_stations": row[1] or 0,
                        "avg_delay_minutes": round(row[2] or 0, 2),
                        "on_time_percentage": round(row[3] or 0, 2),
                        "data_freshness": func.HttpResponse.utcnow().isoformat(),
                        "source": "real_database_pymssql"
                    }
                    connection_successful = True
                
                conn.close()
                logger.info("✅ Données analytics récupérées avec pymssql")
                
            except Exception as e:
                logger.warning(f"❌ Échec récupération avec pymssql: {e}")
        
        if connection_successful:
            response_data = {
                "status": "success",
                "data": real_data,
                "timestamp": func.HttpResponse.utcnow().isoformat()
            }
        else:
            # Fallback vers données de démo avec explication
            response_data = {
                "status": "fallback",
                "message": "Database connection failed - returning demo data",
                "data": {
                    "total_departures": 1248,
                    "unique_stations": 28,
                    "avg_delay_minutes": 4.2,
                    "on_time_percentage": 82.5,
                    "data_freshness": "Demo data (DB connection failed)",
                    "source": "fallback_demo"
                },
                "timestamp": func.HttpResponse.utcnow().isoformat()
            }
        
        return func.HttpResponse(
            json.dumps(response_data),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logger.error(f"❌ Erreur dans analytics-fixed: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                "status": "error",
                "message": f"Analytics endpoint failed: {str(e)}",
                "timestamp": func.HttpResponse.utcnow().isoformat()
            }),
            status_code=500,
            mimetype="application/json"
        )

if __name__ == "__main__":
    # Test local
    print("Testing database drivers...")
    driver_status = test_database_drivers()
    print(f"Driver status: {driver_status}")
