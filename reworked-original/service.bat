@echo off
set "LOCAL_VERSION=1.10.4"

:: External commands
if "%~1"=="status_zapret" goto reviewed_preflight
if "%~1"=="check_files" goto reviewed_check_files

if "%~1"=="check_updates" (
    if defined NO_UPDATE_CHECK exit /b

    if exist "%~dp0utils\check_updates.enabled" (
        if not "%~2"=="soft" (
            start "" /b "%ComSpec%" /d /c call "%~f0" check_updates soft
        ) else (
            call :service_check_updates soft
        )
    )

    exit /b
)

if "%~1"=="load_game_filter" (
    call :game_switch_status
    exit /b
)

if "%~1"=="load_user_lists" (
    call :load_user_lists
    exit /b
)

if "%1"=="admin" (
    call :check_command chcp || exit /b 1
    call :check_command find || exit /b 1
    call :check_command findstr || exit /b 1
    call :check_command netsh || exit /b 1
    
    call :load_user_lists

    echo Started with admin rights
) else (
    call :check_extracted || exit /b 1
    call :check_command powershell || exit /b 1

    echo Requesting admin rights...
    set "ZAPRET_REVIEW_SERVICE=%~f0"
    powershell -NoProfile -Command "try { Start-Process -FilePath $env:ZAPRET_REVIEW_SERVICE -ArgumentList 'admin' -Verb RunAs -ErrorAction Stop } catch { Write-Host 'Administrator request was cancelled or failed.'; exit 1 }"
    exit
)


:: MENU ================================
setlocal EnableDelayedExpansion
title ZAPRET SERVICE MANAGER v!LOCAL_VERSION!
:menu

cls

call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :get_strategy_name

set "menu_choice=null"

echo.
echo   ZAPRET SERVICE MANAGER v!LOCAL_VERSION!
echo.  !CurrentStrategy!
echo   ----------------------------------------
echo.
echo   :: SERVICE
echo      1. Install Service
echo      2. Remove this folder's zapret service
echo      3. Check Status
echo.
echo   :: SETTINGS
echo      4. Game Filter         [!GameFilterStatus!]
echo      5. IPSet Filter        [!IPsetStatus!]
echo      6. Auto-Update Check   [!CheckUpdatesStatus!]
echo      7. Replace active fakes
echo.
echo   :: UPDATES
echo      8. Update IPSet List
echo      9. Hosts information (manual only)
echo      10. Check for Updates
echo.
echo   :: TOOLS
echo      11. Diagnostics (read-only)
echo      12. Check files (read-only)
echo.
echo   ----------------------------------------
echo      0. Exit
echo.

set /p menu_choice=   Select option (0-12): 

if "%menu_choice%"=="1" goto service_install
if "%menu_choice%"=="2" goto service_remove
if "%menu_choice%"=="3" goto service_status
if "%menu_choice%"=="4" goto game_switch
if "%menu_choice%"=="5" goto ipset_switch
if "%menu_choice%"=="6" goto check_updates_switch
if "%menu_choice%"=="7" goto replace_active_fakes
if "%menu_choice%"=="8" goto ipset_update
if "%menu_choice%"=="9" goto hosts_update
if "%menu_choice%"=="10" goto service_check_updates
if "%menu_choice%"=="11" goto service_diagnostics
if "%menu_choice%"=="12" goto run_tests
if "%menu_choice%"=="0" exit /b
goto menu


:: LOAD USER LISTS =====================
:load_user_lists
set "LISTS_PATH=%~dp0lists\"

if not exist "%LISTS_PATH%ipset-exclude-user.txt" (
    echo 203.0.113.113/32>"%LISTS_PATH%ipset-exclude-user.txt"
)
if not exist "%LISTS_PATH%list-general-user.txt" (
    echo # Never leave this file empty>"%LISTS_PATH%list-general-user.txt"
    echo domain.example.abc>>"%LISTS_PATH%list-general-user.txt"
)
if not exist "%LISTS_PATH%list-exclude-user.txt" (
    echo domain.example.abc>"%LISTS_PATH%list-exclude-user.txt"
)

exit /b


:: TCP ENABLE ==========================
:tcp_enable
:: Kept for batch compatibility. Global TCP timestamps are never changed here.
exit /b 0


:: STATUS ==============================
:service_status
cls
chcp 437 > nul

sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do echo Service strategy installed from "%%B"
)

call :test_service zapret
call :test_service WinDivert

