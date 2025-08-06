#!/bin/bash

# ==========================================================
# Démarrage Azure Function - Script BASH
# ==========================================================
# 
# UTILISATION RAPIDE :
# cd /mnt/e/_SoftEng/_BeCode/azure-1-week-subllings
# chmod +x start-azure-function.sh
# ./start-azure-function.sh
# 
# ==========================================================

clear

echo "Starting Azure Function Server..."
echo "Working directory: $(pwd)"

# Aller au bon répertoire (WSL path)
cd /mnt/e/_SoftEng/_BeCode/azure-1-week-subllings

# Vérifier si on est dans le bon répertoire
if [ ! -d "azure_function" ]; then
    echo " azure_function directory not found!"
    echo "Please run this script from the project root directory."
    exit 1
fi

# Naviguer vers le répertoire Azure Function
cd azure_function

echo " Changed to: $(pwd)"
echo " Files in directory:"
ls -la | head -10

# Vérifier si func est installé
if ! command -v func &> /dev/null; then
    echo " Azure Functions Core Tools not found!"
    echo "Please install: npm install -g azure-functions-core-tools@4 --unsafe-perm true"
    exit 1
fi

echo " Azure Functions Core Tools version:"
func --version

# Vérifier si le fichier function_app.py existe
if [ ! -f "function_app.py" ]; then
    echo " function_app.py not found!"
    echo "Make sure you're in the correct directory."
    exit 1
fi

# Tuer les processus func existants
echo " Cleaning up existing func processes..."
pkill -f "func start" 2>/dev/null || true
taskkill //F //IM func.exe 2>/dev/null || true

# Attendre un peu pour que les processus se ferment
sleep 2

echo "Starting Azure Function on port 7071..."
echo "Function will be available at: http://localhost:7071"
echo "Debug endpoint: http://localhost:7071/api/debug"
echo "Database preview: http://localhost:7071/api/database-preview"
echo ""
echo "Press Ctrl+C to stop the function"
echo "=================================================="

# Démarrer Azure Function
func start --port 7071

echo ""
echo "Azure Function stopped."
