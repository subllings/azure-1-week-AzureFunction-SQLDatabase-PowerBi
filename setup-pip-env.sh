#!/bin/bash

# ==========================================================
# USAGE :
# cd /e/_SoftEng/_BeCode/azure-1-week-subllings
# chmod +x setup-pip-env.sh
# ./setup-pip-env.sh
# ==========================================================

clear

# === Configuration ===
VENV_DIR=".venv"
REQUIREMENTS_FILE="requirements.txt"
AZURE_FUNCTION_DIR="azure_function"

# Find Python 3.13 automatically (used by Azure Functions)
PYTHON313_PATH=""

# Try different common Python 3.13 locations
for python_cmd in "python3.13" "python3" "python"; do
    if command -v "$python_cmd" &> /dev/null; then
        version=$($python_cmd --version 2>&1 | grep -o "3\.13\.[0-9]*")
        if [[ -n "$version" ]]; then
            PYTHON313_PATH="$python_cmd"
            break
        fi
    fi
done

# If not found in PATH, try common installation directories
if [[ -z "$PYTHON313_PATH" ]]; then
    for path in "/usr/bin/python3.13" "/usr/local/bin/python3.13" "C:/Python313/python.exe" "/c/Python313/python.exe" "$HOME/.pyenv/versions/3.13.*/bin/python"; do
        if [[ -x "$path" ]]; then
            version=$($path --version 2>&1 | grep -o "3\.13\.[0-9]*")
            if [[ -n "$version" ]]; then
                PYTHON313_PATH="$path"
                break
            fi
        fi
    done
fi

# Check if we found Python 3.13
if [[ -z "$PYTHON313_PATH" ]]; then
    echo "❌ Python 3.13 not found!"
    echo "Azure Functions Core Tools requires Python 3.13"
    echo "Please install Python 3.13 and make sure it's available in PATH or in a standard location."
    echo ""
    echo "Available Python versions:"
    for cmd in "python3" "python" "python3.13" "python3.12" "python3.11"; do
        if command -v "$cmd" &> /dev/null; then
            echo "  - $cmd: $($cmd --version 2>&1)"
        fi
    done
    exit 1
fi

echo "🐍 Found Python 3.13: $($PYTHON313_PATH --version)"
echo "✅ Using Python 3.13 for both development and Azure Functions"

# Delete previous virtual environment if it exists
if [ -d "$VENV_DIR" ]; then
    echo "🗑️ Removing existing virtual environment: $VENV_DIR"
    rm -rf "$VENV_DIR"
fi

# Create new virtual environment with Python 3.13 (same as Azure Functions)
echo "📦 Creating new virtual environment with Python 3.13..."
"$PYTHON313_PATH" -m venv "$VENV_DIR"

# Activate environment
source "$VENV_DIR/Scripts/activate"

# Upgrade pip
python -m pip install --upgrade pip

# Install dependencies
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "📥 Installing dependencies from $REQUIREMENTS_FILE..."
    python -m pip install -r "$REQUIREMENTS_FILE"
    echo "✅ Dependencies installed in virtual environment."
else
    echo "❌ Could not find $REQUIREMENTS_FILE at project root."
    exit 1
fi

# Install SQL drivers directly in Python 3.13 global environment (used by Azure Functions)
echo "🔗 Installing SQL drivers in Python 3.13 global environment..."
echo "� Note: Installing in global Python 3.13 because Azure Functions uses global Python"

# First try with pre-compiled wheels
"$PYTHON313_PATH" -m pip install pyodbc pymssql --only-binary=all --upgrade 2>/dev/null || {
    echo "⚠️ Binary wheels failed, trying compilation from source..."
    
    # Try compiling from source with --no-binary
    "$PYTHON313_PATH" -m pip install pyodbc --no-binary pyodbc --upgrade 2>/dev/null || {
        echo "⚠️ pyodbc compilation from source failed, trying older binary version"
        "$PYTHON313_PATH" -m pip install pyodbc==4.0.35 --only-binary=all 2>/dev/null || {
            echo "⚠️ pyodbc installation completely failed"
        }
    }
    
    "$PYTHON313_PATH" -m pip install pymssql --no-binary pymssql --upgrade 2>/dev/null || {
        echo "⚠️ pymssql compilation from source failed, trying older binary version"
        "$PYTHON313_PATH" -m pip install pymssql==2.2.7 --only-binary=all 2>/dev/null || {
            echo "⚠️ pymssql installation failed, using alternative driver"
            # Install alternative SQL drivers
            "$PYTHON313_PATH" -m pip install SQLAlchemy pyodbc-precompiled 2>/dev/null || true
        }
    }
}

# Install additional Azure Functions dependencies in virtual environment
echo "🚀 Installing Azure Functions dependencies in virtual environment..."
python -m pip install azure-functions pandas requests azure-identity azure-keyvault-secrets python-dateutil

