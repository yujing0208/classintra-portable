@echo off
title Uninstall Auto-Start - Hotspot Redirect
echo.
echo ================================================
echo   Uninstall Auto-Start - Hotspot HTTPS Redirect
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

set "SCRIPT_DIR=%~dp0"
set TASK_NAME=IR_Hotspot_Redirect

:: Tell the watchdog to stop before removing the scheduled task
echo stop>"%SCRIPT_DIR%watchdog.stop"

echo [1/3] Stopping any running service...
echo.

:: Find and kill node process running hotspot-redirect.js
set "KILLED="
for /f "tokens=2 delims==" %%a in ('wmic process where "commandline like '%%hotspot-redirect.js%%' and name='node.exe'" get processid /value 2^>nul') do (
    set "PID=%%a"
    if not "!PID!"=="" (
        set "PID=!PID: =!"
        if not "!PID!"=="" (
            echo   Stopping node.exe PID !PID!...
            taskkill /f /pid !PID! >nul 2>&1
            powershell.exe -NoProfile -Command "Start-Sleep -Seconds 1"
            set "KILLED=1"
        )
    )
)
if defined KILLED (echo   [OK] Service process stopped) else (echo   [INFO] No running service found)

echo.
echo [2/3] Deleting scheduled task...
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1
schtasks /delete /tn "IR_Hotspot_Redirect_Recovery" /f >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK] Task "%TASK_NAME%" deleted
) else (
    echo   [INFO] Task "%TASK_NAME%" not found
)

echo.
echo [3/3] Cleaning firewall rules...
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
echo   [OK] Firewall rules removed

echo.
echo ================================================
echo   Uninstall complete!
echo ================================================
echo.
echo   Auto-start and firewall rules have been removed.
echo.
pause
