param([Parameter(Mandatory=$true)][string]$Root,[switch]$ValidateOnly,[switch]$PrintProfiles)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
$q=[char]34
$bin=Join-Path $Root 'bin'
$exe=Join-Path $bin 'winws.exe'
$list=Join-Path $Root 'lists/list-youtube-optimized.txt'
$mutex=$null
$locked=$false
$job=$null
$owned=$null
$run=$null
$report=[ordered]@{Version=2;TimeUtc=[datetime]::UtcNow.ToString('o');Note='HTTP tests are not browser/QUIC/video validation. No DNS, service, firewall or global policy changes.';RawTcp=@();Candidates=@();Selected=$null}

function Get-Profiles([string]$Directory) {
    $q=[char]34
    $hostfile=Join-Path $Directory 'lists/list-youtube-optimized.txt'
    $pattern=Join-Path $Directory 'bin/tls_clienthello_www_google_com.bin'
    $quic=Join-Path $Directory 'bin/quic_initial_www_google_com.bin'
    $common=@('--wf-tcp=443','--wf-udp=443','--filter-udp=443',('--hostlist='+$q+$hostfile+$q),'--dpi-desync=fake','--dpi-desync-repeats=6',('--dpi-desync-fake-quic='+$q+$quic+$q),'--new','--filter-tcp=443',('--hostlist='+$q+$hostfile+$q),'--ip-id=zero')
    @(
        [pscustomobject]@{Name='BASE-MULTISPLIT';Arguments=$common+@('--dpi-desync=multisplit','--dpi-desync-split-seqovl=681','--dpi-desync-split-pos=1',('--dpi-desync-split-seqovl-pattern='+$q+$pattern+$q))},
        [pscustomobject]@{Name='FAKE-TLS-AUTO-ALT';Arguments=$common+@('--dpi-desync=fake,fakedsplit','--dpi-desync-split-pos=1','--dpi-desync-fooling=badseq','--dpi-desync-badseq-increment=2','--dpi-desync-repeats=8','--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com')},
        [pscustomobject]@{Name='ALT8-FAKE';Arguments=$common+@('--dpi-desync=fake','--dpi-desync-fake-tls-mod=none','--dpi-desync-repeats=6','--dpi-desync-fooling=badseq','--dpi-desync-badseq-increment=2')},
        [pscustomobject]@{Name='ALT7-SNI-SPLIT';Arguments=$common+@('--dpi-desync=multisplit','--dpi-desync-split-pos=2,sniext+1','--dpi-desync-split-seqovl=679',('--dpi-desync-split-seqovl-pattern='+$q+$pattern+$q))}
    )
}

function Test-Tcp([string[]]$Addresses,[int]$Timeout=4000,[int]$Port=443) {
    $pending=@(foreach($ip in $Addresses) {
        $c=New-Object Net.Sockets.TcpClient
        $watch=[Diagnostics.Stopwatch]::StartNew()
        try { $t=$c.ConnectAsync($ip,$Port);[pscustomobject]@{Ip=$ip;Client=$c;Task=$t;Watch=$watch} }
        catch { $c.Dispose();[pscustomobject]@{Ip=$ip;Client=$null;Task=$null;Watch=$watch;Failure=$_.CategoryInfo.Reason} }
    })
    foreach($p in $pending) {
        $state='Timeout'
        try {
            if($null -eq $p.Task) {$state='ConnectError'}
            elseif($p.Task.IsCompleted -or $p.Task.Wait([Math]::Max(1,$Timeout-[int]$p.Watch.ElapsedMilliseconds))) {
                $null=$p.Task.GetAwaiter().GetResult();$state='Connected'
            }
        } catch { $state=$_.Exception.GetBaseException().GetType().Name }
        finally {if($null -ne $p.Client){$p.Client.Dispose()}}
        [pscustomobject]@{Ip=$p.Ip;State=$state;ElapsedMs=$p.Watch.ElapsedMilliseconds}
    }
}

function Invoke-Https([string]$Address) {
    $p=New-Object Diagnostics.Process
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:SystemRoot 'System32/curl.exe'
    $format='http=%{http_code};bytes=%{size_download};total=%{time_total}'
    $info.Arguments='--disable --silent --show-error --http1.1 --location --max-redirs 3 --max-time 14 --connect-timeout 8 --proto =https --proto-redir =https --output NUL --write-out '+$q+$format+$q+' '
    if($Address){$info.Arguments+='--resolve www.youtube.com:443:'+$Address+' '}
    $info.Arguments+='https://www.youtube.com/'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p.StartInfo=$info
    try {
        $null=$p.Start()
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(18000)){$p.Kill();$p.WaitForExit()}
        $text=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
        if($env:USERPROFILE){$err=$err.Replace($env:USERPROFILE,'[profile]')}
        $err=$err -replace '(https?://)[^/@\s]+@','$1[redacted]@'
        $http=0;$bytes=0L
        if($text -match 'http=(\d+)'){$http=[int]$Matches[1]}
        if($text -match 'bytes=(\d+)'){$bytes=[long]$Matches[1]}
        [pscustomobject]@{ExitCode=$p.ExitCode;HttpCode=$http;Bytes=$bytes;Success=($p.ExitCode -eq 0 -and $http -eq 200 -and $bytes -ge 1024);Metrics=$text;Error=$err}
    } catch {[pscustomobject]@{ExitCode=-1;HttpCode=0;Bytes=0;Success=$false;Error=$_.CategoryInfo.Reason}}
    finally {$p.Dispose()}
}

