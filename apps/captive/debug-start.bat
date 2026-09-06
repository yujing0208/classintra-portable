@echo off
title Hotspot HTTPS Redirect Service
echo.
echo ================================================
echo   Hotspot HTTPS Redirect - STARTUP
echo ================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Need Administrator!
    pause
    exit /b 1
)

set "DIR=%~dp0"

echo Step 1: Check port 53...
powershell -NoProfile -Command "if (Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if %errorlevel% equ 0 (
    echo   [INFO] Port 53 is in use (Windows hotspot DNS service)
) else (
    echo   [OK] Port 53 is free
)

echo.
echo Step 2: Start hotspot...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%start-hotspot.ps1" -Verbose
echo   Done (exit code: %errorlevel%).

echo.
echo Step 3: Firewall...
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
netsh advfirewall firewall add rule name="Hotspot DNS Redirect" dir=in action=allow protocol=UDP localport=53 remoteip=192.168.137.0/24 >nul 2>&1
netsh advfirewall firewall add rule name="Hotspot HTTPS Redirect" dir=in action=allow protocol=TCP localport=443 remoteip=192.168.137.0/24 >nul 2>&1
echo   Done.

echo.
echo Step 4: Starting Node.js...
echo   Press Ctrl+C to stop
echo ------------------------------------------------
echo.

node "%DIR%hotspot-redirect.js"

echo.
echo ================================================
echo   Node exited. Cleaning up...
echo ================================================
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
sc start SharedAccess >nul 2>&1
echo   Cleanup done.
pause
