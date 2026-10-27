@echo off
setlocal DisableDelayedExpansion
set "ZAPRET_REWORK_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';try{Start-Process -FilePath (Join-Path $env:ZAPRET_REWORK_ROOT 'general.bat') -WorkingDirectory $env:ZAPRET_REWORK_ROOT -Verb RunAs}catch{Write-Host 'Launch cancelled or failed. Extract the full archive and try again.' -ForegroundColor Red;exit 1}"
if errorlevel 1 pause