set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "WinDivert64.sys file NOT found."
)
echo:

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    call :PrintGreen "Bypass (winws.exe) is RUNNING."
) else (
    call :PrintRed "Bypass (winws.exe) is NOT running."
)

pause
goto menu

:test_service
set "ServiceName=%~1"
set "ServiceStatus="

for /f "tokens=3 delims=: " %%A in ('sc query "%ServiceName%" ^| findstr /i "STATE"') do set "ServiceStatus=%%A"
set "ServiceStatus=%ServiceStatus: =%"

if "%ServiceStatus%"=="RUNNING" (
    if "%~2"=="soft" (
        echo "%ServiceName%" is ALREADY RUNNING as service, use "service.bat" and choose "Remove Services" first if you want to run standalone bat.
        pause
        exit /b
    ) else (
        echo "%ServiceName%" service is RUNNING.
    )
) else if "%ServiceStatus%"=="STOP_PENDING" (
    call :PrintYellow "!ServiceName! is STOP_PENDING, that may be caused by a conflict with another bypass. Run Diagnostics to try to fix conflicts"
) else if not "%~2"=="soft" (
    echo "%ServiceName%" service is NOT running.
)

exit /b


:: REMOVE ==============================
:service_remove
cls
chcp 65001 > nul
call :reviewed_support CheckServiceOwner
if errorlevel 1 (
    pause
    goto menu
)
sc query "zapret" >nul 2>&1
if errorlevel 1 (
    echo Service "zapret" is not installed.
    pause
    goto menu
)
echo Only the zapret service belonging to this folder will be stopped and removed.
echo Shared WinDivert drivers and other processes are left unchanged.
sc qc "zapret"
set "REMOVE_CONFIRM="
set /p "REMOVE_CONFIRM=Type REMOVE to stop and delete this zapret service (Enter cancels): "
if not "!REMOVE_CONFIRM!"=="REMOVE" goto menu
net stop "zapret"
sc delete "zapret"
if errorlevel 1 echo Could not delete zapret. No shared drivers or unrelated processes were removed.
pause
goto menu


:: INSTALL =============================
:service_install
cls
chcp 437 > nul

:: Main
cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"

:: Searching for .bat files in current folder, except files that start with "service"
echo Pick one of the options:
set "count=0"
for /f "delims=" %%F in ('powershell -NoProfile -Command "Get-ChildItem -LiteralPath '.' -Filter 'general*.bat' | Where-Object { $_.Name -ne 'general (ALT5).bat' } | Sort-Object { [Regex]::Replace($_.Name, '(\d+)', { $args[0].Value.PadLeft(8, '0') }) } | ForEach-Object { $_.Name }"') do (
    set /a count+=1
    echo   !count!. %%F
    set "file!count!=%%F"
)

echo   0. Exit

echo.

:: Choosing file
set "choice="
set /p "choice=Input option (0-!count!, default: 0): "
if "!choice!"=="" (
    set "choice=0"
)

if "!choice!"=="0" (
    goto menu
)

set "selectedFile=!file%choice%!"
if /i "!selectedFile!"=="general (ALT5).bat" goto menu
if not defined selectedFile (
    echo Invalid choice, exiting...
    pause
    goto menu
)

:: Args that should be followed by value
set "args_with_value=sni host altorder"

:: Parsing args (mergeargs: 2=start param|3=arg with value|1=params args|0=default)
set "args="
set "capture=0"
set "mergeargs=0"
set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
set QUOTE="

