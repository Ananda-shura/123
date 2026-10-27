param([Parameter(Mandatory=$true)][string]$Root,[switch]$ValidateOnly,[switch]$PrintProfiles,[switch]$PrintExpandedProfiles)
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


$current=$null

function Convert-TelegramCidrText {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw 'Telegram CIDR list is empty.'
    }
    if ($Text.Length -gt 65536) {
        throw 'Telegram CIDR response is too large.'
    }
    $Text = $Text.TrimStart([char]0xFEFF)
    $lines = @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($lines.Count -lt 1 -or $lines.Count -gt 64) {
        throw 'Telegram CIDR list must contain between 1 and 64 networks.'
    }

    function Get-TgIpv4Number([byte[]]$Bytes) {
        return (([uint64]$Bytes[0] -shl 24) -bor
            ([uint64]$Bytes[1] -shl 16) -bor
            ([uint64]$Bytes[2] -shl 8) -bor [uint64]$Bytes[3])
    }

    # Check overlap, not just the first address of an input network. A public
    # /16 containing a documentation /24 must be rejected too.
    $blocked = @(
        '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
        '169.254.0.0/16', '172.16.0.0/12', '192.0.0.0/24',
        '192.0.2.0/24', '192.88.99.0/24', '192.168.0.0/16',
        '198.18.0.0/15', '198.51.100.0/24', '203.0.113.0/24',
        '224.0.0.0/4', '240.0.0.0/4'
    ) | ForEach-Object {
        $parts = $_.Split('/')
        $first = Get-TgIpv4Number ([Net.IPAddress]::Parse($parts[0]).GetAddressBytes())
        $size = [uint64][Math]::Pow(2, 32 - [int]$parts[1])
        [pscustomobject]@{ First = $first; Last = $first + $size - 1 }
    }

    $result = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $lines) {
        if ($line -notmatch '^([0-9A-Fa-f:.]+)/((?:0|[1-9][0-9]{0,2}))$') {
            throw 'Telegram CIDR response contains a malformed network.'
        }
        $addressText = $Matches[1]
        $prefix = [int]$Matches[2]
        $address = [Net.IPAddress]::None
        if (-not [Net.IPAddress]::TryParse($addressText, [ref]$address)) {
            throw 'Telegram CIDR response contains an invalid address.'
        }
        $bytes = $address.GetAddressBytes()
        $ipv4 = $address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
        if ($ipv4) {
            if ($prefix -lt 16 -or $prefix -gt 32) {
                throw 'Telegram IPv4 prefix must be between /16 and /32.'
            }
            if ($addressText -notmatch '^[0-9]{1,3}(?:\.[0-9]{1,3}){3}$' -or
                $addressText -cne $address.ToString()) {
                throw 'Telegram IPv4 address must use canonical dotted decimal.'
            }
            $bits = 32
        } elseif ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
            if ($prefix -lt 32 -or $prefix -gt 128) {
                throw 'Telegram IPv6 prefix must be between /32 and /128.'
            }
            if (($bytes[0] -band 0xE0) -ne 0x20) {
                throw 'Telegram IPv6 address is outside global 2000::/3 space.'
            }
            # RFC 3849 and RFC 9637 documentation allocations.
            if (($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
                 $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8) -or
                ($bytes[0] -eq 0x3F -and $bytes[1] -eq 0xFF -and
                 ($bytes[2] -band 0xF0) -eq 0)) {
                throw 'Telegram IPv6 address is a documentation allocation.'
            }
            $bits = 128
        } else {
            throw 'Telegram CIDR address family is unsupported.'
        }

        for ($bit = $prefix; $bit -lt $bits; $bit++) {
            $index = [int][Math]::Floor($bit / 8)
            $mask = 1 -shl (7 - ($bit % 8))
            if (($bytes[$index] -band $mask) -ne 0) {
                throw 'Telegram CIDR contains host bits; network address required.'
            }
        }
        if ($ipv4) {
            $first = Get-TgIpv4Number $bytes
            $last = $first + [uint64][Math]::Pow(2, 32 - $prefix) - 1
            foreach ($range in $blocked) {
                if ($first -le $range.Last -and $last -ge $range.First) {
                    throw 'Telegram IPv4 network overlaps non-public address space.'
                }
            }
        }
        $canonical = $address.ToString().ToLowerInvariant() + '/' + $prefix
        if ($seen.Add($canonical)) {
            $null = $result.Add($canonical)
        }
    }
    # Standard PowerShell pipeline return; callers use @(...) to retain an array
    # for both single-network and multiple-network responses.
    return $result.ToArray()
}

