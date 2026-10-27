param(
    [Parameter(Mandatory=$true)][string]$Root,
    [ValidateSet('Preflight','Validate','UpdateIpSet','SwitchIpSet','CheckServiceOwner')]
    [string]$Mode='Preflight',
    [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'

function Convert-ReviewedIpSetText {
    param([AllowNull()][AllowEmptyString()][string]$Text,[switch]$AllowSentinel)
    if([string]::IsNullOrWhiteSpace($Text)){throw 'IPSet is empty. Empty IPSet means ANY and is refused.'}
    if([Text.Encoding]::UTF8.GetByteCount($Text) -gt 8388608){throw 'IPSet exceeds 8 MiB.'}
    $lines=@($Text.TrimStart([char]0xFEFF) -split '\r?\n'|ForEach-Object{$_.Trim()}|Where-Object{$_ -and -not $_.StartsWith('#')})
    if($lines.Count -lt 1 -or $lines.Count -gt 100000){throw 'IPSet must contain 1 to 100000 networks.'}
    function Get-ReviewedIpv4Number([byte[]]$Bytes){
        (([uint64]$Bytes[0] -shl 24) -bor ([uint64]$Bytes[1] -shl 16) -bor ([uint64]$Bytes[2] -shl 8) -bor [uint64]$Bytes[3])
    }
    $blocked=@('0.0.0.0/8','10.0.0.0/8','100.64.0.0/10','127.0.0.0/8','169.254.0.0/16','172.16.0.0/12','192.0.0.0/24','192.0.2.0/24','192.88.99.0/24','192.168.0.0/16','198.18.0.0/15','198.51.100.0/24','203.0.113.0/24','224.0.0.0/4','240.0.0.0/4')|ForEach-Object{
        $parts=$_.Split('/');$first=Get-ReviewedIpv4Number ([Net.IPAddress]::Parse($parts[0]).GetAddressBytes())
        [pscustomobject]@{First=$first;Last=$first+[uint64][Math]::Pow(2,32-[int]$parts[1])-1}
    }
    function Test-ReviewedIpv6Overlap([byte[]]$A,[int]$PrefixA,[byte[]]$B,[int]$PrefixB){
        $common=[Math]::Min($PrefixA,$PrefixB);$whole=[int][Math]::Floor($common/8);$partial=$common%8
        for($j=0;$j -lt $whole;$j++){if($A[$j] -ne $B[$j]){return $false}}
        if($partial -ne 0){$mask=(255 -shl (8-$partial)) -band 255;if(($A[$whole] -band $mask) -ne ($B[$whole] -band $mask)){return $false}}
        return $true
    }
    $v6docs=@(
        [pscustomobject]@{Address=[Net.IPAddress]::Parse('2001:db8::');Prefix=32},
        [pscustomobject]@{Address=[Net.IPAddress]::Parse('3fff::');Prefix=20}
    )
    $result=New-Object 'Collections.Generic.List[string]'
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($line in $lines){
        if($AllowSentinel -and $lines.Count -eq 1 -and $line -ceq '203.0.113.113/32'){return @('203.0.113.113/32')}
        if($line -notmatch '^([0-9a-fA-F:.]+)/([1-9][0-9]{0,2})$'){throw 'IPSet contains a malformed or catch-all network.'}
        $textAddress=$Matches[1];$prefix=[int]$Matches[2];$ip=[Net.IPAddress]::None
        if(-not [Net.IPAddress]::TryParse($textAddress,[ref]$ip)){throw 'IPSet contains an invalid address.'}
        $bytes=$ip.GetAddressBytes();$v4=$ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
        if($v4){
            if($prefix -gt 32 -or $textAddress -notmatch '^[0-9]{1,3}(?:\.[0-9]{1,3}){3}$' -or $textAddress -cne $ip.ToString()){throw 'IPSet IPv4 address or prefix is invalid.'}
        }elseif($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
            if($prefix -gt 128 -or ($bytes[0] -band 0xE0) -ne 0x20){throw 'IPSet IPv6 network is not public global space.'}
            foreach($range in $v6docs){if(Test-ReviewedIpv6Overlap $bytes $prefix $range.Address.GetAddressBytes() $range.Prefix){throw 'IPSet overlaps documentation IPv6 space.'}}
        }else{throw 'Unsupported IPSet address family.'}
        $whole=[int][Math]::Floor($prefix/8);$remainder=$prefix%8
        for($i=$whole;$i -lt $bytes.Length;$i++){
            $mask=if($i -eq $whole -and $remainder -ne 0){(1 -shl (8-$remainder))-1}else{255}
            if(($bytes[$i] -band $mask) -ne 0){throw 'IPSet contains host bits; use network addresses.'}
        }
        $canonical=$ip.ToString().ToLowerInvariant()+'/'+$prefix
        if($v4){
            $first=Get-ReviewedIpv4Number $bytes;$last=$first+[uint64][Math]::Pow(2,32-$prefix)-1
            # Exact compatibility entry in the verified official 1.10.4 IPSet catalog.
            # The deprecated 6to4 relay /24 is not an RFC1918 private network; do not
            # generalize this exception to its subprefixes or other reserved space.
            $legacyRelay=$canonical -ceq '192.88.99.0/24'
            if(-not $legacyRelay){foreach($range in $blocked){if($first -le $range.Last -and $last -ge $range.First){throw 'IPSet overlaps private, reserved or documentation IPv4 space.'}}}
        }
        if($seen.Add($canonical)){$null=$result.Add($canonical)}
    }
    $result.ToArray()
}

function Read-ReviewedIpSet([string]$Path,[switch]$AllowSentinel){
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if(-not ($file -is [IO.FileInfo]) -or $file.Length -gt 8388608){throw 'IPSet file is missing or exceeds 8 MiB.'}
    @(Convert-ReviewedIpSetText ([IO.File]::ReadAllText($file.FullName)) -AllowSentinel:$AllowSentinel)
}

function Test-ReviewedFiles([string]$Directory){
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'ORIGINAL-SHA256.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($name in @('bin/winws.exe','bin/WinDivert.dll','bin/WinDivert64.sys','bin/cygwin1.dll')){
        $expected=$manifest.PSObject.Properties[$name].Value
        if($expected -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $Directory $name) -Algorithm SHA256).Hash -ne $expected){throw ('Native file checksum mismatch: '+$name)}
    }
    $null=@(Read-ReviewedIpSet (Join-Path $Directory 'lists/ipset-all.txt') -AllowSentinel)
}

