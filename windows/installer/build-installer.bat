@echo off
setlocal

set APP_VERSION=1.0.0
if not "%~1"=="" set APP_VERSION=%~1
set LOG_PATH=%~dp0build-installer.log

powershell -ExecutionPolicy Bypass -File "%~dp0build-installer.ps1" -AppVersion %APP_VERSION% > "%LOG_PATH%" 2>&1
if errorlevel 1 (
  echo.
  echo Build failed. See log:
  echo %LOG_PATH%
  type "%LOG_PATH%"
  pause
  exit /b 1
)

echo.
for %%f in ("%~dp0..\dist\installer\TripleSpaceTranslator-Setup-%APP_VERSION%.exe") do (
  if exist "%%~ff" (
    echo Installer ready:
    echo %%~ff
    start "" explorer /select,"%%~ff"
  )
)

echo.
echo Build log:
echo %LOG_PATH%
pause

endlocal
