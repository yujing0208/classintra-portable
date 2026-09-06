@echo off
setlocal
title ClassIntra Portable - Setup
cd /d "%~dp0"

echo ============================================================
echo   ClassIntra 便携版 - 安装 / 初始化
echo   （首次使用或代码更新后运行；重复运行安全）
echo ============================================================
echo.

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "PNPM_JS=%ROOT%runtime\pnpm\node_modules\pnpm\bin\pnpm.cjs"
set "APP=%ROOT%apps\ClassIntra"

if not exist "%NODE%" (
  echo [错误] 找不到 runtime\node\node.exe
  echo        请确认整个文件夹是从 U 盘完整拷贝的（不要只拷部分文件）。
  pause & exit /b 1
)
if not exist "%PNPM_JS%" (
  echo [错误] 找不到内置 pnpm，请重新完整拷贝便携包。
  pause & exit /b 1
)
if not exist "%APP%\package.json" (
  echo [错误] 找不到 apps\ClassIntra 源码，请重新完整拷贝便携包。
  pause & exit /b 1
)

echo [1/4] 安装项目依赖（走国内镜像，首次约几分钟）...
pushd "%APP%"
"%NODE%" "%PNPM_JS%" install --frozen-lockfile
if errorlevel 1 (
  echo.
  echo 依赖安装未完全成功，重试一次（不锁定版本）...
  "%NODE%" "%PNPM_JS%" install
  if errorlevel 1 (
    echo [错误] 依赖安装失败。请检查网络后重试。
    pause & exit /b 1
  )
)
popd
echo.

echo [2/4] 生成服务器配置 server\.env ...
if not exist "%APP%\server\.env" (
  copy /Y "%APP%\server\.env.example" "%APP%\server\.env" >nul
  rem 生成随机 JWT_SECRET 并写入
  powershell -NoProfile -Command "$p='%APP:\=\\%server\.env'; $l=Get-Content $p -Encoding UTF8; $r=[Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48)); for($i=0;$i -lt $l.Count;$i++){ if($l[$i] -match '^JWT_SECRET='){ $l[$i]='JWT_SECRET='+$r } }; Set-Content $p $l -Encoding UTF8"
  echo       已生成 .env（含随机 JWT_SECRET）
  echo.
  echo       ^>^> 请用记事本打开 apps\ClassIntra\server\.env，按你的班级修改：
  echo          ADMIN_USER_IDS=你的班管ID   （如 250100 表示25届01班）
  echo          DEV_PASSWORD=xxx            （取消注释可创建 ID=999999 测试号）
) else (
  echo       已存在，跳过。
)
echo.

echo [3/4] 初始化数据库 ...
pushd "%APP%\server"
rem -r dotenv/config 先加载 .env，否则 JWT_SECRET 缺失会 FATAL
"%NODE%" -r dotenv/config src/utils/init-db.js
if errorlevel 1 (
  echo [错误] 数据库初始化失败。
  popd
  pause & exit /b 1
)
popd
echo.

echo [4/4] 构建前端页面（首次约 1-3 分钟）...
pushd "%APP%\client"
"%NODE%" "%PNPM_JS%" run build
if errorlevel 1 (
  echo [错误] 前端构建失败。
  pause & exit /b 1
)
popd
echo.

echo ============================================================
echo   完成！接下来运行：2-启动ClassIntra.bat
echo   浏览器访问  http://localhost:9001
echo   管理员：  ADMIN_USER_IDS 中配置的班管ID（注册时自动成为管理员）
echo ============================================================
echo.
pause
