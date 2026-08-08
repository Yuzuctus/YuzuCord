@echo off
setlocal
title RandomFavorites - Legacy launcher

set "MANAGER_SCRIPT=%~dp0scripts\RandomFavoritesManager.ps1"

if not exist "%MANAGER_SCRIPT%" (
    echo.
    echo  Impossible de demarrer l'installation.
    echo  Le fichier suivant est manquant :
    echo %MANAGER_SCRIPT%
    echo.
    echo  Cette ancienne entree est conservee pour les installations existantes.
    echo  Extrais completement le ZIP YuzuCord, puis lance
    echo  "Installer YuzuCord.cmd" depuis le dossier extrait.
    set "EXIT_CODE=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MANAGER_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

:finish
if not defined RANDOM_FAVORITES_NO_PAUSE pause
exit /b %EXIT_CODE%
