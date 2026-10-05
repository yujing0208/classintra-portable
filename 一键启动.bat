@echo off
setlocal enabledelayedexpansion
title ClassIntra + Captive

:: ============================================================
::  ClassIntra + Captive - combined one-click launcher
::
::  Order:
::    [1] release any running hotspot (frees UDP 53)
::    [2] start ClassIntra, wait until the process shows up
::    [3] prepare captive (firewall)
::    [4] start captive HERE (it binds UDP 53 first), the hotspot
::        then comes up automatically in the background
::
::  Why the hotspot starts AFTER captive:
::    Windows Mobile Hotspot is powered by Internet Connection
::    Sharing (ICS).  While it is on, the ICS DNS proxy binds
::    0.0.0.0:53 - exactly the port the captive DNS hijack needs.
::    Stopping ICS to free port 53 switches the hotspot off again,
::    so the old order could never work.  Verified fix: let captive
::    bind 53 first, then start the hotspot - ICS cannot grab 53
::    but the hotspot itself still comes up.
::
::  Hotspot strategy (captive\hotspot-ctl.ps1):
::    netsh hostednetwork  -> up to 100 clients, works under SYSTEM
::    Windows Mobile Hotspot -> fallback, needs a user session
:: ============================================================

:: --------------------------- CONFIG -------------------------
set "WAIT_READY=25"
set "HOTSPOT_SSID=%COMPUTERNAME%"
set "HOTSPOT_KEY=classintr"
set "HOTSPOT_MAX=30"
set "HOTSPOT_WAIT=120"

set "ROOT=%~dp0"
set "NG=%ROOT%runtime\node_gui\node.exe"
set "NODE=%ROOT%runtime\node\node.exe"
set "NODE_PATH=%ROOT%server\node_modules"
:: console node (keeps output visible in this window); fall back to GUI node
set "CNODE=%NODE%"
if not exist "%CNODE%" set "CNODE=%NG%"
set "LOGDIR=%ROOT%logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "HCTL=%ROOT%captive\hotspot-ctl.ps1"

:: ----------------------- AUTO ELEVATION ---------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    echo Please click YES on the UAC prompt.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%ROOT%"

echo ================================================
echo   ClassIntra + Captive Launcher
echo ================================================
echo.

if not exist "%NG%" (
    echo [ERR] Missing GUI node: %NG%
    goto :end
)

:: ----------------------- DEPS / CONFIG ----------------------
if exist "%NODE%" if exist "%ROOT%tools\relink.js" "%NODE%" "%ROOT%tools\relink.js" >nul 2>&1
if not exist "%ROOT%server\.env" if exist "%ROOT%tools\make-env.js" "%NODE%" "%ROOT%tools\make-env.js" >nul 2>&1
if not exist "%ROOT%server\database" mkdir "%ROOT%server\database"
if not exist "%ROOT%server\database\classintra.db" (
    pushd "%ROOT%server"
    "%NODE%" -r dotenv/config src\utils\init-db.js >nul 2>&1
    popd
)

:: --------------- CLEAN OLD INSTANCES (targeted) -------------
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter 'Name=''node.exe''' | Where-Object { $_.CommandLine -match 'src\\app\.js|hotspot-redirect\.js' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter 'Name=''powershell.exe''' | Where-Object { $_.CommandLine -match 'watchdog\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>&1
del "%ROOT%captive\watchdog.stop" >nul 2>&1
ping -n 3 127.0.0.1 >nul

:: ============ 1) RELEASE HOTSPOT (free UDP 53) ==============
echo [1/4] Releasing any running hotspot (frees UDP 53 for captive)...
if exist "%HCTL%" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HCTL%" -Action off
) else (
    echo    [WARN] hotspot-ctl.ps1 not found - skipping
)
echo.

:: ===================== 2) CLASSINTRA ========================
echo [2/4] Starting ClassIntra...
call :count_nodes
set "BASE=%N%"
start "ClassIntra" /B /D "%ROOT%server" "%NG%" --max-old-space-size=768 src\app.js > "%LOGDIR%\classintra.log" 2>&1

