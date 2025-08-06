@echo off
REM ==========================================================
REM Démarrage Azure Function - Script BAT SIMPLE
REM ==========================================================

echo Starting Azure Function...
echo PORT: 7071
echo URL: http://localhost:7071
echo.

REM Aller au bon répertoire
cd /d "e:\_SoftEng\_BeCode\azure-1-week-subllings"

REM Lancer Git Bash dans une nouvelle fenêtre avec le script
echo Opening new Git Bash window...
start "" "C:\Program Files\Git\git-bash.exe" --cd="e:\_SoftEng\_BeCode\azure-1-week-subllings" "./start-azure-function.sh"

REM Si ça ne marche pas, essayer avec wsl dans une nouvelle fenêtre
if %ERRORLEVEL% NEQ 0 (
    echo Trying with WSL in new window...
    start cmd /k "wsl bash -c 'cd /mnt/e/_SoftEng/_BeCode/azure-1-week-subllings && chmod +x start-azure-function.sh && ./start-azure-function.sh'"
)

echo Azure Function window opened!
echo Check: http://localhost:7071 in a few seconds
pause