function Test-ReviewedServiceOwner([string]$Directory){
    $service=Get-CimInstance Win32_Service -Filter "Name='zapret'" -ErrorAction Stop
    if($null -eq $service){return}
    $command=[Environment]::ExpandEnvironmentVariables([string]$service.PathName).Trim()
    if($command -match '^"([^"]+)"(?:\s|$)'){$actual=$Matches[1]}
    elseif($command -match '^(\S+)(?:\s|$)'){$actual=$Matches[1]}
    else{throw 'Cannot determine which folder owns the existing zapret service.'}
    $expected=[IO.Path]::GetFullPath((Join-Path $Directory 'bin/winws.exe'))
    if(-not [IO.Path]::GetFullPath($actual).Equals($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'The existing zapret service belongs to another folder. It was not changed.'}
}

function Get-ReviewedOfficialIpSet {
    $p=New-Object Diagnostics.Process;$started=$false
    try{
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=Join-Path $env:SystemRoot 'System32/curl.exe'
        $info.Arguments='--disable --fail --silent --show-error --max-time 25 --connect-timeout 8 --max-filesize 8388608 --proto =https --proto-redir =https -- https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt'
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$p.StartInfo=$info
        $started=$p.Start();if(-not $started){throw 'Official IPSet download could not start.'}
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(29000)){throw 'Official IPSet download timed out.'}
        if(-not $stdout.Wait(3000) -or -not $stderr.Wait(3000)){throw 'Official IPSet response could not be read.'}
        $body=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
        if($p.ExitCode -ne 0){throw 'Verified HTTPS IPSet download failed; the old list was preserved.'}
        @(Convert-ReviewedIpSetText $body)
    }finally{
        if($started){try{if(-not $p.HasExited){$p.Kill();$null=$p.WaitForExit(4000)}}catch{}}
        $p.Dispose()
    }
}

