@echo off
setlocal

set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%one-click-local-libretranslate.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. Please check messages above.
  pause
  exit /b 1
)

echo.
echo Local LibreTranslate setup completed.
pause
endlocal
