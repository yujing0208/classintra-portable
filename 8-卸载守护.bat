@echo off
setlocal
cd /d "%~dp0"

rem 提权
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限，正在请求提升...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "APP=%ROOT%apps\ClassIntra"
set "PM2=%APP%\server\node_modules\pm2\bin\pm2"
set "PM2_HOME=%ROOT%runtime\pm2-home"

echo ============================================================
echo   卸载 ClassIntra 守护与开机自启
echo ============================================================
echo.

if exist "%PM2%" (
  echo 停止并删除 PM2 托管进程...
  "%NODE%" "%PM2%" delete classintra-server >nul 2>&1
  "%NODE%" "%PM2%" kill >nul 2>&1
  echo   已停止（如需重新运行服务，用 2-启动ClassIntra.bat）
) else (
  echo   未找到 pm2，跳过。
)

echo 删除开机自启计划任务...
schtasks /Delete /TN "ClassIntraAutoStart" /F >nul 2>&1
if errorlevel 1 ( echo   计划任务不存在或已删除。 ) else ( echo   已删除。 )

echo.
echo 完成。
echo.
pause
