@echo off
setlocal
cd /d "%~dp0"

echo 正在停止 ClassIntra 服务器 ...
taskkill /FI "WINDOWTITLE eq ClassIntra Server*" /T /F >nul 2>&1
if errorlevel 1 (
  echo 未找到运行中的服务器窗口（可能已停止）。
) else (
  echo 已停止。
)
echo.
pause
