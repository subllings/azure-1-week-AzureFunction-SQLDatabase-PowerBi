@echo off
REM ===================================================================
REM Azure DevOps Self-Hosted Agent Startup Script
REM ===================================================================
REM This script starts the Azure DevOps self-hosted agent for CI/CD pipelines
REM 
REM Prerequisites:
REM - Agent installed in C:\azagent (or update AGENT_PATH below)
REM - Personal Access Token configured during agent setup
REM - Docker Desktop installed and running
REM
REM Usage: 
REM   start-azure-devops-agent.bat
REM   start-azure-devops-agent.bat --service (to install as service)
REM ===================================================================

echo.
echo ========================================
echo Azure DevOps Agent Startup
echo ========================================
echo.

REM Configuration
set AGENT_PATH=C:\azagent
set AGENT_NAME=iRail-Dev-Agent

REM Check if agent directory exists
if not exist "%AGENT_PATH%" (
    echo ERROR: Agent directory not found at %AGENT_PATH%
    echo.
    echo Please ensure the Azure DevOps agent is installed.
    echo Download from: https://dev.azure.com/bouman9YvesSchillings/irail-functions-cicd/_settings/agentpools
    echo.
    pause
    exit /b 1
)

REM Check if Docker Desktop is running
echo Checking Docker Desktop status...
docker version >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: Docker Desktop is not running or not installed
    echo Please start Docker Desktop before continuing
    echo.
    pause
)

REM Change to agent directory
cd /d "%AGENT_PATH%"

REM Check command line argument
if "%1"=="--service" goto install_service
if "%1"=="--install-service" goto install_service

REM Run agent interactively
:run_interactive
echo Starting Azure DevOps agent interactively...
echo Agent Path: %AGENT_PATH%
echo Agent Name: %AGENT_NAME%
echo.
echo Press Ctrl+C to stop the agent
echo.
.\run.cmd
goto end

REM Install agent as Windows service
:install_service
echo Installing Azure DevOps agent as Windows service...
echo.
.\config.cmd --unattended --runAsService
if %errorlevel% equ 0 (
    echo.
    echo SUCCESS: Agent installed as Windows service
    echo The agent will start automatically when Windows boots
    echo.
) else (
    echo.
    echo ERROR: Failed to install agent as service
    echo Please check the configuration and try again
    echo.
)
goto end

:end
echo.
echo Agent startup script completed
pause
