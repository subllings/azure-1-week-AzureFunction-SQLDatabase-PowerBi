#!/bin/bash

# ==========================================================
# USAGE :
# cd /e/_SoftEng/_BeCode/azure-1-week-AzureFunction-SQLDatabase-PowerBi
# chmod +x setup-pip-env.sh
# ./setup-pip-env.sh
# ==========================================================

clear

# === Configuration ===
VENV_DIR=".venv"
REQUIREMENTS_FILE="requirements.txt"

# Check if Python 3.12 is available
if ! py -3.12 --version &> /dev/null; then
    echo "Python 3.12.10 is not available via 'py -3.12'"
    echo "Install it or verify your Python Launcher (py) setup."
    exit 1
fi

# Delete previous virtual environment if it exists
if [ -d "$VENV_DIR" ]; then
    echo "Removing existing virtual environment: $VENV_DIR"
    rm -rf "$VENV_DIR"
fi

# Create new virtual environment
echo "Creating new virtual environment with Python 3.12.10..."
py -3.12 -m venv "$VENV_DIR"

# Activate environment
source "$VENV_DIR/Scripts/activate"

# Upgrade pip
python -m pip install --upgrade pip

# Install dependencies
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "Installing dependencies from $REQUIREMENTS_FILE..."
    python -m pip install -r "$REQUIREMENTS_FILE"
    echo "Dependencies installed."
else
    echo "Could not find $REQUIREMENTS_FILE at project root."
    exit 1
fi

# Final message
echo ""
echo "Virtual environment ready: $VENV_DIR"
echo "To activate it later: source $VENV_DIR/Scripts/activate"
