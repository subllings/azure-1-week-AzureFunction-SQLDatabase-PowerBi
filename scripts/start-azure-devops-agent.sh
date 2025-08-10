#!/bin/bash

# ===================================================================
# Azure DevOps Self-Hosted Agent Startup Script (Bash Version)
# ===================================================================
# This script starts the Azure DevOps self-hosted agent for CI/CD pipelines
# 
# Prerequisites:
# - Agent installed in /home/azagent or C:\azagent (Windows)
# - Personal Access Token configured during agent setup
# - Docker installed and running
#
# Usage: 
#   ./start-azure-devops-agent.sh
#   ./start-azure-devops-agent.sh --service
# ===================================================================

set -e  # Exit on any error

echo ""
echo "========================================"
echo "Azure DevOps Agent Startup"
echo "========================================"
echo ""

# Configuration
AGENT_PATH_LINUX="/home/azagent"
AGENT_PATH_WINDOWS="C:/azagent"
AGENT_NAME="iRail-Dev-Agent"

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    AGENT_PATH="$AGENT_PATH_WINDOWS"
    SCRIPT_EXT=".cmd"
else
    AGENT_PATH="$AGENT_PATH_LINUX"
    SCRIPT_EXT=".sh"
fi

echo "Detected OS: $OSTYPE"
echo "Agent Path: $AGENT_PATH"

# Check if agent directory exists
if [ ! -d "$AGENT_PATH" ]; then
    echo "ERROR: Agent directory not found at $AGENT_PATH"
    echo ""
    echo "Please ensure the Azure DevOps agent is installed."
    echo "Download from: https://dev.azure.com/bouman9YvesSchillings/irail-functions-cicd/_settings/agentpools"
    echo ""
    exit 1
fi

# Check if Docker is running
echo "Checking Docker status..."
if ! docker version &> /dev/null; then
    echo "WARNING: Docker is not running or not installed"
    echo "Please start Docker before continuing"
    echo ""
    read -p "Press Enter to continue anyway..."
fi

# Change to agent directory
cd "$AGENT_PATH"

# Check command line argument
if [ "$1" == "--service" ] || [ "$1" == "--install-service" ]; then
    echo "Installing Azure DevOps agent as service..."
    echo ""
    
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows service installation
        ./config.cmd --unattended --runAsService
    else
        # Linux service installation
        sudo ./svc.sh install
        sudo ./svc.sh start
    fi
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "SUCCESS: Agent installed as service"
        echo "The agent will start automatically on boot"
        echo ""
    else
        echo ""
        echo "ERROR: Failed to install agent as service"
        echo "Please check the configuration and try again"
        echo ""
        exit 1
    fi
else
    # Run agent interactively
    echo "Starting Azure DevOps agent interactively..."
    echo "Agent Path: $AGENT_PATH"
    echo "Agent Name: $AGENT_NAME"
    echo ""
    echo "Press Ctrl+C to stop the agent"
    echo ""
    
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        ./run.cmd
    else
        ./run.sh
    fi
fi

echo ""
echo "Agent startup script completed"