for /f "tokens=*" %%a in ('type "!selectedFile!"') do (
    set "line=%%a"
    call set "line=%%line:^!=EXCL_MARK%%"
    call set "line=!line!"

    echo !line! | findstr /i "winws.exe" >nul
    if not errorlevel 1 (
        set "capture=1"
    )

    if !capture!==1 (
        if not defined args (
            set "line=!line:*winws.exe"=!"
        )

        set "temp_args="
        for %%i in (!line!) do (
            set "arg=%%i"

            if not "!arg!"=="^" if not "!arg!"=="^^" (
                if "!arg:~0,2!" EQU "--" if not !mergeargs!==0 (
                    set "mergeargs=0"
                )

                if "!arg:~0,1!" EQU "!QUOTE!" (
                    set "arg=!arg:~1,-1!"

                    echo !arg! | findstr ":" >nul
                    if !errorlevel!==0 (
                        set "arg=\!QUOTE!!arg!\!QUOTE!"
                    ) else if "!arg:~0,1!"=="@" (
                        set "arg=\!QUOTE!@%~dp0!arg:~1!\!QUOTE!"
                    ) else (
                        set "arg=\!QUOTE!%~dp0!arg!\!QUOTE!"
                    )
                )

                if !mergeargs!==1 (
                    set "temp_args=!temp_args!,!arg!"
                ) else if !mergeargs!==3 (
                    set "temp_args=!temp_args!=!arg!"
                    set "mergeargs=1"
                ) else (
                    set "temp_args=!temp_args! !arg!"
                )

                if "!arg:~0,2!" EQU "--" (
                    set "mergeargs=2"
                ) else if !mergeargs! GEQ 1 (
                    if !mergeargs!==2 set "mergeargs=1"

                    for %%x in (!args_with_value!) do (
                        if /i "%%x"=="!arg!" (
                            set "mergeargs=3"
                        )
                    )
                )
            )
        )

        if not "!temp_args!"=="" (
            set "args=!args! !temp_args!"
        )
    )
)

:: Creating service with parsed args (no global TCP settings change)

set ARGS=%args%
call set "ARGS=%%ARGS:EXCL_MARK=^!%%"
echo Final args: !ARGS!
set SRVCNAME=zapret

if not defined ARGS (
    echo Selected strategy did not contain valid arguments. Nothing was installed.
    pause
    goto menu
)
call :reviewed_support Validate
if errorlevel 1 (
    pause
    goto menu
)
call :reviewed_support CheckServiceOwner
if errorlevel 1 (
    pause
    goto menu
)
echo This action installs or replaces this folder's zapret service with automatic startup.
echo Review the final arguments above. Other folders' services will not be replaced.
set "INSTALL_CONFIRM="
set /p "INSTALL_CONFIRM=Type INSTALL to continue (Enter cancels): "
if not "!INSTALL_CONFIRM!"=="INSTALL" goto menu
net stop %SRVCNAME% >nul 2>&1
sc delete %SRVCNAME% >nul 2>&1
sc create %SRVCNAME% binPath= "\"%BIN_PATH%winws.exe\" !ARGS!" DisplayName= "zapret" start= auto
if errorlevel 1 (
    echo Service creation failed. Close Services.msc if it is holding the old service open and retry.
    pause
    goto menu
)
sc description %SRVCNAME% "Zapret DPI bypass software"
sc start %SRVCNAME%
if errorlevel 1 echo The service was created but did not start. Check its arguments and permissions.
for %%F in ("!file%choice%!") do (
    set "filename=%%~nF"
)
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f

pause
goto menu


:: CHECK UPDATES =======================
:service_check_updates
chcp 437 > nul
if not "%~1"=="soft" cls
set "GITHUB_VERSION="

:: Set current version and URLs
set "GITHUB_VERSION_URL=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt"
set "GITHUB_RELEASE_URL=https://github.com/Flowseal/zapret-discord-youtube/releases/tag/"
set "GITHUB_DOWNLOAD_URL=https://github.com/Flowseal/zapret-discord-youtube/releases/latest"

:: Get the latest version from GitHub
for /f "delims=" %%A in ('powershell -NoProfile -Command "(Invoke-WebRequest -Uri \"%GITHUB_VERSION_URL%\" -Headers @{\"Cache-Control\"=\"no-cache\"} -UseBasicParsing -TimeoutSec 5).Content.Trim()" 2^>nul') do set "GITHUB_VERSION=%%A"

:: Error handling
if not defined GITHUB_VERSION (
    echo Warning: failed to fetch the latest version. This warning does not affect the operation of zapret
    timeout /T 9
    if "%~1"=="soft" exit /b
    goto menu
)

:: Version comparison
if "%LOCAL_VERSION%"=="%GITHUB_VERSION%" (
    echo Latest version installed: %LOCAL_VERSION%
    
    if "%~1"=="soft" exit /b
    pause
    goto menu
) 

echo New version available: %GITHUB_VERSION%
echo Release page: %GITHUB_RELEASE_URL%%GITHUB_VERSION%

echo Download page: %GITHUB_DOWNLOAD_URL%
echo Open it manually if you choose to update.


if "%~1"=="soft" exit /b
pause
goto menu



:: DIAGNOSTICS =========================
:service_diagnostics
chcp 437 > nul
cls

