@echo off
setlocal DisableDelayedExpansion
set "ZAPRET_HAPP_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';try{$r=$env:ZAPRET_HAPP_ROOT;$p=Join-Path $r 'happ/setup-happ.ps1';if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne 'f97488eec4d8e77bae5e6206fae4ee328fba487e82be1d159a0822fff3cb386d'){throw 'Setup checksum mismatch. Extract archive again.'};$p=Join-Path $r 'happ/telegram-ipset.ps1';if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne '973b1939ba19c92cd5a38e3d11da2364bfb5ac8b8767ce5cfda71c16cf868511'){throw 'Setup checksum mismatch. Extract archive again.'};$p=Join-Path $r 'happ/setup-happ.ps1';$s=[scriptblock]::Create([IO.File]::ReadAllText($p));& $s -Root $r}catch{Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}"
set "result=%errorlevel%"
pause
exit /b %result%
