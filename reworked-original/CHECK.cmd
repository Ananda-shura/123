@echo off
setlocal DisableDelayedExpansion
set "ZAPRET_CORE_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';try{$r=$env:ZAPRET_CORE_ROOT;$p=Join-Path $r 'utils/reviewed-support.ps1';if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne 'd9a131f0bd674d3ff1f68565e6f6c9fa0c3bf9a5b00dad5ce6ce05d0df51b9ba'){throw 'Support checksum mismatch. Extract archive again.'};$s=[scriptblock]::Create([IO.File]::ReadAllText($p));& $s -Root $r -Mode Preflight -ValidateOnly}catch{Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}"
set "result=%errorlevel%"
pause
exit /b %result%