:: Zapret path
call :PrintGreen "Zapret is installed in: '%~dp0'"
echo:

:: Base Filtering Engine
sc query BFE | findstr /I "RUNNING" > nul
if !errorlevel!==0 (
    call :PrintGreen "Base Filtering Engine check passed"
) else (
    call :PrintRed "[X] Base Filtering Engine is not running. This service is required for zapret to work"
)
echo:

:: Proxy check
set "proxyEnabled=0"
set "proxyServer="

for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do (
    if "%%B"=="0x1" set "proxyEnabled=1"
)

if !proxyEnabled!==1 (
    for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do (
        set "proxyServer=%%B"
    )
    
    call :PrintYellow "[?] System proxy is enabled: !proxyServer!"
    call :PrintYellow "Make sure it's valid or disable it if you don't use a proxy"
) else (
    call :PrintGreen "Proxy check passed"
)
echo:

:: TCP timestamps information (read-only)
netsh interface tcp show global
call :PrintYellow "TCP settings are displayed only. This diagnostic does not change timestamps."
echo:

:: AdguardSvc.exe
tasklist /FI "IMAGENAME eq AdguardSvc.exe" | find /I "AdguardSvc.exe" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Adguard process found. Adguard may cause problems with Discord"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/417"
) else (
    call :PrintGreen "Adguard check passed"
)
echo:

:: Killer
sc query | findstr /I "Killer" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Killer services found. Killer conflicts with zapret"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/2512#issuecomment-2821119513"
) else (
    call :PrintGreen "Killer check passed"
)
echo:

:: Intel Connectivity Network Service
sc query | findstr /I "Intel" | findstr /I "Connectivity" | findstr /I "Network" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Intel Connectivity Network Service found. It conflicts with zapret"
    call :PrintRed "https://github.com/ValdikSS/GoodbyeDPI/issues/541#issuecomment-2661670982"
) else (
    call :PrintGreen "Intel Connectivity check passed"
)
echo:

:: Check Point
set "checkpointFound=0"
sc query | findstr /I "TracSrvWrapper" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

sc query | findstr /I "EPWD" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

if !checkpointFound!==1 (
    call :PrintRed "[X] Check Point services found. Check Point conflicts with zapret"
    call :PrintRed "Try to uninstall Check Point"
) else (
    call :PrintGreen "Check Point check passed"
)
echo:

:: SmartByte
sc query | findstr /I "SmartByte" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] SmartByte services found. SmartByte conflicts with zapret"
    call :PrintRed "Try to uninstall or disable SmartByte through services.msc"
) else (
    call :PrintGreen "SmartByte check passed"
)
echo:

:: Cyrillic path
powershell -NoProfile -Command "if ('%~dp0' -match '[\u0430-\u044F\u0410-\u042F\u0451\u0401]') { exit 0 } else { exit 1 }"
if !errorlevel!==0 (
    call :PrintYellow "[?] The path where Zapret is installed contains Cyrillic characters"
    call :PrintYellow "If bypass doesn't work, try to move Zapret to another directory, for example in C:\zapret"
) else (
    call :PrintGreen "Cyrillic path check passed"
)
echo:

:: OneDrive
if defined OneDrive (
    echo %~dp0\ | findstr /I /C:"%OneDrive%\\" > nul
    if !errorlevel!==0 (
        call :PrintRed "[X] Zapret is installed in a OneDrive folder"
        call :PrintRed "If bypass doesn't work, try to move Zapret to another directory, for example in C:\zapret"
    ) else (
        call :PrintGreen "OneDrive check passed"
    )
) else (
    call :PrintGreen "OneDrive check passed"
)
echo:

:: WinDivert64.sys file
set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "WinDivert64.sys file NOT found."
    echo:
)

:: VPN
set "VPN_SERVICES="
sc query | findstr /I "VPN HappService" > nul
if !errorlevel!==0 (
    for /f "tokens=2 delims=:" %%A in ('sc query ^| findstr /I "VPN HappService"') do (
        if not defined VPN_SERVICES (
            set "VPN_SERVICES=!VPN_SERVICES!%%A"
        ) else (
            set "VPN_SERVICES=!VPN_SERVICES!,%%A"
        )
    )
    call :PrintYellow "[?] VPN services found:!VPN_SERVICES!. Some VPNs can conflict with zapret"
    call :PrintYellow "An installed VPN service does not prove an active VPN connection. Check the actual connection in its application."
) else (
    call :PrintGreen "VPN check passed"
)
echo:

