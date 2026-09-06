@echo off
setlocal
cd /d "%~dp0"

rem ============================================================
rem  停止 captive 热点劫持（兼容两种运行方式）
rem    1. 前台模式（5-captive热点劫持-启动.bat）
rem    2. 守护模式（5.2-captive守护安装.bat，watchdog 后台运行）
rem  说明：仅停止本次服务，不删除守护/开机自启（那用 5.2 的卸载）
rem ============================================================

rem ---- 提权（停止节点需要管理员）----
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限，正在请求提升...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "ROOT=%~dp0"
set "CAPTIVE=%ROOT%apps\captive"

echo ============================================================
echo   停止 captive 热点劫持服务
echo ============================================================
echo.

echo [1/4] 通知守护进程停止（若处于守护模式，避免被自动拉起）...
echo stop>"%CAPTIVE%\watchdog.stop"
schtasks /end /tn "IR_Hotspot_Redirect" >nul 2>&1
schtasks /end /tn "IR_Hotspot_Redirect_Recovery" >nul 2>&1
echo       [OK]

echo.
echo [2/4] 停止 hotspot-redirect.js 进程...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$killed=$false; Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { $_.CommandLine -like '*hotspot-redirect.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $killed=$true }; if($killed){'  [OK] 已停止' } else { '  [提示] 未发现运行中的 captive 进程' }"
echo.

echo [3/4] 清理防火墙规则...
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
echo       [OK]

echo.
echo [4/4] 清理守护锁文件...
if exist "%CAPTIVE%\watchdog.lock" del "%CAPTIVE%\watchdog.lock" >nul 2>&1
echo       [OK]

echo.
echo ============================================================
echo   已停止。如需重新开启：
echo     前台调试 : 5-captive热点劫持-启动.bat
echo     后台守护 : 5.2-captive守护安装.bat（选 1）
echo   如需彻底卸载守护与开机自启：
echo     5.2-captive守护安装.bat（选 2）
echo ============================================================
echo.
pause
