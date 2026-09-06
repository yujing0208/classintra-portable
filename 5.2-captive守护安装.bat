@echo off
setlocal
cd /d "%~dp0"

rem ============================================================
rem  captive 无窗口守护 - 安装 / 卸载（管理员）
rem  安装后 captive 以"后台守护"方式运行：
rem    - 无任何黑色窗口、任务栏不显示
rem    - 崩溃自动拉起（watchdog 每 15 秒健康检查）
rem    - 开机 30 秒后自动启动（计划任务，最高权限）
rem    - 日志写入 apps\captive\logs\service.log
rem ============================================================

rem ---- 提权 ----
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限，正在请求提升...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  echo.
  echo 如果上方没有弹出 UAC 权限确认框，说明提权被取消或失败。
  echo 请关闭本窗口后，右键此文件选择【以管理员身份运行】。
  pause
  exit /b
)

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "CAPTIVE=%ROOT%apps\captive"
set "TASK=IR_Hotspot_Redirect"

if not exist "%NODE%" (
  echo [错误] 缺少 runtime\node\node.exe，请完整拷贝便携包。
  pause & exit /b 1
)
if not exist "%CAPTIVE%\watchdog.ps1" (
  echo [错误] 缺少 apps\captive\watchdog.ps1，请完整拷贝便携包。
  pause & exit /b 1
)

echo ============================================================
echo   captive 无窗口守护（安装 / 卸载）
echo   请选择操作：
echo     1 - 安装守护并立即后台启动（推荐日常使用）
echo     2 - 卸载守护（停止并移除开机自启）
echo     0 - 退出
echo ============================================================
echo.
choice /c 120 /n /m "请选择 (1=安装 2=卸载 0=退出): "
if errorlevel 3 exit /b 0
if errorlevel 2 goto :Uninstall
if errorlevel 1 goto :Install

:Install
echo.
echo [0/4] 检查 TLS 证书（缺失则自动生成）...
if not exist "%CAPTIVE%\certs\cert.pem" (
  "%NODE%" "%ROOT%scripts\gen-cert.js" "%CAPTIVE%\certs"
  if errorlevel 1 ( echo [错误] 证书生成失败。 & pause & exit /b 1 )
)
echo       证书就绪。

echo.
echo [1/4] 清理旧的守护任务（如有）...
if exist "%CAPTIVE%\watchdog.stop" del "%CAPTIVE%\watchdog.stop" >nul 2>&1
schtasks /delete /tn "%TASK%" /f >nul 2>&1
schtasks /delete /tn "%TASK%_Recovery" /f >nul 2>&1
echo       [OK] 已清理。

echo.
echo [2/4] 注册开机自启计划任务 %TASK% ...
schtasks /create ^
  /tn "%TASK%" ^
  /tr "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%CAPTIVE%\watchdog.ps1\"" ^
  /sc ONSTART ^
  /delay 0000:30 ^
  /rl HIGHEST ^
  /f >nul 2>&1
if errorlevel 1 (
  echo [失败] 计划任务注册失败，请确认以管理员身份运行。
  pause & exit /b 1
)

echo       配置无限运行 + 任务级崩溃自恢复...
powershell -NoProfile -ExecutionPolicy Bypass -File "%CAPTIVE%\configure-task-recovery.ps1" -TaskName "%TASK%" >nul 2>&1
schtasks /change /tn "%TASK%" /np >nul 2>&1
echo       [OK] 已注册（开机 30 秒后自动以最高权限后台运行）。

echo.
echo [3/4] 立即后台启动 captive 守护（无窗口）...
schtasks /run /tn "%TASK%" >nul 2>&1
if errorlevel 1 (
  echo [警告] 立即启动失败，可能稍后随开机自启生效。
) else (
  echo       [OK] 已启动。稍候可运行 5.5-captive诊断.bat 确认 53/443 端口。
)

echo.
echo [4/4] 完成。请确认前置条件：
echo   - ClassIntra 服务器需已运行（建议先装 7-安装守护与开机自启.bat）
echo   - 本机需支持"移动热点"（watchdog 会自动拉起热点）
echo.
echo   日常查看状态 : 5.5-captive诊断.bat （只读）
echo   查看运行日志 : apps\captive\logs\service.log / watchdog.log
echo   停止服务     : 6-停止Captive.bat （守护会在下次开机时随自启恢复）
echo   彻底卸载守护 : 双击本脚本选 2
echo ============================================================
echo.
pause
exit /b 0

:Uninstall
echo.
echo [1/4] 通知 watchdog 停止（避免自愈拉起）...
echo stop>"%CAPTIVE%\watchdog.stop"
schtasks /end /tn "%TASK%" >nul 2>&1
schtasks /end /tn "%TASK%_Recovery" >nul 2>&1
echo       [OK]

echo.
echo [2/4] 停止 captive 服务进程（hotspot-redirect.js）...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { $_.CommandLine -like '*hotspot-redirect.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo       [OK] 已停止。

echo.
echo [3/4] 删除开机自启计划任务...
schtasks /delete /tn "%TASK%" /f >nul 2>&1
schtasks /delete /tn "%TASK%_Recovery" /f >nul 2>&1
echo       [OK] 已删除。

echo.
echo [4/4] 清理防火墙规则与锁文件...
netsh advfirewall firewall delete rule name="Hotspot DNS Redirect" >nul 2>&1
netsh advfirewall firewall delete rule name="Hotspot HTTPS Redirect" >nul 2>&1
if exist "%CAPTIVE%\watchdog.lock" del "%CAPTIVE%\watchdog.lock" >nul 2>&1
echo       [OK] 完成。

echo.
echo 守护已卸载。如需前台调试模式，可双击 5-captive热点劫持-启动.bat。
echo.
pause
exit /b 0
