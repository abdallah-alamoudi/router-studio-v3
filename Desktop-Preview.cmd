@echo off
"%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\installation\Start-Desktop-Preview.ps1"
if errorlevel 1 pause
