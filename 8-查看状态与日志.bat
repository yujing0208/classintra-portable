@echo off
setlocal
cd /d "%~dp0"

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "APP=%ROOT%apps\ClassIntra"
set "PM2=%APP%\server\node_modules\pm2\bin\pm2"
set "PM2_HOME=%ROOT%runtime\pm2-home"

echo ============================================================
echo   ClassIntra 服务状态与日志
echo ============================================================
echo.

if exist "%PM2%" (
  echo --- PM2 进程列表 ---
  "%NODE%" "%PM2%" ls
  echo.
  echo --- 最近 30 行输出日志 ---
  "%NODE%" "%PM2%" logs classintra-server --lines 30 --nostream
  echo.
) else (
  echo   未找到 pm2，守护模式未安装。
  echo   提示: 若服务正以前台窗口运行（2-启动），日志在窗口内查看。
)
echo.
pause
