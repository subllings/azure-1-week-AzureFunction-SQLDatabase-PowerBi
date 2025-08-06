@echo off
REM Deploy Staging Environment Only
REM Script pour déployer uniquement l'environnement staging (Windows)

echo 🚀 Déploiement de l'environnement STAGING uniquement
echo ==================================================

REM Check if we're in the right directory
if not exist "infrastructure\main.tf" (
    echo ❌ Erreur: Ce script doit être exécuté depuis la racine du projet
    echo 📁 Assurez-vous d'être dans le dossier azure-1-week-subllings
    exit /b 1
)

REM Check if Azure CLI is logged in
echo 🔐 Vérification de l'authentification Azure...
az account show >nul 2>&1
if errorlevel 1 (
    echo ❌ Vous n'êtes pas connecté à Azure. Exécutez: az login
    exit /b 1
)

echo ✅ Authentification Azure OK

REM Navigate to infrastructure directory
cd infrastructure

REM Check if Terraform is installed
terraform version >nul 2>&1
if errorlevel 1 (
    echo ❌ Terraform n'est pas installé. Installez-le depuis: https://www.terraform.io/downloads.html
    exit /b 1
)

echo ✅ Terraform trouvé

REM Prompt for SQL password if not set
if "%TF_VAR_sql_admin_password%"=="" (
    echo 🔑 Mot de passe SQL Admin requis pour staging:
    set /p TF_VAR_sql_admin_password="Entrez le mot de passe SQL (min 8 caractères, avec majuscules, minuscules, chiffres): "
)

REM Optionally get developer IP for SQL access
if "%TF_VAR_developer_ip%"=="" (
    echo 🌐 Voulez-vous autoriser votre IP pour l'accès direct au SQL Server?
    set /p TF_VAR_developer_ip="Entrez votre IP publique (ou appuyez sur Entrée pour ignorer): "
)

echo 🔧 Initialisation de Terraform...
terraform init
if errorlevel 1 (
    echo ❌ Erreur lors de l'initialisation
    exit /b 1
)

echo 📋 Planification du déploiement staging...
terraform plan -var-file="staging.tfvars" -out="staging.tfplan"
if errorlevel 1 (
    echo ❌ Erreur lors de la planification
    exit /b 1
)

echo 🎯 Plan de déploiement généré. Voulez-vous continuer?
set /p CONFIRM="Tapez 'oui' pour déployer staging: "

if not "%CONFIRM%"=="oui" (
    echo ❌ Déploiement annulé
    exit /b 0
)

echo 🚀 Déploiement de l'environnement staging en cours...
terraform apply "staging.tfplan"

if errorlevel 1 (
    echo ❌ Erreur lors du déploiement
    exit /b 1
)

echo ✅ =======================
echo ✅ STAGING DÉPLOYÉ AVEC SUCCÈS!
echo ✅ =======================
echo.
echo 📊 Ressources déployées:
echo   - App Service Plan: FC1 (Flex Consumption)
echo   - Azure Functions: Optimisé pour staging
echo   - SQL Database: Basic SKU
echo   - Storage: LRS
echo.
echo 💡 Prochaines étapes:
echo   1. Configurer les secrets dans Azure DevOps
echo   2. Tester les endpoints de l'API
echo   3. Vérifier la collecte de données iRail
echo.
echo 🔗 Outputs Terraform:
terraform output

pause
