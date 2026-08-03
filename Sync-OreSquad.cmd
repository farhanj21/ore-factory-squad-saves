@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Ore Factory Squad - Save Sync
echo.
echo  Ore Factory Squad - Save Sync
echo  -----------------------------------------
echo    1. Pull latest save (before hosting)
echo    2. Push my save (after playing)
echo    3. Full sync (pull + push)
echo    4. Resolve conflict (keep newest save)
echo.
set "choice="
set /p "choice=Choose [1/2/3/4, default 3]: "
if "%choice%"=="" set "choice=3"
if "%choice%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-OreSquad.ps1" -Pull
if "%choice%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-OreSquad.ps1" -Push
if "%choice%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-OreSquad.ps1"
if "%choice%"=="4" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-OreSquad.ps1" -Resolve
echo.
pause
