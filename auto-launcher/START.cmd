@echo off
setlocal DisableDelayedExpansion
set "ZAPRET_AUTO_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';try{$r=$env:ZAPRET_AUTO_ROOT;$p=Join-Path $r 'autopick/autopick.ps1';if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne '7424a495e23523da4749aef08c0d9666d6e12b150347dc5c6a0c7c85a8b02f96'){throw 'Launcher checksum mismatch. Extract the downloaded archive again.'};$s=[scriptblock]::Create([IO.File]::ReadAllText($p));& $s -Root $r}catch{Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}"
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