# Also install in global Python 3.13 for Azure Functions
echo "🚀 Installing Azure Functions dependencies in Python 3.13 global..."
"$PYTHON313_PATH" -m pip install azure-functions pandas requests azure-identity azure-keyvault-secrets python-dateutil

# Navigate to Azure Function directory and install local requirements
if [ -d "$AZURE_FUNCTION_DIR" ]; then
    cd "$AZURE_FUNCTION_DIR"
    
    # Install requirements in the Azure Function virtual environment if it exists
    if [ -f "requirements.txt" ]; then
        echo "📥 Installing Azure Function requirements..."
        if [ -d ".venv" ]; then
            source ".venv/Scripts/activate"
            python -m pip install -r requirements.txt
            deactivate
        fi
    fi
    
    # Check if local.settings.json exists and has SQL_CONNECTION_STRING
    if [ -f "local.settings.json" ]; then
        if grep -q "SQL_CONNECTION_STRING" local.settings.json; then
            echo "✅ Found SQL_CONNECTION_STRING in local.settings.json"
        else
            echo "⚠️ Warning: SQL_CONNECTION_STRING not found in local.settings.json"
            echo "Make sure to configure your database connection string."
        fi
    else
        echo "⚠️ Warning: local.settings.json not found"
        echo "Make sure to configure your Azure Function settings."
    fi
    
    cd ..
fi

# Test SQL drivers availability in Python 3.13 global environment
echo "🧪 Testing SQL drivers availability in Python 3.13 global..."
if "$PYTHON313_PATH" -c "import pyodbc; print('✅ pyodbc available')" 2>/dev/null; then
    echo "✅ pyodbc successfully installed in Python 3.13 global environment"
else
    echo "❌ pyodbc installation failed in Python 3.13 global"
fi

if "$PYTHON313_PATH" -c "import pymssql; print('✅ pymssql available')" 2>/dev/null; then
    echo "✅ pymssql successfully installed in Python 3.13 global environment"
else
    echo "❌ pymssql installation failed in Python 3.13 global"
fi

# Test SQL drivers availability in virtual environment 
echo "🧪 Testing SQL drivers availability in virtual environment..."
if python -c "import pyodbc; print('✅ pyodbc available')" 2>/dev/null; then
    echo "✅ pyodbc available in virtual environment"
else
    echo "⚠️ pyodbc not available in virtual environment (using global Python 3.13)"
fi

if python -c "import pymssql; print('✅ pymssql available')" 2>/dev/null; then
    echo "✅ pymssql available in virtual environment"
else
    echo "⚠️ pymssql not available in virtual environment (using global Python 3.13)"
fi

# Final message
echo ""
echo "🎉 Environment setup complete!"
echo "📁 Virtual environment ready: $VENV_DIR (Python 3.13)"
echo "🐍 Same Python 3.13 version used for development AND Azure Functions"
echo "🔗 SQL Connection configured for online Azure SQL Database"
echo "💾 SQL drivers: pyodbc and pymssql installed"
echo ""
echo "🚀 To start Azure Function with database connection:"
echo "   source $VENV_DIR/Scripts/activate && cd $AZURE_FUNCTION_DIR && func start --port 7072"
echo ""
echo "🧪 To test database connection:"
echo "   curl http://localhost:7072/api/debug"
echo "   curl http://localhost:7072/api/database-preview"
echo ""
echo "To activate development environment later: source $VENV_DIR/Scripts/activate"

# Optional: Start Azure Function automatically
read -p "🚀 Do you want to start the Azure Function now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Starting Azure Function on port 7072..."
    
    # Activate the virtual environment first
    source "$VENV_DIR/Scripts/activate"
    
    cd "$AZURE_FUNCTION_DIR"
    echo "📍 Current directory: $(pwd)"
    echo "🐍 Using Python: $(python --version)"
    echo "🔍 Files in directory: $(ls -la | head -5)"
    
    # Kill any existing func processes
    pkill -f "func start" 2>/dev/null || true
    taskkill //F //IM func.exe 2>/dev/null || true
    
    # Start Azure Function
    echo "⚡ Launching func start --port 7072..."
    func start --port 7072 &
    FUNC_PID=$!
    
    echo "⏳ Waiting for Azure Function to start..."
    sleep 8
    
    # Test if it's running
    if curl -s http://localhost:7072/api/health > /dev/null; then
        echo "✅ Azure Function is running on http://localhost:7072"
        echo "🔗 Health check: http://localhost:7072/api/health"
        echo "🗃️ Database preview: http://localhost:7072/api/database-preview"
        echo "🐛 Debug info: http://localhost:7072/api/debug"
        echo ""
        echo "🛑 To stop the function, use: kill $FUNC_PID"
    else
        echo "❌ Failed to start Azure Function or it's not responding"
        echo "💡 Try starting manually: cd $AZURE_FUNCTION_DIR && func start --port 7072"
    fi
fi
