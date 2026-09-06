@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Hotspot HTTPS Redirect - Startup Script
::   Interactive : start-hotspot-redirect.bat
::   Silent      : start-hotspot-redirect.bat --silent
:: ============================================================

:: ---- Portable node PATH adapter ----
:: When running from the ClassIntraPortable USB package (watchdog /
:: scheduled task context has no system node), prepend the bundled
:: portable node so the bare `node` command below resolves.
if exist "%~dp0..\..\runtime\node\node.exe" (
    set "PATH=%~dp0..\..\runtime\node;%PATH%"
)

if /i "%~1"=="--silent" goto :Silent

:: A manual start re-enables the watchdog after a previous stop
if exist "%~dp0watchdog.stop" del "%~dp0watchdog.stop" >nul 2>&1

:: ============================================================
:: INTERACTIVE MODE (visible console window)
:: ============================================================
title Hotspot HTTPS Redirect Service

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script requires Administrator privileges!
    echo         Right-click this file -^> "Run as administrator"
    pause
    exit /b 1
)

set "DIR=%~dp0"

echo.
echo ================================================
echo   Hotspot HTTPS Redirect - Startup Script
echo ================================================
echo.

call :DoWork

pause
exit /b %errorlevel%

:: ============================================================
:: SILENT MODE (log to file, no console window)
:: ============================================================
:Silent

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Administrator privileges are required.>>"%~dp0logs\service.log"
    exit /b 1
)

set "DIR=%~dp0"

if not exist "%DIR%logs" mkdir "%DIR%logs"
set "LOG=%DIR%logs\service.log"

echo. >> "%LOG%"
echo ============================================= >> "%LOG%"
echo [%date% %time%] Service starting (silent) >> "%LOG%"
echo ============================================= >> "%LOG%"

call :DoWork >> "%LOG%" 2>&1

exit /b %errorlevel%

:: ============================================================
:: CORE LOGIC
:: ============================================================
:DoWork

echo [1/4] Preparing hotspot and DNS port 53...
echo.

sc query SharedAccess | findstr /i "RUNNING" >nul 2>&1
if %errorlevel% equ 0 echo   [INFO] Windows hotspot service is running.

echo.
echo [2/4] Starting mobile hotspot...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%start-hotspot.ps1" -Verbose
if %errorlevel% equ 0 (
    echo   [OK] Mobile hotspot is ready
) else (
    echo   [ERROR] Failed to start mobile hotspot. Proxy will not start.
    sc start SharedAccess >nul 2>&1
    exit /b 1
)

:: SharedAccess may own UDP 53. Stop it only after the hotspot is ON.
echo.
echo   Releasing UDP port 53 after hotspot startup...
sc stop SharedAccess >nul 2>&1
for /l %%i in (1,1,15) do (
    powershell -NoProfile -Command "if (Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue) { exit 1 } else { exit 0 }" >nul 2>&1
    if not errorlevel 1 goto :Port53Ready
    powershell -NoProfile -Command "Start-Sleep -Seconds 1"
)
echo   [ERROR] UDP port 53 could not be released. Please stop SharedAccess manually.
exit /b 1

:Port53Ready
echo   [OK] UDP port 53 released.

echo.
echo [3/4] Configuring firewall...
echo.

netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
netsh advfirewall firewall add rule name="Hotspot DNS Redirect" dir=in action=allow protocol=UDP localport=53 remoteip=192.168.137.0/24 >nul 2>&1
netsh advfirewall firewall add rule name="Hotspot HTTPS Redirect" dir=in action=allow protocol=TCP localport=443 remoteip=192.168.137.0/24 >nul 2>&1
echo   [OK] Firewall rules configured

echo.
echo [4/4] Starting DNS + HTTPS redirect service...
echo.
echo   Press Ctrl+C to stop
echo ------------------------------------------------
echo.

node "%DIR%hotspot-redirect.js"

:: --------------------------------------------------
:: Cleanup (runs after service exits)
:: --------------------------------------------------
echo.
echo Cleaning up...
echo.

netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
echo   [OK] Firewall rules removed

echo.
echo Service stopped.
goto :EOF
