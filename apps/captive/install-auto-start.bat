@echo off
title Install Auto-Start - Hotspot Redirect
echo.
echo ================================================
echo   Install Auto-Start - Hotspot HTTPS Redirect
echo   (Silent background mode - no visible window)
echo ================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/c','\"%~f0\"' -Verb RunAs"
    exit /b 0
)

set "DIR=%~dp0"
set TASK_NAME=IR_Hotspot_Redirect
if exist "%DIR%watchdog.stop" del "%DIR%watchdog.stop" >nul 2>&1

echo [1/3] Removing existing task (if any)...
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1
schtasks /delete /tn "IR_Hotspot_Redirect_Recovery" /f >nul 2>&1
echo   [OK] Old task cleaned up

echo.
echo [2/3] Creating scheduled task...
echo   Task name : %TASK_NAME%
echo   Launcher  : PowerShell watchdog
echo   Mode      : Silent background (no console window)
echo.

schtasks /create ^
    /tn "%TASK_NAME%" ^
    /tr "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%DIR%watchdog.ps1\"" ^
    /sc ONSTART ^
    /delay 0000:30 ^
    /rl HIGHEST ^
    /f

if %errorlevel% equ 0 (
echo   [OK] Scheduled task created
) else (
    echo   [FAIL] Failed to create scheduled task
    pause
    exit /b 1
)

echo   Configuring unlimited runtime and task-level recovery...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%configure-task-recovery.ps1" -TaskName "%TASK_NAME%" >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK] Unlimited runtime and automatic task recovery configured
) else (
    echo   [FAIL] Could not configure task recovery
    pause
    exit /b 1
)

echo.
echo [3/3] Configuring task properties...
echo.

schtasks /change ^
    /tn "%TASK_NAME%" ^
    /np ^
    >nul 2>&1

echo   [OK] Task properties configured

echo.
echo ================================================
echo   Installation complete!
echo ================================================
echo.
echo   Auto-start is now enabled (silent mode):
echo     - Triggers 30s after Windows starts
echo     - Runs as one hidden watchdog process
echo     - Auto-starts mobile hotspot
echo     - Monitors and restarts the proxy if it closes
echo     - Restarts the proxy when the hotspot goes off
echo     - Uses task-level recovery if the watchdog exits
echo     - All output logged to: logs\service.log and logs\watchdog.log
echo.
echo   To stop the service : run stop-hotspot-redirect.bat (as admin)
echo   To uninstall        : run uninstall-auto-start.bat    (as admin)
echo   To start manually   : run start-hotspot-redirect.bat (as admin)
echo.
echo   Would you like to start the service now?
choice /c YN /n /m "  Start now (Y/N)? "
if %errorlevel% equ 1 (
    echo.
    echo Starting service in background...
    schtasks /run /tn "%TASK_NAME%" >nul 2>&1
    echo Service launched. Check logs\service.log for status.
)
pause
