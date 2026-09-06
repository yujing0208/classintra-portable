@echo off
setlocal
cd /d "%~dp0"

rem 提权
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
set "APP=%ROOT%apps\ClassIntra"
set "PM2=%APP%\server\node_modules\pm2\bin\pm2"
set "PM2_HOME=%ROOT%runtime\pm2-home"
if not exist "%PM2_HOME%" mkdir "%PM2_HOME%"
if not exist "%APP%\logs" mkdir "%APP%\logs"

if not exist "%NODE%" ( echo [错误] 缺少 runtime\node\node.exe & pause & exit /b 1 )
if not exist "%PM2%" ( echo [错误] 未找到 pm2，请先运行 1-安装初始化.bat & pause & exit /b 1 )

echo ============================================================
echo   安装 ClassIntra 守护 + 开机自启
echo   - PM2 守护：崩溃自动重启、开机恢复、日志记录
echo   - 计划任务：登录 Windows 后自动拉起服务
echo ============================================================
echo.

echo [1/3] 用 PM2 启动服务（守护模式）...
"%NODE%" "%PM2%" start "%APP%\ecosystem.config.js"
if errorlevel 1 (
  echo [错误] PM2 启动失败。
  pause & exit /b 1
)
echo       保存进程列表（供开机 resurrect）...
"%NODE%" "%PM2%" save
echo.

echo [2/3] 注册开机自启计划任务 ClassIntraAutoStart ...
schtasks /Create /TN "ClassIntraAutoStart" /TR "wscript.exe \"%ROOT%scripts\classintra-autostart.vbs\"" /SC ONLOGON /RL HIGHEST /F >nul 2>&1
if errorlevel 1 (
  echo [警告] 计划任务注册失败（可能权限不足）。服务仍可由 PM2 守护。
) else (
  echo       已注册（登录 Windows 后自动恢复服务）。
)
echo.

echo [3/3] 完成检查 ...
"%NODE%" "%PM2%" ls
echo.
echo ============================================================
echo   完成！现在服务由 PM2 守护，崩溃会自动重启。
echo   网页: http://localhost:9001
echo   查看日志: 双击本文件所在目录下的 8-查看状态与日志.bat
echo   卸载:    双击 8-卸载守护.bat
echo   重要:    用完电脑请运行 9-安全退出.bat 再弹出 U 盘！
echo ============================================================
echo.
pause