function Get-TlsFlags($Profile) {
    $index=[Array]::IndexOf([object[]]$Profile.Arguments,'--ip-id=zero')
    if($index -lt 0){throw 'TLS flags missing'}
    @($Profile.Arguments[($index+1)..($Profile.Arguments.Count-1)])
}

function Get-CombinedProfile($Youtube,$OpenAI,$Telegram,[string]$Directory,[string]$TelegramSet) {
    if([string]::IsNullOrWhiteSpace($TelegramSet) -or -not (Test-Path -LiteralPath $TelegramSet -PathType Leaf)){throw 'Missing Telegram IPSet'}
    $validated=@(Convert-TelegramCidrText ([IO.File]::ReadAllText($TelegramSet)))
    if(-not $validated.Count){throw 'Empty Telegram IPSet'}
    $q=[char]34
    $args=@($Youtube.Arguments)
    $hasProfiles=$args.Count -gt 2
    $exclude=Join-Path $Directory 'lists/list-exclude.txt'
    $extra=Join-Path $Directory 'lists/list-services-web.txt'
    $openaiList=Join-Path $Directory 'lists/list-openai.txt'
    $telegramList=Join-Path $Directory 'lists/list-telegram-web.txt'
    $quic=Join-Path $Directory 'bin/quic_initial_www_google_com.bin'
    if($hasProfiles){$args+='--new'}
    $args+=@('--filter-udp=443',('--hostlist='+$q+$extra+$q),('--hostlist-exclude='+$q+$exclude+$q),'--dpi-desync=fake','--dpi-desync-repeats=6',('--dpi-desync-fake-quic='+$q+$quic+$q),'--new')
    $args+=@('--filter-tcp=443',('--hostlist='+$q+$openaiList+$q),('--hostlist-exclude='+$q+$exclude+$q),'--ip-id=zero')
    $args+=@(Get-TlsFlags $OpenAI)
    $args+='--new'
    $args+=@('--filter-tcp=443',('--hostlist='+$q+$telegramList+$q),('--hostlist-exclude='+$q+$exclude+$q),'--ip-id=zero')
    $args+=@(Get-TlsFlags $Telegram)
    $args+='--new'
    $args+=@('--filter-tcp=443','--filter-l7=unknown',('--ipset='+$q+$TelegramSet+$q),'--dpi-desync=multisplit','--dpi-desync-split-pos=1','--dpi-desync-any-protocol=1','--dpi-desync-cutoff=n3')
    [pscustomobject]@{Name=($Youtube.Name+'_OAI_'+$OpenAI.Name+'_TG_'+$Telegram.Name);Arguments=$args}
}

