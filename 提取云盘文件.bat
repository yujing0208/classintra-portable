@echo off
chcp 65001 >nul
title ClassIntra Cloud Export
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "NODE="
if exist "runtime\node_gui\node.exe" set "NODE=%~dp0runtime\node_gui\node.exe"
if not defined NODE if exist "runtime\node\node.exe" set "NODE=%~dp0runtime\node\node.exe"
if not defined NODE (
  echo [ERROR] Bundled node.exe not found under runtime\ .
  echo         Run this script from the ClassIntra package root.
  echo.
  pause
  exit /b 1
)

echo ====================================================
echo  ClassIntra cloud export - pull out every file
echo ====================================================
echo.

"%NODE%" "%~dp0tools\export-cloud.js" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo Finished. The export folder has been opened.
) else (
  echo Finished with problems. Exit code: %RC%
  echo Check the export log inside the output folder.
)
echo.
pause
exit /b %RC%
