@echo off
setlocal DisableDelayedExpansion
set "ZAPRET_EXPANDED_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';try{$r=$env:ZAPRET_EXPANDED_ROOT;$p=Join-Path $r 'expanded/expanded.ps1';if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne '63487461db1f229ff4fe28c19b2954ea48553ffa58a0aa78e06d3eae564b28d5'){throw 'Launcher checksum mismatch. Extract archive again.'};$s=[scriptblock]::Create([IO.File]::ReadAllText($p));& $s -Root $r}catch{Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}"
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
