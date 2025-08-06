#!/usr/bin/env python3
"""
Test de diagnostic pour identifier le problème avec l'endpoint analytics
"""

import json
import time
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

def test_analytics_endpoint():
    """Teste spécifiquement l'endpoint analytics problématique"""
    
    print("🔍 DIAGNOSTIC DE L'ENDPOINT ANALYTICS")
    print("=" * 50)
    
    base_url = "https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net"
    analytics_url = f"{base_url}/api/analytics"
    
    print(f"📡 URL testée: {analytics_url}")
    print()
    
    try:
        # Faire la requête avec plus de détails
        req = Request(analytics_url, headers={
            'User-Agent': 'DiagnosticScript/1.0',
            'Accept': 'application/json'
        })
        
        print("⏳ Envoi de la requête...")
        start_time = time.time()
        
        with urlopen(req, timeout=60) as response:
            end_time = time.time()
            response_time = end_time - start_time
            
            status_code = response.getcode()
            content = response.read().decode('utf-8')
            
            print(f"✅ Réponse reçue")
            print(f"📊 Status Code: {status_code}")
            print(f"⏱️ Temps de réponse: {response_time:.2f}s")
            print(f"📏 Taille: {len(content)} bytes")
            print()
            
            # Parser le JSON pour plus de détails
            try:
                data = json.loads(content)
                print("📋 Contenu JSON:")
                print(json.dumps(data, indent=2))
            except json.JSONDecodeError:
                print("📄 Contenu brut (non-JSON):")
                print(content)
            
            return True
            
    except HTTPError as e:
        print(f"❌ Erreur HTTP: {e.code} - {e.reason}")
        
        # Lire le contenu de l'erreur pour plus de détails
        try:
            error_content = e.read().decode('utf-8')
            print("📄 Contenu de l'erreur:")
            
            try:
                error_data = json.loads(error_content)
                print(json.dumps(error_data, indent=2))
                
                # Analyser l'erreur spécifique
                if "message" in error_data:
                    message = error_data["message"]
                    print()
                    print("🔍 ANALYSE DE L'ERREUR:")
                    
                    if "No working database driver" in message:
                        print("❌ PROBLÈME IDENTIFIÉ: Driver de base de données manquant")
                        print()
                        print("💡 SOLUTIONS POSSIBLES:")
                        print("1. 🔧 Les packages pyodbc/pymssql ne sont pas installés")
                        print("2. 🔧 Les drivers ODBC ne sont pas disponibles dans Azure")
                        print("3. 🔧 Problème de configuration de l'environnement Azure")
                        print()
                        print("📋 ÉTAPES DE CORRECTION:")
                        print("• Vérifier requirements.txt contient pyodbc>=4.0.34")
                        print("• Redéployer la Function App")
                        print("• Vérifier les logs Azure Function pour plus de détails")
                        
                    elif "connection" in message.lower():
                        print("❌ PROBLÈME IDENTIFIÉ: Problème de connexion à la base de données")
                        print()
                        print("💡 SOLUTIONS POSSIBLES:")
                        print("1. 🔧 String de connexion incorrecte")
                        print("2. 🔧 Règles de firewall Azure SQL")
                        print("3. 🔧 Credentials invalides")
                        
                    else:
                        print(f"❌ ERREUR INCONNUE: {message}")
                        
            except json.JSONDecodeError:
                print(error_content)
                
        except:
            print("❌ Impossible de lire le contenu de l'erreur")
        
        return False
        
    except URLError as e:
        print(f"❌ Erreur URL: {e.reason}")
        return False
        
    except Exception as e:
        print(f"❌ Erreur inattendue: {str(e)}")
        return False

def test_other_endpoints_for_comparison():
    """Teste d'autres endpoints pour comparaison"""
    
    print("\n" + "=" * 50)
    print("🔍 TEST DES AUTRES ENDPOINTS (COMPARAISON)")
    print("=" * 50)
    
    base_url = "https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net"
    
    endpoints = [
        ("Health", f"{base_url}/api/health"),
        ("PowerBI Stations", f"{base_url}/api/powerbi-data?type=stations")
    ]
    
    for name, url in endpoints:
        print(f"\n🧪 Test: {name}")
        try:
            req = Request(url, headers={'User-Agent': 'DiagnosticScript/1.0'})
            with urlopen(req, timeout=30) as response:
                status_code = response.getcode()
                print(f"  ✅ Status: {status_code} - Fonctionne")
        except Exception as e:
            print(f"  ❌ Erreur: {str(e)}")

def check_requirements_file():
    """Vérifie le fichier requirements.txt"""
    
    print("\n" + "=" * 50)
    print("🔍 VÉRIFICATION DU FICHIER REQUIREMENTS.TXT")
    print("=" * 50)
    
    try:
        with open('../azure_function/requirements.txt', 'r') as f:
            requirements = f.read()
            
        print("📄 Contenu du requirements.txt:")
        print(requirements)
        print()
        
        # Vérifier les drivers spécifiques
        if 'pyodbc' in requirements:
            print("✅ pyodbc trouvé dans requirements.txt")
        else:
            print("❌ pyodbc MANQUANT dans requirements.txt")
            
        if 'pymssql' in requirements:
            print("✅ pymssql trouvé dans requirements.txt")
        else:
            print("❌ pymssql MANQUANT dans requirements.txt")
            
    except FileNotFoundError:
        print("❌ Fichier requirements.txt non trouvé")
    except Exception as e:
        print(f"❌ Erreur lecture requirements.txt: {e}")

def main():
    """Fonction principale de diagnostic"""
    
    print("🔍 DIAGNOSTIC COMPLET DE L'ERREUR 500")
    print("🕐 Début du diagnostic:", time.strftime("%Y-%m-%d %H:%M:%S"))
    
    # 1. Tester l'endpoint analytics problématique
    analytics_ok = test_analytics_endpoint()
    
    # 2. Tester d'autres endpoints pour comparaison
    test_other_endpoints_for_comparison()
    
    # 3. Vérifier les requirements
    check_requirements_file()
    
    # 4. Résumé et recommandations
    print("\n" + "=" * 50)
    print("📊 RÉSUMÉ DU DIAGNOSTIC")
    print("=" * 50)
    
    if not analytics_ok:
        print("❌ L'endpoint /api/analytics a un problème")
        print()
        print("🔧 ACTIONS RECOMMANDÉES:")
        print("1. Vérifier les logs Azure Function App dans le portail Azure")
        print("2. S'assurer que pyodbc et pymssql sont dans requirements.txt")
        print("3. Redéployer la Function App")
        print("4. Vérifier la configuration SQL_CONNECTION_STRING")
        print("5. Tester la connectivité à Azure SQL Database")
        print()
        print("🌐 Logs Azure à consulter:")
        print("• Portal Azure → Function App → Monitoring → Logs")
        print("• Application Insights → Logs")
        print("• Rechercher 'database driver' dans les logs")
    else:
        print("✅ L'endpoint /api/analytics fonctionne correctement")
    
    print(f"\n🕐 Fin du diagnostic: {time.strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⏹️ Diagnostic interrompu par l'utilisateur")
    except Exception as e:
        print(f"\n❌ Erreur durant le diagnostic: {e}")
    
    # Attendre une entrée avant de fermer
    try:
        input("\n🔑 Appuyez sur Entrée pour continuer...")
    except:
        pass