:: DNS
set "dohfound=0"
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-ChildItem -Recurse -Path 'HKLM:System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\' | Get-ItemProperty | Where-Object { $_.DohFlags -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count"') do (
    if %%a gtr 0 (
        set "dohfound=1"
    )
)
if !dohfound!==0 (
    call :PrintYellow "[?] Make sure you have configured secure DNS in a browser with some non-default DNS service provider,"
    call :PrintYellow "If you use Windows 11 you can configure encrypted DNS in the Settings to hide this warning"
) else (
    call :PrintGreen "Secure DNS check passed"
)
echo:

:: Hosts file check
set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
if exist "%hostsFile%" (
    set "yt_found=0"
    >nul 2>&1 findstr /I "youtube.com" "%hostsFile%" && set "yt_found=1"
    >nul 2>&1 findstr /I "youtu.be" "%hostsFile%" && set "yt_found=1"
    if !yt_found!==1 (
        call :PrintYellow "[?] Your hosts file contains entries for youtube.com or youtu.be. This may cause problems with YouTube access"
    )
)

:: WinDivert information (read-only; shared driver ownership is unknown)
sc query "WinDivert"
sc query "WinDivert14"
call :PrintYellow "A running driver may belong to another application. No driver or service is stopped or deleted."
echo:

:: Conflicting bypasses
set "conflicting_services=GoodbyeDPI discordfix_zapret winws1 winws2"
set "found_any_conflict=0"
set "found_conflicts="

for %%s in (!conflicting_services!) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 (
        if "!found_conflicts!"=="" (
            set "found_conflicts=%%s"
        ) else (
            set "found_conflicts=!found_conflicts! %%s"
        )
        set "found_any_conflict=1"
    )
)

if !found_any_conflict!==1 (
    call :PrintYellow "Other bypass services found: !found_conflicts!"
    call :PrintYellow "This diagnostic only reports them. Manage their own applications if necessary."
)
echo:
call :PrintGreen "Read-only diagnostics finished. No caches, services, drivers or TCP settings were changed."

pause
goto menu


:: GAME SWITCH ========================
:game_switch_status

set "gameFlagFile=%~dp0utils\game_filter.enabled"
set "GameFilterMode=disabled"
set "GameFilterTCPRange=1024-65535"
set "GameFilterUDPRange=1024-65535"
set "GameFilterStatus=disabled"
set "GameFilter=12"
set "GameFilterTCP=12"
set "GameFilterUDP=12"

if not exist "%gameFlagFile%" exit /b

set "GameFilterTCPCandidate="
set "GameFilterUDPCandidate="
for /f "usebackq tokens=1,* delims==" %%A in ("%gameFlagFile%") do (
    if /i "%%A"=="mode" set "GameFilterMode=%%B"
    if /i "%%A"=="all" set "GameFilterMode=all"
    if /i "%%A"=="udp" (
        if "%%B"=="" (set "GameFilterMode=udp") else set "GameFilterUDPCandidate=%%B"
    )
    if /i "%%A"=="tcp" (
        if "%%B"=="" (set "GameFilterMode=tcp") else set "GameFilterTCPCandidate=%%B"
    )
)

call :validate_game_filter_range "%GameFilterTCPCandidate%"
if defined ValidatedGameFilterRange set "GameFilterTCPRange=%ValidatedGameFilterRange%"
call :validate_game_filter_range "%GameFilterUDPCandidate%"
if defined ValidatedGameFilterRange set "GameFilterUDPRange=%ValidatedGameFilterRange%"

if /i "%GameFilterMode%"=="all" (
    set "GameFilterStatus=enabled (TCP and UDP)"
    set "GameFilter=%GameFilterTCPRange%"
    set "GameFilterTCP=%GameFilterTCPRange%"
    set "GameFilterUDP=%GameFilterUDPRange%"
) else if /i "%GameFilterMode%"=="tcp" (
    set "GameFilterStatus=enabled (TCP)"
    set "GameFilter=%GameFilterTCPRange%"
    set "GameFilterTCP=%GameFilterTCPRange%"
    set "GameFilterUDP=12"
) else if /i "%GameFilterMode%"=="udp" (
    set "GameFilterStatus=enabled (UDP)"
    set "GameFilter=%GameFilterUDPRange%"
    set "GameFilterTCP=12"
    set "GameFilterUDP=%GameFilterUDPRange%"
) else (
    set "GameFilterMode=disabled"
)
exit /b