function Stop-Owned($Process) {
    if($null -ne $Process) {
        if(-not $Process.HasExited){$Process.Kill();if(-not $Process.WaitForExit(5000)){throw 'Не удалось завершить собственный тестовый процесс. Проверка остановлена.'}}
        $Process.Dispose()
    }
}

function Select-Profile($Profiles,[scriptblock]$Start,[scriptblock]$Probe,[scriptblock]$Stop) {
    foreach($candidate in $Profiles) {
        $process=$null;$keep=$false
        $entry=[ordered]@{Profile=$candidate.Name;FixedAddress=$null;NormalDns=$null;Passed=$false;Error=$null}
        try {
            Write-Host ('Проверка: '+$candidate.Name)
            $process=& $Start $candidate
            if($process.HasExited){throw 'Тестовый winws завершился при запуске.'}
            $entry.FixedAddress=& $Probe 'fixed'
            if($entry.FixedAddress.Success) {
                $entry.NormalDns=& $Probe 'normal'
                if($entry.NormalDns.Success){
                    if($process.HasExited){throw 'Тестовый процесс завершился во время проверки.'}
                    $entry.Passed=$true;$keep=$true
                }
            }
        } catch {
            $entry.Error=$_.Exception.Message.Replace($Root,'[folder]')
            if($_.Exception.Message -eq 'AUTOPICK_JOB_ASSIGN_FAILED'){throw}
        }
        finally {
            $report.Candidates+=@([pscustomobject]$entry)
            if(-not $keep -and $null -ne $process){& $Stop $process}
        }
        if($keep){return [pscustomobject]@{Profile=$candidate;Process=$process}}
    }
    return $null
}

function Save-Report {
    if($run){$report|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $run 'RESULT.txt') -Encoding UTF8}
}

function Get-RouteSummary([string]$Address) {
    try {
        $route=@(Find-NetRoute -RemoteIPAddress $Address|Where-Object{$_.PSObject.Properties['DestinationPrefix']})|Select-Object -First 1
        $adapter=@(Get-NetAdapter -IncludeHidden|Where-Object{$_.ifIndex -eq $route.InterfaceIndex})|Select-Object -First 1
        $kind='Unknown'
        if($adapter.InterfaceDescription -match 'Happ|Wintun|WireGuard|TAP|TUN'){$kind='Tunnel-like'}
        elseif($adapter.HardwareInterface){$kind='Hardware'}
        elseif($adapter.Virtual){$kind='Virtual'}
        [pscustomobject]@{Ip=$Address;InterfaceIndex=$route.InterfaceIndex;DestinationPrefix=$route.DestinationPrefix;AdapterKind=$kind}
    } catch {[pscustomobject]@{Ip=$Address;Error='Route query unavailable'}}
}