set "PTRY=0"
:proc_wait
call :count_nodes
if !N! GTR %BASE% goto :proc_ok
set /a PTRY+=1
if !PTRY! geq 60 goto :proc_timeout
ping -n 2 127.0.0.1 >nul
goto :proc_wait

:proc_ok
echo    OK - ClassIntra process detected
goto :proc_done

:proc_timeout
echo    [WARN] ClassIntra process not detected in 60s - continuing anyway

:proc_done
echo    Waiting %WAIT_READY%s for initialization...
ping -n %WAIT_READY% 127.0.0.1 >nul

:: ==================== 3) CAPTIVE PREP =======================
echo.
echo [3/4] Preparing captive (release UDP 53 + firewall)...
sc stop SharedAccess >nul 2>&1
set "QT=0"
:port53_wait
powershell -NoProfile -Command "if (Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue) { exit 1 } else { exit 0 }" >nul 2>&1
if not errorlevel 1 goto :port53_ok
set /a QT+=1
if !QT! geq 15 goto :port53_ok
ping -n 2 127.0.0.1 >nul
goto :port53_wait

:port53_ok
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
netsh advfirewall firewall add rule name="Hotspot DNS Redirect" dir=in action=allow protocol=UDP localport=53 remoteip=192.168.137.0/24 >nul 2>&1
netsh advfirewall firewall add rule name="Hotspot HTTPS Redirect" dir=in action=allow protocol=TCP localport=443 remoteip=192.168.137.0/24 >nul 2>&1

if not exist "%ROOT%captive\certs\cert.pem" echo    [WARN] missing captive\certs\cert.pem - captive may fail
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) { exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 echo    [WARN] port 443 occupied (e.g. Steam++/Watt Toolkit) - captive may fail
echo    OK

:: ========== 4) WATCHDOG + ARM HOTSPOT + CAPTIVE =========
echo.
echo [4/4] Starting Captive (DNS + HTTPS redirect)...
echo    Captive binds UDP 53 first, then the hotspot starts automatically.
echo    Captive runs HERE.  Close this window (or Ctrl+C) to stop everything.
echo    Hotspot log : %LOGDIR%\hotspot.log
echo    Watchdog log: %LOGDIR%\watchdog.log
echo.
echo ================================================
echo   ClassIntra : http://localhost:9001
echo   Logs       : %LOGDIR%
echo ================================================
echo.

:: --- watchdog: keeps ClassIntra alive + re-opens the hotspot if it drops ---
if exist "%ROOT%captive\watchdog.ps1" (
    start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%captive\watchdog.ps1" -Interval 20
    echo    Watchdog   : ON   (process guard + hotspot monitor)
) else (
    echo    [WARN] watchdog.ps1 not found - no process guard
)

:: --- arm the hotspot (waits until captive owns UDP 53) ---
if exist "%HCTL%" (
    start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%HCTL%" -Action on -WaitPort 53 -WaitTimeout %HOTSPOT_WAIT% -Ssid "%HOTSPOT_SSID%" -Key "%HOTSPOT_KEY%" -MaxClient %HOTSPOT_MAX%
) else (
    echo [WARN] hotspot-ctl.ps1 not found - hotspot will NOT be started
)

:: ---------- captive: foreground loop (crashes are auto-recovered) ----------
:captive_loop
pushd "%ROOT%captive"
"%CNODE%" hotspot-redirect.js
popd
if exist "%ROOT%captive\watchdog.stop" goto :end
echo.
echo ================================================
echo   Captive exited - restarting in 5 seconds
echo   (close this window or press Ctrl+C to stop everything)
echo ================================================
ping -n 6 127.0.0.1 >nul
goto :captive_loop

:: ======================= HELPERS ============================
:count_nodes
set "N=0"
for /f %%A in ('tasklist /FI "IMAGENAME eq node.exe" /NH ^| find /c /i "node.exe"') do set "N=%%A"
exit /b

:end
endlocal
exit /b 0