function Invoke-ServiceHttps([string]$Url,[switch]$Body) {
    if($Url -notmatch '^https://'){throw 'Only verified HTTPS is supported'}
    $p=New-Object Diagnostics.Process
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:SystemRoot 'System32/curl.exe'
    $q=[char]34
    $info.Arguments='--disable --silent --show-error --http1.1 --max-time 12 --connect-timeout 7 --proto =https --proto-redir =https '
    if($Body){$info.Arguments+='--fail --max-filesize 65536 '}
    else{$info.Arguments+='--output NUL --write-out '+$q+'http=%{http_code};bytes=%{size_download};total=%{time_total}'+$q+' '}
    $info.Arguments+=$q+$Url+$q
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p.StartInfo=$info
    try {
        $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(16000)){$p.Kill();$p.WaitForExit()}
        $text=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
        if($env:USERPROFILE){$err=$err.Replace($env:USERPROFILE,'[profile]')}
        $err=$err -replace '(https?://)[^/@\s]+@','$1[redacted]@'
        $http=0;if(-not $Body -and $text -match 'http=(\d+)'){$http=[int]$Matches[1]}
        [pscustomobject]@{Url=$Url;ExitCode=$p.ExitCode;HttpCode=$http;ResponseReached=($p.ExitCode -eq 0 -and $http -ge 100 -and $http -le 599);AppVerified=$false;Output=if($Body){$text}else{''};Metrics=if($Body){''}else{$text};Error=$err}
    } catch {[pscustomobject]@{Url=$Url;ExitCode=-1;HttpCode=0;ResponseReached=$false;AppVerified=$false;Output='';Error=$_.CategoryInfo.Reason}}
    finally{$p.Dispose()}
}

function Start-Tracked($Profile) {
    $sequence.Value++
    $slug=$Profile.Name -replace '[^A-Za-z0-9_-]','_'
    if($slug.Length -gt 90){$slug=$slug.Substring(0,90)}
    $name=$sequence.Value.ToString('D2')+'-'+$slug
    $p=Start-Process -FilePath $exe -ArgumentList ($Profile.Arguments -join ' ') -WorkingDirectory $bin -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $run ($name+'-stdout.log')) -RedirectStandardError (Join-Path $run ($name+'-stderr.log'))
    try{$job.Add($p)}catch{try{Stop-Owned $p}finally{throw 'AUTOPICK_JOB_ASSIGN_FAILED'}}
    Start-Sleep -Milliseconds 1000
    return $p
}

function Restart-Combined($Profile) {
    if($null -ne $current.Process){Stop-Owned $current.Process;$current.Process=$null}
    $current.Process=Start-Tracked $Profile
    if($current.Process.HasExited){throw 'Combined profile exited during startup'}
}

function Select-ServiceMethod([string]$Service,[string]$Url,$Methods,$Youtube,$OpenAI,$Telegram) {
    foreach($method in $Methods) {
        $keep=$false
        $entry=[ordered]@{Service=$Service;Method=$method.Name;Result=$null;Error=$null}
        try {
            $oa=$OpenAI;$tg=$Telegram
            if($Service -eq 'ChatGPT'){$oa=$method}else{$tg=$method}
            Write-Host ('Проверка '+$Service+': '+$method.Name)
            Restart-Combined (Get-CombinedProfile $Youtube $oa $tg $Root $telegramSet)
            $entry.Result=Invoke-ServiceHttps $Url
            if($entry.Result.ResponseReached -and -not $current.Process.HasExited) {
                $keep=$true
                return $method
            }
        } catch {
            $entry.Error=$_.Exception.Message.Replace($Root,'[folder]')
            if($_.Exception.Message -eq 'AUTOPICK_JOB_ASSIGN_FAILED'){throw}
        }finally{
            $report.WebAttempts+=@([pscustomobject]$entry)
            if(-not $keep -and $current.Process){Stop-Owned $current.Process;$current.Process=$null}
        }
    }
    return $null
}

function Test-ControlRegression($Before,$After) {
    if($Before.ResponseReached -and -not $After.ResponseReached){return $true}
    $beforePage=$Before.ResponseReached -and $Before.HttpCode -ge 200 -and $Before.HttpCode -lt 400
    $afterPage=$After.ResponseReached -and $After.HttpCode -ge 200 -and $After.HttpCode -lt 400
    return [bool]($beforePage -and -not $afterPage)
}