:game_switch
chcp 437 > nul
cls
call :game_switch_status

echo Select game filter option:
if "%GameFilterMode%"=="disabled"   (echo   1. * Disable) else      echo   1.   Disable
if "%GameFilterMode%"=="all"        (echo   2. * TCP and UDP) else  echo   2.   TCP and UDP
if "%GameFilterMode%"=="tcp"        (echo   3. * TCP) else          echo   3.   TCP
if "%GameFilterMode%"=="udp"        (echo   4. * UDP) else          echo   4.   UDP
echo.
echo   5. Change TCP port range (current: %GameFilterTCPRange%)
echo   6. Change UDP port range (current: %GameFilterUDPRange%)
echo   7. Change TCP and UDP port ranges
echo.
echo.  0. Exit
echo.
set "GameFilterChoice=0"
set /p "GameFilterChoice=Select option (0-7, default: 0): "
if "%GameFilterChoice%"=="" set "GameFilterChoice=0"

if "%GameFilterChoice%"=="1" (
    set "GameFilterMode=disabled"
) else if "%GameFilterChoice%"=="2" (
    set "GameFilterMode=all"
) else if "%GameFilterChoice%"=="3" (
    set "GameFilterMode=tcp"
) else if "%GameFilterChoice%"=="4" (
    set "GameFilterMode=udp"
) else if "%GameFilterChoice%"=="5" (
    call :change_game_filter_range tcp
) else if "%GameFilterChoice%"=="6" (
    call :change_game_filter_range udp
) else if "%GameFilterChoice%"=="7" (
    call :change_game_filter_range all
) else (
    goto menu
)

echo.
call :save_game_filter_settings
call :PrintYellow "Restart the zapret to apply the changes"
pause
goto game_switch


:change_game_filter_range
set "GameFilterRangeInput="

echo.
echo Changing ports for %~1 (example: 1024-1934,1936-65535, default: 1024-65535)
set /p "GameFilterRangeInput=Enter ports/ranges: "
call :validate_game_filter_range "%GameFilterRangeInput%"
if not defined ValidatedGameFilterRange (
    call :PrintRed "Invalid input. Please enter valid ports/ranges."
    pause
    goto game_switch
)

if /i "%~1"=="tcp" set "GameFilterTCPRange=%ValidatedGameFilterRange%"
if /i "%~1"=="udp" set "GameFilterUDPRange=%ValidatedGameFilterRange%"
if /i "%~1"=="all" (
    set "GameFilterTCPRange=%ValidatedGameFilterRange%"
    set "GameFilterUDPRange=%ValidatedGameFilterRange%"
)
exit /b


:validate_game_filter_range
set "ValidatedGameFilterRange="
setlocal EnableDelayedExpansion
set "GameFilterRangeToValidate=%~1"
set "GameFilterRangeToValidate=!GameFilterRangeToValidate: =!"
if not defined GameFilterRangeToValidate exit /b
for %%A in ("!GameFilterRangeToValidate:,=" "!") do (
    call :gf_validate_item "%%~A"
    if not defined GameFilterRangeItemValid exit /b
)
endlocal & set "ValidatedGameFilterRange=%GameFilterRangeToValidate%"
exit /b


:gf_validate_item
set "GameFilterRangeItemValid="
setlocal EnableDelayedExpansion
set "GameFilterRangeItem=%~1"

