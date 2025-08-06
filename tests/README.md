# 🧪 Guide des Tests API Azure Function

## Vue d'ensemble

Ce dossier contient une suite complète de tests pour valider tous les endpoints de votre API Azure Function. Trois niveaux de tests sont disponibles :

1. **Tests Rapides** - Tests simples sans dépendances
2. **Tests Unitaires** - Tests avec mocks pour la logique métier
3. **Tests d'Intégration** - Tests avec les vrais endpoints déployés

## 🚀 Exécution Rapide (Recommandée)

### Option 1: Script Python Simple
```bash
cd tests
python quick_test.py
```

### Option 2: Script Batch Windows
```bash
cd tests
run_tests.bat
```

### Option 3: Test complet avec rapport
```bash
cd tests
python run_tests.py
```

## 📋 Endpoints Testés

| Endpoint | Description | Test Inclus |
|----------|-------------|-------------|
| `/api/health` | Vérification de l'état de l'API | ✅ |
| `/api/analytics` | Données analytiques globales | ✅ |
| `/api/powerbi-data?type=stations` | Liste des stations pour Power BI | ✅ |
| `/api/powerbi-data?type=departures` | Données des départs pour Power BI | ✅ |
| `/api/powerbi-data?type=delays` | Données des retards pour Power BI | ✅ |
| `/api/liveboard?station=X` | Tableau des départs par station | ✅ |
| `/api/data-refresh` | Rafraîchissement manuel des données | ✅ |

## 🔧 Configuration des Tests

### URL de Base
```
https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net
```

### Timeouts
- Tests rapides: 30 secondes par endpoint
- Tests d'intégration: 60 secondes pour les endpoints complexes

## 📊 Types de Tests

### 1. Tests Fonctionnels
- ✅ Statut HTTP 200 pour les endpoints valides
- ✅ Structure JSON correcte dans les réponses
- ✅ Présence des champs obligatoires
- ✅ Types de données appropriés

### 2. Tests de Validation
- ❌ Statut HTTP 400 pour les paramètres invalides
- ❌ Messages d'erreur appropriés
- ❌ Gestion des paramètres manquants

### 3. Tests de Performance
- ⏱️ Temps de réponse < 30 secondes
- 📏 Taille des réponses raisonnable
- 🔄 Gestion des timeouts

## 🔍 Résultats Attendus

### Endpoint Health (`/api/health`)
```json
{
  "status": "healthy",
  "service": "Azure Train Data API",
  "timestamp": "2025-08-04T...",
  "version": "1.0.0"
}
```

### Endpoint PowerBI Stations
```json
{
  "status": "success",
  "data": [...],
  "count": 156,
  "note": "Belgian railway stations"
}
```

### Endpoint Analytics
```json
{
  "total_departures": 1500,
  "unique_stations": 25,
  "avg_delay_minutes": 3.5,
  "on_time_percentage": 85.2
}
```

## 🛠️ Prérequis

### Minimum (Tests Rapides)
- Python 3.7+
- Connexion Internet
- Aucune dépendance externe

### Complet (Tous les Tests)
```bash
pip install -r test_requirements.txt
```

**Dépendances:**
- `requests` - Requêtes HTTP
- `pytest` - Framework de tests
- `azure-functions` - SDK Azure Functions
- `mock` - Tests avec mocks

## 📖 Utilisation Détaillée

### Test Rapide Sans Installation
```bash
# Aller dans le dossier tests
cd tests

# Exécuter le test simple (aucune dépendance requise)
python quick_test.py
```

**Sortie attendue:**
```
🚀 TESTS RAPIDES DES ENDPOINTS API
========================================
🧪 Test: Health Check
📡 URL: https://traindata-function-app-hsefg2hkbbetgac2.francecentral-01.azurewebsites.net/api/health
  ✅ Statut: 200
  ⏱️ Temps: 0.85s
  📏 Taille: 156 bytes
  📊 Clés JSON: ['status', 'service', 'timestamp', 'version']
  ✅ TEST RÉUSSI

...

🎯 Score: 6/6 tests réussis (100.0%)
🎉 TOUS LES TESTS ONT RÉUSSI!
```

### Tests Complets avec Pytest
```bash
# Installer les dépendances
pip install -r test_requirements.txt

# Exécuter tous les tests
python run_tests.py

# Ou utiliser pytest directement
pytest test_endpoints.py -v
pytest test_integration.py -v
```

## 🐛 Diagnostic des Problèmes

### Tests Échouent avec Timeout
- **Cause**: Fonction Azure en mode "cold start"
- **Solution**: Réessayer après quelques minutes

### Erreur 500 sur les Endpoints
- **Cause**: Problème de base de données ou configuration
- **Solution**: Vérifier les logs Azure Function App

### Erreur 400 sur PowerBI Endpoints
- **Cause**: Paramètre `type` invalide ou manquant
- **Solution**: Utiliser `type=stations|departures|delays`

### Import Errors dans les Tests Unitaires
- **Cause**: Dépendances manquantes
- **Solution**: `pip install -r test_requirements.txt`

## 📈 Métriques de Performance

### Temps de Réponse Acceptables
- Health: < 5 secondes
- Analytics: < 15 secondes  
- PowerBI Endpoints: < 30 secondes
- Liveboard: < 45 secondes

### Tailles de Réponse Typiques
- Health: ~150 bytes
- Stations: ~15KB (156 stations)
- Departures: Variable selon les données
- Analytics: ~500 bytes

## 🔄 Intégration Continue

### GitHub Actions
Les tests sont intégrés dans le pipeline CI/CD :
```yaml
- name: Run API Tests
  run: |
    cd tests
    python quick_test.py
```

### Surveillance Continue
- Tests automatiques après chaque déploiement
- Alertes en cas d'échec des tests de santé
- Métriques de performance trackées

## 📝 Rapports de Tests

### Rapport Automatique
Le script `run_tests.py` génère automatiquement un rapport :
```
test_report_2025-08-04_14-30-15.md
```

### Contenu du Rapport
- Résumé des tests exécutés
- Endpoints testés avec statuts
- Métriques de performance
- Recommandations d'amélioration

## 🚀 Prochaines Étapes

1. **Exécuter le test rapide** pour vérifier le fonctionnement
2. **Installer les dépendances** pour les tests complets
3. **Intégrer dans votre workflow** de développement
4. **Configurer la surveillance** continue
5. **Ajouter des tests personnalisés** selon vos besoins

## 💡 Conseils

- **Commencez par `quick_test.py`** - Aucune installation requise
- **Utilisez `run_tests.bat`** sur Windows pour plus de simplicité
- **Consultez les logs Azure** en cas de problème persistant
- **Testez après chaque modification** du code Azure Function

---

**✅ Vos endpoints sont maintenant entièrement testés et validés !**
