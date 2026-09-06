@echo off
setlocal
cd /d "%~dp0"

rem ---- 提权（停止守护节点需要管理员）----
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限，正在请求提升...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "APP=%ROOT%apps\ClassIntra"
set "CAPTIVE=%ROOT%apps\captive"
set "PM2=%APP%\server\node_modules\pm2\bin\pm2"
set "PM2_HOME=%ROOT%runtime\pm2-home"

echo ============================================================
echo   安全退出（弹出 U 盘前必做）
echo   停止 ClassIntra + captive 全部后台服务，避免文件占用
echo ============================================================
echo.

rem ---- 1. 前台窗口模式的 ClassIntra 服务器（2-启动方式）----
echo [1/6] 停止前台 ClassIntra 窗口...
taskkill /FI "WINDOWTITLE eq ClassIntra Server*" /T /F >nul 2>&1
echo       [OK]

rem ---- 2. PM2 守护模式 ----
echo [2/6] 停止 PM2 托管进程...
if exist "%PM2%" (
  "%NODE%" "%PM2%" kill >nul 2>&1
  echo       [OK] PM2 已退出
) else (
  echo       [提示] 未使用 PM2 守护，跳过。
)

rem ---- 3. captive 守护（watchdog + 计划任务）----
echo [3/6] 通知 captive watchdog 停止...
echo stop>"%CAPTIVE%\watchdog.stop"
schtasks /end /tn "IR_Hotspot_Redirect" >nul 2>&1
schtasks /end /tn "IR_Hotspot_Redirect_Recovery" >nul 2>&1
echo       [OK]

rem ---- 4. 停止 captive 劫持进程 ----
echo [4/6] 停止 hotspot-redirect.js 进程...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { $_.CommandLine -like '*hotspot-redirect.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo       [OK]

rem ---- 5. 清理防火墙 + 锁文件 ----
echo [5/6] 清理防火墙规则与锁文件...
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
if exist "%CAPTIVE%\watchdog.lock" del "%CAPTIVE%\watchdog.lock" >nul 2>&1
echo       [OK]

rem ---- 6. 兜底：清理本便携包 node 启动的残留监听 ----
echo [6/6] 兜底清理残留端口监听...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":9001 " ^| findstr "LISTENING"') do (
  taskkill /PID %%a /F >nul 2>&1
)
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":53 " ^| findstr "LISTENING"') do (
  taskkill /PID %%a /F >nul 2>&1
)
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":443 " ^| findstr "LISTENING"') do (
  taskkill /PID %%a /F >nul 2>&1
)
timeout /t 1 /nobreak >nul
echo       [OK]

echo.
echo ============================================================
echo   全部服务已停止。现在可以安全弹出 U 盘。
echo ============================================================
echo.
pause