echo(!GameFilterRangeItem!| findstr /r /x /c:"[1-9][0-9]*" /c:"[1-9][0-9]*-[1-9][0-9]*" > nul || exit /b
for /f "tokens=1,2 delims=-" %%A in ("!GameFilterRangeItem!") do (
    set "GameFilterRangeStart=%%A"
    set "GameFilterRangeEnd=%%B"
)
if not defined GameFilterRangeEnd set "GameFilterRangeEnd=!GameFilterRangeStart!"

if not "!GameFilterRangeStart:~5,1!"=="" exit /b
if not "!GameFilterRangeEnd:~5,1!"=="" exit /b
set /a GameFilterRangeStartNumber=GameFilterRangeStart, GameFilterRangeEndNumber=GameFilterRangeEnd
if !GameFilterRangeStartNumber! gtr 65535 exit /b
if !GameFilterRangeEndNumber! gtr 65535 exit /b
if !GameFilterRangeStartNumber! gtr !GameFilterRangeEndNumber! exit /b

endlocal & set "GameFilterRangeItemValid=1"
exit /b


:save_game_filter_settings
>"%gameFlagFile%" (
    echo mode=%GameFilterMode%
    echo tcp=%GameFilterTCPRange%
    echo udp=%GameFilterUDPRange%
)
exit /b


:: CHECK UPDATES SWITCH =================
:check_updates_switch_status
chcp 437 > nul

set "checkUpdatesFlag=%~dp0utils\check_updates.enabled"

if exist "%checkUpdatesFlag%" (
    set "CheckUpdatesStatus=enabled"
) else (
    set "CheckUpdatesStatus=disabled"
)
exit /b


:check_updates_switch
chcp 437 > nul
cls

if not exist "%checkUpdatesFlag%" (
    echo Enabling check updates...
    echo ENABLED > "%checkUpdatesFlag%"
) else (
    echo Disabling check updates...
    del /f /q "%checkUpdatesFlag%"
)

pause
goto menu


:: REPLACE ACTIVE FAKES =================
:replace_active_fakes
chcp 437 > nul
cls

set "BIN_PATH=%~dp0bin\"
set "fake_count=0"
set "fake_type="
set "fake_number="
set "discord_hash="
set "game_hash="
set "current_discord_fake=(not found)"
set "current_game_fake=(not found)"

if not exist "%BIN_PATH%" (
    echo Error: bin folder not found.
    pause
    goto menu
)

pushd "%BIN_PATH%"
for /f "tokens=1,2,3 delims=|" %%A in ('powershell -NoProfile -Command "foreach ($item in @(@{Name='ACTIVE_DISCORD_UDP.bin'; Label='ACTIVE_DISCORD'},@{Name='ACTIVE_GAME_UDP.bin'; Label='ACTIVE_GAME'})) { if (Test-Path -LiteralPath $item.Name) { Write-Output ($item.Label + [char]124 + $item.Label + [char]124 + (Get-FileHash -LiteralPath $item.Name -Algorithm SHA256).Hash) } }; $files = @(Get-ChildItem -LiteralPath . -File -Filter '*.bin'); foreach ($file in $files) { if ($file.BaseName -notlike 'ACTIVE_*') { Write-Output ('FAKE' + [char]124 + $file.BaseName + [char]124 + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) } }"') do (
    if "%%A"=="ACTIVE_DISCORD" (
        set "discord_hash=%%C"
    ) else if "%%A"=="ACTIVE_GAME" (
        set "game_hash=%%C"
    ) else if "%%A"=="FAKE" (
        set /a fake_count+=1
        set "fake_file!fake_count!=%BIN_PATH%%%B.bin"
        set "fake_name!fake_count!=%%B"
        set "fake_hash!fake_count!=%%C"
    )
)
popd

if !fake_count! EQU 0 (
    echo No .bin files were found in the bin folder.
    pause
    goto menu
)

for /l %%N in (1,1,!fake_count!) do (
    if defined discord_hash if /i "!fake_hash%%N!"=="!discord_hash!" set "current_discord_fake=!fake_name%%N!"
    if defined game_hash if /i "!fake_hash%%N!"=="!game_hash!" set "current_game_fake=!fake_name%%N!"
)

:replace_active_fakes_prompt
echo.
echo Enter the fake type number and the fake file number to replace it with.
echo Example: 1 4 (replaces Discord UDP with fake file under number 4)
echo          2 1 (replaces GameFilter UDP with fake file under number 1)
echo.
echo Press ENTER or 0 to return.
echo.
echo   ----------------------------------------
echo.
echo Fake types:
echo   1. Discord UDP     (current: !current_discord_fake!)
echo   2. GameFilter UDP  (current: !current_game_fake!)
echo.
echo Fake files:
for /l %%N in (1,1,!fake_count!) do echo   %%N. !fake_name%%N!
echo.

set "replace_choice="
set /p "replace_choice=Enter choice: "
if not defined replace_choice goto menu
if "!replace_choice!"=="0" goto menu

set "active_file="
set "fake_type="
set "fake_number="
for /f "tokens=1,2" %%A in ("!replace_choice!") do (
    set "fake_type=%%A"
    set "fake_number=%%B"
)

if "!fake_type!"=="1" (
    set "active_file=%BIN_PATH%ACTIVE_DISCORD_UDP.bin"
) else if "!fake_type!"=="2" (
    set "active_file=%BIN_PATH%ACTIVE_GAME_UDP.bin"
) else (
    echo Invalid fake type.
    pause
    cls
    goto replace_active_fakes_prompt
)

set "source_file="
for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" set "source_file=!fake_file%%N!"
if not defined source_file (
    echo Invalid fake file number.
    pause
    cls
    goto replace_active_fakes_prompt
)

del /f /q "!active_file!" >nul 2>&1
copy /y "!source_file!" "!active_file!" >nul
if errorlevel 1 (
    echo Failed to replace the active fake file.
) else (
    echo Active fake file replaced successfully.
    for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" (
        if "!fake_type!"=="1" set "current_discord_fake=!fake_name%%N!"
        if "!fake_type!"=="2" set "current_game_fake=!fake_name%%N!"
    )
)
pause
cls
goto replace_active_fakes_prompt


