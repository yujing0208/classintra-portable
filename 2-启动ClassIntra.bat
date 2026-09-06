@echo off
setlocal
cd /d "%~dp0"

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "APP=%ROOT%apps\ClassIntra"

if not exist "%NODE%" (
  echo [错误] 缺少 runtime\node\node.exe，请完整拷贝便携包。
  pause & exit /b 1
)
if not exist "%APP%\client\dist\index.html" (
  echo [提示] 前端还没有构建。
  echo        请先运行：1-安装初始化.bat
  pause & exit /b 1
)

rem 防双开：9001 已被监听（如守护模式/已在运行）时直接引导访问
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":9001 " ^| findstr "LISTENING"') do (
  echo 服务已经在运行中（端口 9001 已被监听）。
  echo 可能来源：守护模式（7-安装守护） 或另一个前台窗口。
  echo.
  powershell -NoProfile -Command "Start-Process 'http://localhost:9001'"
  echo 已打开浏览器。无需重复启动。
  pause & exit /b 0
)

rem 确保数据库存在（幂等）
if not exist "%APP%\server\database" mkdir "%APP%\server\database"

rem NODE_PATH 指向 server\node_modules：内置子应用(resource/weather/music等)
rem 通过该路径解析 express 等公共依赖（与 PM2 ecosystem 配置一致）
set "NODE_PATH=%APP%\server\node_modules"

echo 正在启动 ClassIntra 服务器 ...
echo.
echo   访问地址:  http://localhost:9001
echo   关闭方法:  关闭弹出的 "ClassIntra Server" 黑色窗口，
echo              或双击 3-停止ClassIntra.bat
echo.

rem 后台窗口运行服务器（独立窗口，标题为 ClassIntra Server）
start "ClassIntra Server" /d "%APP%\server" cmd /k ""%NODE%" --max-old-space-size=768 src/app.js"

rem 等待服务就绪后自动打开浏览器（最多等 40 秒）
powershell -NoProfile -Command "$ok=$false; for($i=0;$i -lt 40;$i++){ try{ $r=Invoke-WebRequest 'http://localhost:9001' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -ge 200 -and $r.StatusCode -lt 500){ $ok=$true; break } }catch{}; Start-Sleep -Seconds 1 }; if($ok){ Start-Process 'http://localhost:9001' } else { Write-Host '服务似乎未在 40 秒内就绪，请检查 ClassIntra Server 窗口日志。' }"

echo.
echo 服务器窗口已打开。若浏览器未自动弹出，请手动访问 http://localhost:9001
echo.
pause
