#!/usr/bin/env python3
"""
Script de test pour appeler TOUS les endpoints Azure Function en local
"""
import requests
import json
import time
from datetime import datetime

# Configuration
BASE_URL = "http://localhost:7071/api"

def test_endpoint(endpoint, method="GET", params=None, data=None):
    """Test un endpoint et affiche le résultat"""
    url = f"{BASE_URL}/{endpoint}"
    print(f"\n{'='*80}")
    print(f"🔍 TEST: {method} {url}")
    if params:
        print(f"📝 Paramètres: {params}")
    print(f"{'='*80}")
    
    try:
        start_time = time.time()
        
        if method == "GET":
            response = requests.get(url, params=params, timeout=30)
        elif method == "POST":
            response = requests.post(url, params=params, json=data, timeout=30)
        
        end_time = time.time()
        duration = round((end_time - start_time) * 1000, 2)
        
        print(f"⏱️  Durée: {duration}ms")
        print(f"📊 Status: {response.status_code}")
        print(f"📋 Headers: {dict(response.headers)}")
        
        if response.status_code == 200:
            try:
                result = response.json()
                print(f"✅ SUCCÈS!")
                print(f"📄 Réponse JSON (taille: {len(response.text)} chars):")
                
                # Afficher un résumé intelligent
                if isinstance(result, dict):
                    if 'data' in result and isinstance(result['data'], list):
                        print(f"   📊 Nombre d'enregistrements: {len(result['data'])}")
                        if result['data']:
                            print(f"   🔬 Premier record exemple:")
                            print(f"      {json.dumps(result['data'][0], indent=6, ensure_ascii=False)}")
                    elif 'tables' in result:
                        print(f"   🗃️  Tables trouvées: {list(result['tables'].keys())}")
                        for table, table_data in result['tables'].items():
                            if 'row_count' in table_data:
                                print(f"      📋 {table}: {table_data['row_count']} records")
                    else:
                        print(f"   📄 Contenu complet:")
                        print(f"      {json.dumps(result, indent=6, ensure_ascii=False)}")
                else:
                    print(f"   📄 Réponse: {result}")
                    
            except json.JSONDecodeError:
                print(f"⚠️  Réponse non-JSON: {response.text[:500]}...")
        else:
            print(f"❌ ERREUR {response.status_code}")
            print(f"📄 Réponse: {response.text}")
            
    except requests.exceptions.Timeout:
        print(f"⏰ TIMEOUT après 30 secondes")
    except requests.exceptions.ConnectionError:
        print(f"🔌 ERREUR DE CONNEXION - Azure Function pas démarrée?")
    except Exception as e:
        print(f"💥 ERREUR: {str(e)}")

def main():
    print("🚀 TEST DE TOUS LES ENDPOINTS AZURE FUNCTION")
    print(f"🕐 Début: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"🌐 Base URL: {BASE_URL}")
    
    # 1. Test de santé
    test_endpoint("health")
    
    # 2. Test database-preview (pour voir les records de BDD)
    print("\n" + "="*50)
    print("🗃️  TEST SPÉCIAL: DATABASE RECORDS")
    print("="*50)
    test_endpoint("database-preview")
    test_endpoint("database-preview", params={"table": "stations"})
    test_endpoint("database-preview", params={"table": "departures"})
    
    # 3. Test analytics (données de base)
    test_endpoint("analytics")
    
    # 4. Test PowerBI endpoints (données simulées)
    test_endpoint("powerbi")
    test_endpoint("powerbi", params={"data_type": "departures", "limit": 5})
    test_endpoint("powerbi", params={"data_type": "stations"})
    
    # 5. Test powerbi-data (endpoint migré)
    test_endpoint("powerbi-data")
    test_endpoint("powerbi-data", params={"type": "departures", "limit": 3})
    
    # 6. Test stations (données iRail)
    test_endpoint("stations")
    
    # 7. Test liveboard (nécessite station_id)
    print("\n" + "="*50)
    print("🚂 TEST LIVEBOARD (nécessite station_id)")
    print("="*50)
    test_endpoint("liveboard", params={"station": "BE.NMBS.008812005"})  # Brussels Central
    
    print("\n" + "="*80)
    print("🏁 TESTS TERMINÉS!")
    print(f"🕐 Fin: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)
    
    print("\n💡 RÉSUMÉ:")
    print("   - /api/health → Test de base")
    print("   - /api/database-preview → Records de BDD SQL (500 si pas de BDD locale)")
    print("   - /api/powerbi → Données simulées pour Power BI")
    print("   - /api/powerbi-data → Données migrées")
    print("   - /api/stations → Vraies données des gares belges")
    print("   - /api/liveboard → Données temps réel d'une gare")
    print("   - /api/analytics → Statistiques de BDD")

if __name__ == "__main__":
    main()
