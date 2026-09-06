@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo   更新 ClassIntra 代码（需要本机装有 git 且能访问 GitHub 镜像）
echo   更新后请重新运行 1-安装初始化.bat 完成依赖与构建
echo ============================================================
echo.

where git >nul 2>&1
if errorlevel 1 (
  echo [提示] 本机未安装 git，无法在线更新。
  echo        建议：在开发电脑上更新后，把整个文件夹重新拷贝到 U 盘。
  pause & exit /b 1
)

cd /d "%~dp0apps\ClassIntra"
git pull --depth=1 origin main 2>nul
if errorlevel 1 (
  echo [提示] 直接 pull 失败，尝试普通方式...
  git pull origin main
)
echo.
echo 代码更新完成。接下来请运行 1-安装初始化.bat。
echo.
pause