function Write-ReviewedIpSetAtomic([string]$Path,[string[]]$Networks){
    $canonical=@(Convert-ReviewedIpSetText ($Networks -join "`n") -AllowSentinel)
    $temporary=Join-Path (Split-Path -Parent $Path) ('.ipset-stage-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $rollback=$null;$stream=$null
    try{
        $bytes=[Text.Encoding]::ASCII.GetBytes(($canonical -join "`r`n")+"`r`n")
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush();$stream.Dispose();$stream=$null
        if([IO.File]::Exists($Path)){
            $rollback=$Path+'.before-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.bak'
            [IO.File]::Replace($temporary,$Path,$rollback)
        }else{[IO.File]::Move($temporary,$Path)}
        return $rollback
    }finally{
        if($null -ne $stream){$stream.Dispose()}
        if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}
    }
}

try{
    $Root=[IO.Path]::GetFullPath($Root)
    if($ValidateOnly -or $Mode -eq 'Validate'){
        Test-ReviewedFiles $Root
        Write-Output 'REVIEWED_FILES_OK'
        exit 0
    }
    if($env:OS -ne 'Windows_NT'){throw 'This action requires Windows.'}
    if($Mode -eq 'CheckServiceOwner'){Test-ReviewedServiceOwner $Root;exit 0}
    if($Mode -eq 'Preflight'){
        Test-ReviewedFiles $Root
        if($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'AMD64'){throw 'This release requires Windows x64.'}
        $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator rights are required. Launch START.cmd and accept the Windows prompt.'}
        $processes=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{$_.Name -in @('winws.exe','winws2.exe','goodbyedpi.exe')})
        $services=@(Get-Service -Name zapret,GoodbyeDPI,discordfix_zapret,winws1,winws2 -ErrorAction SilentlyContinue|Where-Object{$_.Status -ne 'Stopped'})
        if($processes.Count -or $services.Count){throw 'Another bypass process or service is active. Close its own window or stop it yourself. Nothing was terminated.'}
        exit 0
    }
    $active=Join-Path $Root 'lists/ipset-all.txt';$backup=$active+'.backup'
    if($Mode -eq 'UpdateIpSet'){
        Test-ReviewedFiles $Root
        $old=@(Read-ReviewedIpSet $active -AllowSentinel)
        $disabled=$old.Count -eq 1 -and $old[0] -eq '203.0.113.113/32'
        $new=@(Get-ReviewedOfficialIpSet)
        $target=if($disabled){$backup}else{$active}
        $rollback=Write-ReviewedIpSetAtomic $target $new
        if($disabled){Write-Host ('Validated '+$new.Count+' networks and updated only ipset-all.txt.backup. IPSet filtering remains disabled.') -ForegroundColor Green}
        else{Write-Host ('Validated '+$new.Count+' networks and atomically updated the active IPSet.') -ForegroundColor Green}
        if($rollback){Write-Host ('Previous file retained as '+[IO.Path]::GetFileName($rollback))}
        exit 0
    }
    if($Mode -eq 'SwitchIpSet'){
        $old=@();$invalid=$false
        try{$old=@(Read-ReviewedIpSet $active -AllowSentinel)}catch{$invalid=$true}
        $disabled=-not $invalid -and $old.Count -eq 1 -and $old[0] -eq '203.0.113.113/32'
        if($disabled){
            $new=@(Read-ReviewedIpSet $backup)
            Write-Host ('The backup contains '+$new.Count+' networks. Enabling it can affect traffic to shared provider/CDN addresses.') -ForegroundColor Yellow
            $answer=Read-Host 'Type LOAD to enable this IPSet (Enter cancels)'
            if($answer -cne 'LOAD'){Write-Host 'IPSet was not changed.';exit 0}
            $rollback=Write-ReviewedIpSetAtomic $active $new
            Write-Host 'IPSet filtering enabled. Restart the bypass to apply it.' -ForegroundColor Green
        }else{
            if(-not $invalid){$null=Write-ReviewedIpSetAtomic $backup $old}
            $rollback=Write-ReviewedIpSetAtomic $active @('203.0.113.113/32')
            Write-Host 'IPSet filtering disabled using the documentation-only sentinel. No ANY mode was created.' -ForegroundColor Green
        }
        if($rollback){Write-Host ('Previous active file retained as '+[IO.Path]::GetFileName($rollback))}
        exit 0
    }
}catch{
    $message=$_.Exception.Message.Replace($Root,'[folder]')
    if($env:USERPROFILE){$message=$message.Replace($env:USERPROFILE,'[profile]')}
    Write-Host $message -ForegroundColor Red
    exit 1
}
