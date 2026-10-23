@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoLogo -NoProfile -File "%~dp0utils\start-youtube.ps1"
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
