@echo off
setlocal

set "DIR=%~dp0"
set "STOP_FLAG=%DIR%watchdog.stop"

:RunWatchdog
if exist "%STOP_FLAG%" exit /b 0

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DIR%watchdog.ps1"

if exist "%STOP_FLAG%" exit /b 0

:: Restart the watchdog itself if PowerShell exits unexpectedly.
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 5"
goto :RunWatchdog
