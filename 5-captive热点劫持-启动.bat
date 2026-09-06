@echo off
setlocal
cd /d "%~dp0"

rem 检查管理员权限，没有则自动 UAC 提权重启
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
if not exist "%NODE%" (
  echo [错误] 缺少 runtime\node\node.exe，请完整拷贝便携包。
  pause & exit /b 1
)

rem 将包内 node 置于 PATH 最前，使 captive 脚本的 node 命令可用
set "PATH=%ROOT%runtime\node;%PATH%"

rem 首次运行自动生成 TLS 证书（无 OpenSSL 依赖，纯 Node 生成）
if not exist "%ROOT%apps\captive\certs\cert.pem" (
  echo.
  echo [首次运行] 未找到 TLS 证书，正在自动生成（5 年有效期）...
  "%ROOT%runtime\node\node.exe" "%ROOT%scripts\gen-cert.js" "%ROOT%apps\captive\certs"
  if errorlevel 1 (
    echo [错误] 证书生成失败。
    pause & exit /b 1
  )
  echo.
)

echo.
echo ============================================================
echo   Captive 热点劫持（便携版 · 前台调试模式）
echo   拦截域名： ai.changyan.com / spark.changyan.com / www.wjx.cn / zhixue.com
echo             学生连热点后访问这些域名会自动跳转到 ClassIntra
echo   日常上课建议用无窗口守护：5.2-captive守护安装.bat（选 1）
echo   本模式用于排障/看实时日志，停止：本窗口 Ctrl+C 或 6-停止Captive.bat
echo ============================================================
echo.
pause

cd /d "%ROOT%apps\captive"
call start-hotspot-redirect.bat %*

echo.
echo Captive 已退出。
pause
