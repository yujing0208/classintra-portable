@echo off
setlocal enabledelayedexpansion
title Stop Hotspot Redirect Service
echo.
echo ================================================
echo   Stop Hotspot HTTPS Redirect Service
echo ================================================
echo.

:: Check admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script requires Administrator privileges!
    echo         Right-click this file -^> "Run as administrator"
    pause
    exit /b 1
)

echo [1/3] Stopping redirect service process...
echo.

:: Tell the watchdog not to restart the service while stopping it
echo stop>"%~dp0watchdog.stop"
echo   [OK] Watchdog stop signal created

schtasks /end /tn "IR_Hotspot_Redirect" >nul 2>&1
schtasks /end /tn "IR_Hotspot_Redirect_Recovery" >nul 2>&1

:: Find node.exe processes running hotspot-redirect.js
:: WMIC returns lines like "ProcessId=12345"
set "KILLED="
for /f "tokens=2 delims==" %%a in ('wmic process where "commandline like '%%hotspot-redirect.js%%' and name='node.exe'" get processid /value 2^>nul') do (
    set "PID=%%a"
    if not "!PID!"=="" (
        set "PID=!PID: =!"
        if not "!PID!"=="" (
            echo   Found node.exe PID !PID! (hotspot-redirect.js^)
            echo   Sending graceful shutdown...

            :: Graceful kill first (sends SIGTERM -> process.on('SIGTERM') handler)
            taskkill /pid !PID! >nul 2>&1
            if !errorlevel! neq 0 (
                :: Force kill if graceful fails
                echo   Graceful shutdown failed, force killing...
                taskkill /f /pid !PID! >nul 2>&1
            )

            :: Wait a moment for process to exit
            powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"

            :: Verify it's gone
            tasklist /fi "pid eq !PID!" 2>nul | findstr "!PID!" >nul 2>&1
            if !errorlevel! neq 0 (
                echo   [OK] Process PID !PID! stopped
            ) else (
                echo   [WARN] Process PID !PID! may still be running
            )
            set "KILLED=1"
        )
    )
)

if not defined KILLED (
    echo   [INFO] No running hotspot-redirect.js process found
)

:: Remove stale PID file if exists
if exist "%~dp0service.pid" (
    del "%~dp0service.pid" 2>nul
)

echo.
echo [2/3] Cleaning firewall rules...
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
echo   [OK] Firewall rules removed

echo.
echo [3/3] Cleaning up watchdog lock...
del "%~dp0watchdog.lock" 2>nul
echo   [OK] Done

echo.
echo ================================================
echo   Service stopped.
echo ================================================
echo.
echo   To restart: run start-hotspot-redirect.bat (as admin)
echo   To re-enable auto-start: already installed,
echo       will auto-start on next system boot.
echo.
pause