try {
    $profiles=@(Get-Profiles $Root)
    if($PrintProfiles){$profiles|ConvertTo-Json -Depth 5;exit 0}
    $manifest=Get-Content -LiteralPath (Join-Path $Root 'ORIGINAL-SHA256.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $entries=@($manifest.PSObject.Properties|Where-Object{$_.Name -like 'bin/*'})
    if($entries.Count -ne 27){throw 'Повреждён список контрольных сумм.'}
    foreach($entry in $entries){if((Get-FileHash -LiteralPath (Join-Path $Root $entry.Name) -Algorithm SHA256).Hash -ne $entry.Value){throw ('Повреждён файл: '+$entry.Name)}}
    $support=Get-Content -LiteralPath (Join-Path $Root 'autopick/SUPPORT-SHA256.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($entry in $support.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $Root $entry.Name) -Algorithm SHA256).Hash -ne $entry.Value){throw ('Повреждён файл подбора: '+$entry.Name)}}
    $names=@(Get-Content -LiteralPath $list|ForEach-Object{$_.Trim()}|Where-Object{$_ -and -not $_.StartsWith('#')})
    if($names.Count -eq 0){throw 'Пустой список доменов. Запуск остановлен.'}
    foreach($name in $names){if($name -notmatch '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$' -or $name.Contains('..')){throw 'Некорректный домен в списке.'}}
    if($ValidateOnly){Write-Output 'FILES_OK';exit 0}
    if($env:OS -ne 'Windows_NT' -or ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'AMD64')){throw 'Требуется Windows x64.'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process -FilePath (Join-Path $Root 'START.cmd') -Verb RunAs;exit 0
    }
    $mutex=New-Object Threading.Mutex($false,'Global\ZapretYoutubeOptimized1104')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Закройте старое окно START.cmd, затем запустите новое.'}
    $other=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -in @('winws.exe','winws2.exe','goodbyedpi.exe')})
    if($other.Count){throw 'Уже работает другой обходчик. Закройте его окно. Этот запуск не завершает чужие процессы.'}
    $services=@(Get-Service -Name zapret,GoodbyeDPI,discordfix_zapret,winws1,winws2 -ErrorAction SilentlyContinue|Where-Object{$_.Status -ne 'Stopped'})
    if($services.Count){throw 'Активна служба обходчика. Этот запуск не останавливает службы.'}
    $run=Join-Path $Root ('logs/autopick-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    $null=New-Item -ItemType Directory -Path $run -Force
    Write-Host 'Проверяю TCP и HTTPS. Настройки Windows и DNS не изменяются.'
    $yt=@([Net.Dns]::GetHostAddresses('www.youtube.com')|Where-Object{$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork}|ForEach-Object{$_.ToString()}|Select-Object -Unique -First 8)
    if(-not $yt.Count){throw 'Не получены IPv4-адреса YouTube.'}
    $control=@()
    try{$control=@([Net.Dns]::GetHostAddresses('www.google.com')|Where-Object{$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork}|ForEach-Object{$_.ToString()}|Select-Object -First 1)}catch{$report.ControlLookupError=$_.CategoryInfo.Reason}
    $report.RawTcp=@(Test-Tcp @($yt+$control|Select-Object -Unique))
    $report.Routes=@(foreach($address in @($yt[0])+$control){Get-RouteSummary $address})
    $reachable=@($report.RawTcp|Where-Object{$_.State -eq 'Connected' -and $yt -contains $_.Ip})
    $report.WithoutZapret=Invoke-Https ''
    if($report.WithoutZapret.Success){
        $report.Selected='NO_FILTER_NEEDED_FOR_HTTPS';Save-Report
        Write-Host 'Без Zapret сайт отвечает HTTP 200. Проверьте браузер; обходчик не запущен.' -ForegroundColor Green
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/notepad.exe') -ArgumentList ($q+(Join-Path $run 'RESULT.txt')+$q)
        exit 0
    }
    if(-not $reachable.Count){throw 'Прямой TCP к адресам YouTube не прошёл. Перебор TLS-стратегий остановлен; пришлите RESULT.txt.'}
    $fixedIp=$reachable[0].Ip
    $report.ComparisonIp=$fixedIp
    Add-Type -Path (Join-Path $Root 'autopick/WindowsJob.cs')
    $job=New-Object ZapretOwnedJob
    $start={param($candidate)
        $stdout=Join-Path $run ($candidate.Name+'-stdout.log');$stderr=Join-Path $run ($candidate.Name+'-stderr.log')
        $p=Start-Process -FilePath $exe -ArgumentList ($candidate.Arguments -join ' ') -WorkingDirectory $bin -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        try{$job.Add($p)}catch{try{Stop-Owned $p}finally{throw 'AUTOPICK_JOB_ASSIGN_FAILED'}}
        Start-Sleep -Milliseconds 1000
        return $p
    }
    $probe={param($mode) if($mode -eq 'fixed'){Invoke-Https $fixedIp}else{Invoke-Https ''}}
    $selected=Select-Profile $profiles $start $probe {param($p) Stop-Owned $p}
    if($null -eq $selected){throw 'Ни один из четырёх вариантов не прошёл HTTPS-проверку. Пришлите RESULT.txt из новой папки logs.'}
    $owned=$selected.Process;$report.Selected=$selected.Profile.Name;Save-Report
    Write-Host ('HTTPS-проверка пройдена: '+$report.Selected) -ForegroundColor Green
    Write-Host 'Теперь откройте YouTube в браузере. Видео и QUIC ещё требуют проверки.'
    Write-Host 'Оставьте окно открытым. Для остановки закройте его или нажмите Ctrl+C.'
    while(-not $owned.HasExited){Start-Sleep -Milliseconds 500}
    $report.SelectedProcessExitCode=$owned.ExitCode;Save-Report
} catch {
    $message=$_.Exception.Message.Replace($Root,'[folder]')
    if($env:USERPROFILE){$message=$message.Replace($env:USERPROFILE,'[profile]')}
    $report.Error=$message;Save-Report
    Write-Host $message -ForegroundColor Red
    if($run){Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/notepad.exe') -ArgumentList ($q+(Join-Path $run 'RESULT.txt')+$q)}
    exit 1
} finally {
    try{if($null -ne $owned){Stop-Owned $owned}}
    finally{
        try{if($null -ne $job){$job.Dispose()}}
        finally{
            if($locked){$mutex.ReleaseMutex()}
            if($null -ne $mutex){$mutex.Dispose()}
        }
    }
}
