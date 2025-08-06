# 🔍 Analyseur de Fichiers ZIP Azure Function

import zipfile
import os
from datetime import datetime

def analyze_zip_file(zip_path):
    """Analyse le contenu d'un fichier ZIP Azure Function"""
    
    if not os.path.exists(zip_path):
        return f"❌ Fichier non trouvé: {zip_path}"
    
    file_size = os.path.getsize(zip_path)
    file_time = datetime.fromtimestamp(os.path.getmtime(zip_path))
    
    print(f"\n📦 **{os.path.basename(zip_path)}**")
    print(f"   📅 Date: {file_time.strftime('%d/%m/%Y %H:%M:%S')}")
    print(f"   💾 Taille: {file_size:,} bytes ({file_size/1024/1024:.1f} MB)")
    
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            file_list = zip_ref.namelist()
            print(f"   📁 Fichiers: {len(file_list)}")
            
            # Analyser les types de fichiers
            file_types = {}
            important_files = []
            
            for file in file_list:
                ext = os.path.splitext(file)[1].lower()
                if ext in file_types:
                    file_types[ext] += 1
                else:
                    file_types[ext] = 1
                
                # Identifier les fichiers importants
                if any(important in file.lower() for important in 
                       ['function_app.py', 'requirements.txt', 'host.json', 'local.settings']):
                    important_files.append(file)
            
            print(f"   🔧 Types de fichiers:")
            for ext, count in sorted(file_types.items()):
                if ext:
                    print(f"      {ext}: {count}")
                else:
                    print(f"      (dossiers): {count}")
            
            print(f"   ⭐ Fichiers clés:")
            for file in important_files:
                print(f"      - {file}")
                
            # Vérifier s'il y a des endpoints PowerBI
            try:
                if 'function_app.py' in file_list:
                    content = zip_ref.read('function_app.py').decode('utf-8', errors='ignore')
                    powerbi_endpoints = []
                    
                    if 'powerbi-data' in content:
                        powerbi_endpoints.append('powerbi-data')
                    if 'analytics' in content:
                        powerbi_endpoints.append('analytics')
                    if 'liveboard' in content:
                        powerbi_endpoints.append('liveboard')
                    if 'health' in content:
                        powerbi_endpoints.append('health')
                    
                    if powerbi_endpoints:
                        print(f"   🎯 Endpoints détectés: {', '.join(powerbi_endpoints)}")
                        
                if 'requirements.txt' in file_list:
                    req_content = zip_ref.read('requirements.txt').decode('utf-8', errors='ignore')
                    packages = [line.strip() for line in req_content.split('\n') if line.strip() and not line.startswith('#')]
                    print(f"   📦 Packages: {len(packages)} dépendances")
                    key_packages = [pkg for pkg in packages if any(key in pkg.lower() for key in ['azure', 'pandas', 'requests', 'pyodbc'])]
                    if key_packages:
                        print(f"   🔑 Packages clés: {', '.join(key_packages[:3])}{'...' if len(key_packages) > 3 else ''}")
                        
            except Exception as e:
                print(f"   ⚠️ Erreur lecture contenu: {str(e)}")
                
    except Exception as e:
        print(f"   ❌ Erreur ouverture ZIP: {str(e)}")
    
    return True

def compare_zip_files():
    """Compare tous les fichiers ZIP Azure Function"""
    
    base_path = r"e:\_SoftEng\_BeCode\azure-1-week-subllings"
    
    zip_files = [
        "azure_function_powerbi.zip",
        "azure_function_powerbi_v2.zip", 
        "azure_function_v3.zip",
        "azure_function_v4.zip",
        "function-deployment-fix.zip"
    ]
    
    print("🔍 **ANALYSE DES FICHIERS ZIP AZURE FUNCTION**")
    print("=" * 60)
    
    for zip_file in zip_files:
        zip_path = os.path.join(base_path, zip_file)
        analyze_zip_file(zip_path)
    
    print("\n📊 **HISTORIQUE ET ÉVOLUTION**")
    print("=" * 60)
    
    print("""
🕐 **Chronologie basée sur les horodatages:**

1. **azure_function_v3.zip** (12:58)
   └─ Version initiale de base
   
2. **azure_function_v4.zip** (13:50)  
   └─ Évolution avec améliorations
   
3. **azure_function_powerbi.zip** (13:58)
   └─ Version spécialement optimisée pour Power BI
   
4. **azure_function_powerbi_v2.zip** (14:05)
   └─ ⭐ AMÉLIORATION de la version Power BI
   
5. **function-deployment-fix.zip** (19:19)
   └─ Fix pour l'erreur 500 analytics (le plus récent)

🎯 **Recommandations:**
- **azure_function_powerbi_v2.zip** = Version Power BI la plus aboutie
- **function-deployment-fix.zip** = Fix le plus récent pour erreur 500
- Les autres versions = Historique de développement
""")

if __name__ == "__main__":
    compare_zip_files()
