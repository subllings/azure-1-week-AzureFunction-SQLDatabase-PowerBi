#!/usr/bin/env python3
"""
Script de debug pour analyser les données iRail
"""
import requests
import json
from datetime import datetime, timezone

def test_irail_api():
    """Test direct de l'API iRail pour voir la structure des données"""
    
    api_url = "https://api.irail.be/liveboard/"
    params = {
        'station': 'Brussels-Central',
        'format': 'json',
        'lang': 'en'
    }
    
    headers = {
        'User-Agent': 'BeCodeTrainApp/1.0 (student.project@becode.education)'
    }
    
    print("🔍 Testant l'API iRail...")
    
    try:
        response = requests.get(api_url, params=params, headers=headers, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        print(f"✅ Réponse API reçue (status: {response.status_code})")
        
        # Analyser la structure des départs
        departures_section = data.get('departures', {})
        print(f"📊 Type de 'departures': {type(departures_section)}")
        
        if isinstance(departures_section, dict):
            departures = departures_section.get('departure', [])
            print(f"📊 Type de 'departure': {type(departures)}")
            print(f"📊 Nombre de départs: {len(departures) if isinstance(departures, list) else 1}")
            
            if departures:
                # Analyser le premier départ en détail
                first_dep = departures[0] if isinstance(departures, list) else departures
                print(f"\n🔍 STRUCTURE DU PREMIER DÉPART:")
                print(f"Type: {type(first_dep)}")
                
                if isinstance(first_dep, dict):
                    print(f"Clés disponibles: {list(first_dep.keys())}")
                    
                    # Analyser les champs critiques
                    vehicle_raw = first_dep.get('vehicle')
                    vehicleinfo_raw = first_dep.get('vehicleinfo')
                    
                    print(f"\n📍 Champ 'vehicle':")
                    print(f"  Type: {type(vehicle_raw)}")
                    print(f"  Valeur: {vehicle_raw}")
                    
                    print(f"\n📍 Champ 'vehicleinfo':")
                    print(f"  Type: {type(vehicleinfo_raw)}")
                    if isinstance(vehicleinfo_raw, dict):
                        print(f"  Clés: {list(vehicleinfo_raw.keys())}")
                        print(f"  shortname: {vehicleinfo_raw.get('shortname')}")
                        print(f"  name: {vehicleinfo_raw.get('name')}")
                    else:
                        print(f"  Valeur: {vehicleinfo_raw}")
                    
                    # Autres champs importants
                    print(f"\n📍 Autres champs:")
                    print(f"  platform: {first_dep.get('platform')} (type: {type(first_dep.get('platform'))})")
                    print(f"  time: {first_dep.get('time')} (type: {type(first_dep.get('time'))})")
                    print(f"  delay: {first_dep.get('delay')} (type: {type(first_dep.get('delay'))})")
                    print(f"  canceled: {first_dep.get('canceled')} (type: {type(first_dep.get('canceled'))})")
                    
                    # Test de l'extraction comme dans notre code
                    print(f"\n🧪 TEST D'EXTRACTION (comme dans function_app.py):")
                    
                    # Version corrigée
                    vehicle = first_dep.get('vehicle', '')
                    vehicleinfo = first_dep.get('vehicleinfo', {})
                    
                    if isinstance(vehicleinfo, dict) and 'shortname' in vehicleinfo:
                        vehicle_name = vehicleinfo.get('shortname', 'Unknown')
                        print(f"  ✅ Utilisé vehicleinfo.shortname: '{vehicle_name}'")
                    elif isinstance(vehicleinfo, dict) and 'name' in vehicleinfo:
                        vehicle_name = vehicleinfo.get('name', 'Unknown')
                        print(f"  ✅ Utilisé vehicleinfo.name: '{vehicle_name}'")
                    elif vehicle:
                        vehicle_name = str(vehicle)
                        print(f"  ⚠️ Fallback vers vehicle: '{vehicle_name}'")
                    else:
                        vehicle_name = 'Unknown'
                        print(f"  ❌ Aucune donnée véhicule: '{vehicle_name}'")
                    
                    # Test des autres champs
                    platform = str(first_dep.get('platform', ''))
                    time_val = first_dep.get('time', 0)
                    
                    try:
                        if time_val:
                            scheduled_time = datetime.fromtimestamp(int(time_val), tz=timezone.utc)
                            print(f"  ✅ Timestamp converti: {scheduled_time}")
                        else:
                            scheduled_time = datetime.now(timezone.utc)
                            print(f"  ⚠️ Pas de timestamp, utilise maintenant: {scheduled_time}")
                    except Exception as e:
                        print(f"  ❌ Erreur timestamp: {e}")
                        scheduled_time = datetime.now(timezone.utc)
                    
                    print(f"  📍 Données finales pour insertion:")
                    print(f"    station_name: 'Brussels-Central'")
                    print(f"    vehicle_name: '{vehicle_name}'")
                    print(f"    platform: '{platform}'")
                    print(f"    scheduled_time: {scheduled_time}")
                    
        # Sauvegarder un échantillon pour analyse
        with open('irail_sample_data.json', 'w') as f:
            json.dump(data, f, indent=2)
        print(f"\n💾 Données sauvées dans 'irail_sample_data.json'")
        
    except Exception as e:
        print(f"❌ Erreur: {e}")

if __name__ == "__main__":
    test_irail_api()
