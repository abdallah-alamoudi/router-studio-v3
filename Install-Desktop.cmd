@echo off
setlocal
set "INSTALLER=%~dp0scripts\Install-Desktop.ps1"
if not exist "%INSTALLER%" (
  echo This command is for a built Router Studio release package.
  echo To build and run from source, follow docs\DESKTOP-PREVIEW.md.
  pause
  exit /b 2
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -AllowUnsignedPreview
set "INSTALL_RESULT=%ERRORLEVEL%"
if not "%INSTALL_RESULT%"=="0" pause
exit /b %INSTALL_RESULT%
