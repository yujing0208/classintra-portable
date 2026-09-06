@echo off
rem ClassIntra 开机自启入口（由计划任务调用，实际执行见同名 .vbs）
rem 只做一件事：恢复 PM2 托管的服务进程；无窗口打扰
setlocal

set "ROOT=%~dp0.."
set "NODE=%ROOT%\runtime\node\node.exe"
set "APP=%ROOT%\apps\ClassIntra"
set "PM2=%APP%\server\node_modules\pm2\bin\pm2"
set "PM2_HOME=%ROOT%\runtime\pm2-home"

if not exist "%NODE%" exit /b 0
if not exist "%PM2%" exit /b 0

rem resurrect 会恢复上次 pm2 save 的进程；未 save 过则直接 start
"%NODE%" "%PM2%" resurrect >nul 2>&1
if errorlevel 1 (
  "%NODE%" "%PM2%" start "%APP%\ecosystem.config.js" >nul 2>&1
  "%NODE%" "%PM2%" save >nul 2>&1
)
exit /b 0
