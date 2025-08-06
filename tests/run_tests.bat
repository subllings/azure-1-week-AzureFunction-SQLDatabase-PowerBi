@echo off
echo ========================================
echo 🧪 LANCEMENT DES TESTS API AZURE FUNCTION
echo ========================================
echo.

REM Vérifier si Python est installé
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Python n'est pas installé ou n'est pas dans le PATH
    echo 📥 Veuillez installer Python depuis https://python.org
    pause
    exit /b 1
)

echo ✅ Python détecté
python --version

echo.
echo 📦 Installation des dépendances pour les tests...
pip install requests pytest azure-functions

echo.
echo 🚀 Démarrage des tests...
echo.

REM Changer vers le répertoire des tests
cd /d "%~dp0"

REM Exécuter le script de test Python
python run_tests.py

echo.
echo 📊 Tests terminés!
echo.
pause