:: IPSET SWITCH =======================
:ipset_switch_status
set "listFile=%~dp0lists\ipset-all.txt"
set "IPsetStatus=invalid (reset to none)"
if not exist "%listFile%" exit /b
for /f %%i in ('type "%listFile%" 2^>nul ^| find /c /v ""') do set "lineCount=%%i"
if !lineCount!==0 exit /b
findstr /X /C:"203.0.113.113/32" "%listFile%" >nul
if not errorlevel 1 (
    if !lineCount!==1 (set "IPsetStatus=none") else set "IPsetStatus=loaded"
) else (
    set "IPsetStatus=loaded"
)
exit /b

:ipset_switch
cls
chcp 65001 > nul
echo IPSet has only none and loaded modes in this build. Empty ANY mode is disabled.
call :reviewed_support SwitchIpSet
pause
goto menu


:: IPSET UPDATE =======================
:ipset_update
cls
chcp 65001 > nul
echo Updating from the official HTTPS source with strict validation.
echo If IPSet is disabled, only the backup is updated; filtering remains disabled.
call :reviewed_support UpdateIpSet
if errorlevel 1 echo Update failed. The active file was not replaced by an invalid download.
pause
goto menu


:: HOSTS UPDATE =======================
:hosts_update
cls
chcp 65001 > nul
echo Windows hosts is not downloaded, edited or replaced by this build.
echo Review any hosts changes manually if a separate diagnosis requires them.
echo Official reference: https://github.com/Flowseal/zapret-discord-youtube/blob/1.10.4/.service/hosts
pause
goto menu


:: RUN TESTS =============================
:run_tests
cls
chcp 65001 > nul
echo Running file and IPSet checks only. No strategy processes or network requests are started.
call "%~dp0CHECK.cmd"
goto menu


:: Get strategy name
:get_strategy_name
set "CurrentStrategy="
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do set "CurrentStrategy=Strategy: %%B"
exit /b


:: Utility functions


:PrintGreen
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Green"
exit /b

:PrintRed
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Red"
exit /b

:PrintYellow
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Yellow"
exit /b

:check_command
where %1 >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] %1 not found in PATH
    echo Fix your PATH variable with instructions here https://github.com/Flowseal/zapret-discord-youtube/issues/7490
    pause
    exit /b 1
)
exit /b 0

:check_extracted
set "extracted=1"

if not exist "%~dp0bin\" set "extracted=0"

if "%extracted%"=="0" (
    echo Zapret must be extracted from archive first or bin folder not found for some reason
    pause
    exit /b 1
)
exit /b 0


:: REVIEWED SUPPORT: explicit paths and environment data, never interpolated PowerShell code
:reviewed_preflight
call :reviewed_support Preflight
exit /b %errorlevel%

:reviewed_check_files
call :reviewed_support Validate
exit /b %errorlevel%

:reviewed_support
setlocal DisableDelayedExpansion
set "ZAPRET_REVIEW_ROOT=%~dp0"
set "ZAPRET_REVIEW_MODE=%~1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';try{$p=Join-Path $env:ZAPRET_REVIEW_ROOT 'utils/reviewed-support.ps1';$s=[scriptblock]::Create([IO.File]::ReadAllText($p));& $s -Root $env:ZAPRET_REVIEW_ROOT -Mode $env:ZAPRET_REVIEW_MODE}catch{Write-Host 'Reviewed support failed to load. Extract the full archive again.' -ForegroundColor Red;exit 1}"
set "reviewed_result=%errorlevel%"
endlocal & exit /b %reviewed_result%
