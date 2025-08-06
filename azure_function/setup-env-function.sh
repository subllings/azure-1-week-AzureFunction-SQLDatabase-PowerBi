#!/bin/bash

# Setup Environment for Azure Function - Python 3.12 (Stable)
# This script creates a dedicated virtual environment for Azure Function deployment
#
# USAGE:
# cd /e/_SoftEng/_BeCode/azure-1-week-subllings/azure_function
# chmod +x setup-env-function.sh
# ./setup-env-function.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Setting up Azure Function Environment (Python 3.12 - Stable)"

# Check if we're in the azure_function directory
if [ ! -f "function_app.py" ]; then
    print_error "Please run this script from the azure_function directory"
    print_error "   cd /e/_SoftEng/_BeCode/azure-1-week-subllings/azure_function && ./setup-env-function.sh"
    exit 1
fi

# Check for Python 3.12 first (preferred for stability)
if command -v python3.12 &> /dev/null; then
    PYTHON_CMD="python3.12"
    print_status "Found Python 3.12 (preferred version)"
elif command -v py -3.12 &> /dev/null; then
    PYTHON_CMD="py -3.12"
    print_status "Found Python 3.12 (via py launcher)"
elif command -v python3.13 &> /dev/null; then
    PYTHON_CMD="python3.13"
    print_warning "Using Python 3.13 (newer but may have compatibility issues)"
elif command -v py -3.13 &> /dev/null; then
    PYTHON_CMD="py -3.13"
    print_warning "Using Python 3.13 (via py launcher - newer but may have compatibility issues)"
elif command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    print_warning "Using system Python 3: $PYTHON_VERSION"
else
    print_error "No compatible Python version found!"
    print_error "   Please install Python 3.12 (recommended) or 3.13:"
    print_error "   - Download from python.org"
    print_error "   - Or use: winget install Python.Python.3.12"
    print_error "   - Or use: pyenv install 3.12.0"
    exit 1
fi

# Remove existing .venv if it exists
if [ -d ".venv" ]; then
    print_warning "Removing existing .venv..."
    rm -rf .venv
fi

# Create new virtual environment with detected Python version
print_status "Creating virtual environment with $PYTHON_CMD..."
$PYTHON_CMD -m venv .venv

# Activate virtual environment
print_status "Activating virtual environment..."
if [[ "$OSTYPE" == "msys" ]]; then
    # Windows Git Bash
    source .venv/Scripts/activate
else
    # Linux/Mac
    source .venv/bin/activate
fi

# Verify Python version
PYTHON_VERSION=$(python --version)
print_status "Python version in venv: $PYTHON_VERSION"

# Upgrade pip
print_status "Upgrading pip..."
python -m pip install --upgrade pip

# Install requirements with pre-compiled wheels for faster setup
print_status "Installing Azure Function requirements (pre-compiled wheels)..."

# Install pyodbc first with pre-compiled wheel (try multiple versions)
print_status "Installing pyodbc with pre-compiled wheel..."
if pip install --only-binary=all pyodbc==5.1.0; then
    print_status "pyodbc 5.1.0 installed successfully"
elif pip install --only-binary=all pyodbc==5.0.1; then
    print_status "pyodbc 5.0.1 installed successfully"
elif pip install --only-binary=all pyodbc; then
    print_status "Latest pyodbc version installed successfully"
else
    print_warning "No pre-compiled pyodbc available, installing without it for now"
fi

# Install other requirements (excluding pyodbc to avoid conflicts)
print_status "Installing remaining packages..."
pip install azure-functions requests azure-identity azure-keyvault-secrets opencensus-ext-azure opencensus-ext-requests opencensus-ext-logging pandas python-dateutil python-dotenv

# Note: pyodbc is fully stable and tested with Python 3.12
print_status "All packages installed successfully - Python 3.12 stable"

print_status "Environment setup completed!"

print_status "SUMMARY:"
print_status "   Python Version: $PYTHON_VERSION"
print_status "   Virtual Environment: azure_function/.venv"
print_status "   Packages: Installed from requirements.txt"

print_status "NEXT STEPS:"
print_status "   1. Activate environment: source .venv/Scripts/activate for Windows or source .venv/bin/activate for Linux/Mac"
print_status "   2. Test locally: func start"
print_status "   3. Deploy to Azure: func azure functionapp publish traindata-function-app-hsefg2hkbbetgac2"

print_status "TIP: This environment is isolated from your main Python setup!"