function Refresh-TelegramSet {
    $fetch=Invoke-ServiceHttps 'https://core.telegram.org/resources/cidr.txt' -Body
    if($fetch.ExitCode -ne 0){return [pscustomobject]@{Loaded=$false;Reason='Official HTTPS source unavailable';ExitCode=$fetch.ExitCode}}
    try {
        $networks=@(Convert-TelegramCidrText $fetch.Output)
        $state=Join-Path $Root 'state';$null=New-Item -ItemType Directory -Path $state -Force
        $name='telegram-'+[guid]::NewGuid().ToString('N')+'.txt'
        $temp=Join-Path $state ($name+'.tmp');$final=Join-Path $state $name
        [IO.File]::WriteAllText($temp,($networks -join "`r`n")+"`r`n",[Text.Encoding]::ASCII)
        Move-Item -LiteralPath $temp -Destination $final
        [pscustomobject]@{Loaded=$true;Path=$final;Count=$networks.Count;Source='https://core.telegram.org/resources/cidr.txt';Sha256=(Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash}
    } catch {[pscustomobject]@{Loaded=$false;Reason='Official response failed strict CIDR validation';ExitCode=$fetch.ExitCode}}
}

function Get-TelegramConnections {
    try {
        $tg=@(Get-Process -Name Telegram -ErrorAction SilentlyContinue)
        foreach($p in $tg){Get-NetTCPConnection -OwningProcess $p.Id -ErrorAction SilentlyContinue|Where-Object{$_.RemotePort -gt 0}|Select-Object RemotePort,State}
    }catch{ }
}

try {
    $profiles=@(Get-Profiles $Root)
    $telegramSet=Join-Path $Root 'lists/telegram-bootstrap-ipset.txt'
    if($PrintProfiles){$profiles|ConvertTo-Json -Depth 5;exit 0}
    if($PrintExpandedProfiles){@(foreach($p in $profiles){Get-CombinedProfile $profiles[0] $p $profiles[0] $Root $telegramSet})|ConvertTo-Json -Depth 5;exit 0}
    $manifest=Get-Content -LiteralPath (Join-Path $Root 'ORIGINAL-SHA256.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $entries=@($manifest.PSObject.Properties|Where-Object{$_.Name -like 'bin/*'})
    if($entries.Count -ne 27){throw 'Повреждён список контрольных сумм.'}
    foreach($entry in $entries){if((Get-FileHash -LiteralPath (Join-Path $Root $entry.Name) -Algorithm SHA256).Hash -ne $entry.Value){throw ('Повреждён файл: '+$entry.Name)}}
    $support=Get-Content -LiteralPath (Join-Path $Root 'expanded/SUPPORT-SHA256.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($entry in $support.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $Root $entry.Name) -Algorithm SHA256).Hash -ne $entry.Value){throw ('Повреждён файл: '+$entry.Name)}}
    foreach($name in @('list-youtube-optimized.txt','list-openai.txt','list-telegram-web.txt','list-services-web.txt')) {
        $names=@(Get-Content -LiteralPath (Join-Path $Root ('lists/'+$name))|ForEach-Object{$_.Trim()}|Where-Object{$_ -and -not $_.StartsWith('#')})
        if(-not $names.Count){throw ('Пустой список: '+$name)}
        foreach($hostName in $names){if($hostName -notmatch '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$' -or $hostName.Contains('..')){throw 'Некорректный домен.'}}
    }
    $bootstrap=@(Convert-TelegramCidrText ([IO.File]::ReadAllText($telegramSet)))
    if($bootstrap.Count -ne 11){throw 'Повреждён резервный список Telegram.'}
    if($ValidateOnly){Write-Output 'FILES_OK';exit 0}
    if($env:OS -ne 'Windows_NT' -or ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'AMD64')){throw 'Требуется Windows x64.'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Start-Process -FilePath (Join-Path $Root 'START.cmd') -Verb RunAs;exit 0}
    $mutex=New-Object Threading.Mutex($false,'Global\ZapretYoutubeOptimized1104')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Закройте прежнее окно START.cmd и повторите запуск.'}
    $other=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -in @('winws.exe','winws2.exe','goodbyedpi.exe')})
    if($other.Count){throw 'Работает другой обходчик. Этот запуск не завершает чужие процессы.'}
    $services=@(Get-Service -Name zapret,GoodbyeDPI,discordfix_zapret,winws1,winws2 -ErrorAction SilentlyContinue|Where-Object{$_.Status -ne 'Stopped'})
    if($services.Count){throw 'Активна служба обходчика. Этот запуск не останавливает службы.'}
    $run=Join-Path $Root ('logs/expanded-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    $null=New-Item -ItemType Directory -Path $run -Force
    $current=@{Process=$null};$sequence=@{Value=0}
    $report=[ordered]@{Version=3;TimeUtc=[datetime]::UtcNow.ToString('o');Note='HTTP responses do not prove login, regional availability, Telegram MTProto or video. No route/DNS/proxy/service/global-policy changes.';Candidates=@();WebAttempts=@();NativeTelegramVerified=$false;Selected=$null}
    Write-Host 'Проверяю YouTube, ChatGPT и Telegram. Сначала сохраняю доступность YouTube.'
    $report.ControlsBefore=@(foreach($url in @('https://ya.ru/','https://store.steampowered.com/')){Invoke-ServiceHttps $url})
    Add-Type -Path (Join-Path $Root 'expanded/WindowsJob.cs');$job=New-Object ZapretOwnedJob
    $report.WithoutZapret=Invoke-Https ''
    if($report.WithoutZapret.Success){$ytChoice=[pscustomobject]@{Name='NO-YOUTUBE-DESYNC';Arguments=@('--wf-tcp=443','--wf-udp=443')}}
    else{
        $yt=@([Net.Dns]::GetHostAddresses('www.youtube.com')|Where-Object{$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork}|ForEach-Object{$_.ToString()}|Select-Object -Unique -First 8)
        $report.RawTcp=@(Test-Tcp $yt)
        $reachable=@($report.RawTcp|Where-Object{$_.State -eq 'Connected'})
        if(-not $reachable.Count){throw 'TCP к YouTube не прошёл. Пришлите RESULT.txt.'}
        $fixedIp=$reachable[0].Ip
        $selected=Select-Profile $profiles {param($p) Start-Tracked $p} {param($mode) if($mode -eq 'fixed'){Invoke-Https $fixedIp}else{Invoke-Https ''}} {param($p) Stop-Owned $p}
        if($null -eq $selected){throw 'Не удалось повторно подобрать YouTube. Вернитесь к сохранённой рабочей папке и пришлите RESULT.txt.'}
        $ytChoice=$selected.Profile;$current.Process=$selected.Process
    }
    $report.YoutubeMethod=$ytChoice.Name
    $preferred=@($profiles|Where-Object{$_.Name -eq $ytChoice.Name})
    if(-not $preferred.Count){$preferred=@($profiles[0])}
    $order=@($preferred)+@($profiles|Where-Object{$_.Name -ne $preferred[0].Name})
    $oaChoice=$preferred[0];$tgChoice=$preferred[0]
    $chosen=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $order $ytChoice $oaChoice $tgChoice
    if($null -ne $chosen){$oaChoice=$chosen}else{$report.ChatGPTWarning='No HTTP response reached; application access is unverified'}
    $chosen=Select-ServiceMethod 'TelegramWeb' 'https://core.telegram.org/' $order $ytChoice $oaChoice $tgChoice
    if($null -ne $chosen){$tgChoice=$chosen}else{$report.TelegramWebWarning='No HTTP response reached; native application access is unverified'}
    Restart-Combined (Get-CombinedProfile $ytChoice $oaChoice $tgChoice $Root $telegramSet)
    $refresh=Refresh-TelegramSet
    if($refresh.Loaded){
        $telegramSet=$refresh.Path
        $report.TelegramIpSource=[pscustomobject]@{Official=$true;Count=$refresh.Count;Source=$refresh.Source;Sha256=$refresh.Sha256}
        Restart-Combined (Get-CombinedProfile $ytChoice $oaChoice $tgChoice $Root $telegramSet)
    }else{$report.TelegramIpSource=[pscustomobject]@{Official=$false;Count=11;Reason=$refresh.Reason;Scope='Bootstrap endpoints only; not complete DC/media coverage'}}
    $report.YoutubeAfter=Invoke-Https ''
    $report.ChatGPTAfter=Invoke-ServiceHttps 'https://chatgpt.com/'
    $report.TelegramWebAfter=Invoke-ServiceHttps 'https://web.telegram.org/'
    $report.ControlsAfter=@(foreach($url in @('https://ya.ru/','https://store.steampowered.com/')){Invoke-ServiceHttps $url})
    $regression=$false
    foreach($before in $report.ControlsBefore){
        $after=@($report.ControlsAfter|Where-Object{$_.Url -eq $before.Url})|Select-Object -First 1
        if(Test-ControlRegression $before $after){$repeat=Invoke-ServiceHttps $before.Url;if(Test-ControlRegression $before $repeat){$regression=$true}}
    }
    if(($report.WithoutZapret.Success -or $ytChoice.Name -ne 'NO-YOUTUBE-DESYNC') -and -not $report.YoutubeAfter.Success){$regression=$true}
    if($regression){
        if($ytChoice.Name -eq 'NO-YOUTUBE-DESYNC'){if($current.Process){Stop-Owned $current.Process;$current.Process=$null}}
        else{Restart-Combined $ytChoice}
        $report.Selected='YOUTUBE_ONLY_FALLBACK';$report.Warning='Expanded checks regressed; only previous YouTube strategy retained';Save-Report
        Write-Host 'Расширение не прошло контрольную проверку. Сохранён только профиль YouTube. Пришлите RESULT.txt.' -ForegroundColor Yellow
    }else{
        $report.Selected='EXPANDED';$report.OpenAiMethod=$oaChoice.Name;$report.TelegramWebMethod=$tgChoice.Name
        Write-Host ('YouTube: '+$ytChoice.Name+'; проверка страницы пройдена.') -ForegroundColor Green
        if($report.ChatGPTAfter.ResponseReached){Write-Host ('ChatGPT: получен ответ HTTP '+$report.ChatGPTAfter.HttpCode+'. Проверьте вход в браузере.')}else{Write-Host 'ChatGPT: соединение не установилось. Пришлите RESULT.txt.' -ForegroundColor Yellow}
        Write-Host 'Откройте ChatGPT в браузере и Telegram Desktop. Вход, MTProto и видео ещё нужно проверить.'
        if($report.ChatGPTAfter.HttpCode -eq 403){Write-Host 'ChatGPT ответил HTTP 403: возможна проверка браузера или ограничение сервиса/региона. Это не подтверждение работы чата.' -ForegroundColor Yellow}
        if(-not $report.TelegramIpSource.Official){Write-Host 'Полный список Telegram не получен; используется ограниченный резервный список серверов.' -ForegroundColor Yellow}
    }
    $report.TelegramConnections=@(Get-TelegramConnections);Save-Report
    Write-Host 'Оставьте окно открытым. Для остановки закройте его или нажмите Ctrl+C.'
    if($current.Process){while(-not $current.Process.HasExited){Start-Sleep -Milliseconds 500}}
}catch{
    $message=$_.Exception.Message.Replace($Root,'[folder]')
    if($env:USERPROFILE){$message=$message.Replace($env:USERPROFILE,'[profile]')}
    $report.Error=$message;Save-Report
    Write-Host $message -ForegroundColor Red
    if($run){Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/notepad.exe') -ArgumentList ($q+(Join-Path $run 'RESULT.txt')+$q)}
    exit 1
}finally{
    try{if($current -and $null -ne $current.Process){Stop-Owned $current.Process}}
    finally{try{if($null -ne $job){$job.Dispose()}}finally{if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}}
}
