#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label = 'baseline',
    [ValidatePattern('^[A-Za-z0-9.-]+$')][string]$PingTarget,
    [ValidateRange(5,100)][int]$PingCount = 20
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$results = Join-Path $root 'diagnostics-local'
$null = New-Item -ItemType Directory -Path $results -Force
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$out = Join-Path $results ($Label + '-' + $stamp + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$report = [ordered]@{ Label = $Label; TimeUtc = [datetime]::UtcNow.ToString('o');
    Note = 'Read-only system queries and outbound DNS/HTTPS/optional ICMP. File output is local. Not a video/game benchmark.' }
function Capture([scriptblock]$Action) {
    try { & $Action } catch { [pscustomobject]@{ Error = $_.Exception.Message } }
}
$report.Processes = @(Capture {
    Get-CimInstance Win32_Process -Filter "Name='winws.exe' OR Name='winws2.exe' OR Name='goodbyedpi.exe'" |
        Select-Object Name,ProcessId,ExecutablePath,CommandLine
})
$report.Services = @(Capture {
    Get-CimInstance Win32_Service | Where-Object {
        $_.Name -match '^(zapret|GoodbyeDPI|discordfix_zapret|winws1|winws2|BFE)$' -or
        $_.Name -match 'Killer|SmartByte|Adguard|TracSrvWrapper|EPWD|VPN|HappService|Intel.*Connectivity'
    } | Select-Object Name,State,StartMode
})
$report.Drivers = @(Capture {
    Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'WinDivert' } |
        Select-Object Name,State,StartMode
})
$report.Dns = @(Capture { Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses.Count -gt 0 } |
    Select-Object InterfaceAlias,AddressFamily,ServerAddresses })
$report.TcpGlobal = @(Capture { & netsh.exe interface tcp show global })
$report.WinHttpProxy = @(Capture { & netsh.exe winhttp show proxy })
$report.UserProxyEnabled = Capture {
    $p = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    [pscustomobject]@{ Enabled = ($p.ProxyEnable -eq 1); PacConfigured = [bool]($p.PSObject.Properties['AutoConfigURL']) }
}
$report.HostsYoutubeEntryCount = Capture {
    $hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    @(Get-Content -LiteralPath $hostsFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'youtube|googlevideo|ytimg' }).Count
}
$report.Flags = Capture {
    [pscustomobject]@{
        GameFilterFilePresent = Test-Path -LiteralPath (Join-Path $root 'utils\game_filter.enabled')
        GameFilter = @(if (Test-Path -LiteralPath (Join-Path $root 'utils\game_filter.enabled')) {
            Get-Content -LiteralPath (Join-Path $root 'utils\game_filter.enabled')
        })
        IpsetLineCount = @(Get-Content -LiteralPath (Join-Path $root 'lists\ipset-all.txt')).Count
    }
}
$report.Files = @(Capture {
    Get-ChildItem -LiteralPath (Join-Path $root 'bin') -File | ForEach-Object {
        $sig = if ($_.Extension -in '.exe','.dll','.sys') { Get-AuthenticodeSignature -LiteralPath $_.FullName }
        [pscustomobject]@{ Name = $_.Name; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;
            SignatureStatus = if ($null -ne $sig) { [string]$sig.Status } else { 'NotApplicable' } }
    }
})
$domains = 'www.youtube.com','redirector.googlevideo.com','i.ytimg.com','youtubei.googleapis.com',
    'store.steampowered.com','steamcommunity.com','cdn.cloudflare.steamstatic.com'
$report.Resolution = @(foreach ($domain in $domains) {
    [pscustomobject]@{ Domain = $domain; Results = @(Capture {
        Resolve-DnsName -Name $domain -DnsOnly | Where-Object { $_.Type -in 'A','AAAA' } | Select-Object Type,IPAddress
    }) }
})
$report.HttpsTcp = @(foreach ($url in @('https://www.youtube.com/',
    'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    'https://store.steampowered.com/','https://steamcommunity.com/')) {
    Capture {
        $format = 'http=%{http_code} dns=%{time_namelookup} connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total} bytes=%{size_download} ip=%{remote_ip}'
        $curl = (Get-Command curl.exe -CommandType Application -ErrorAction Stop).Source
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $curl
        $info.Arguments = '--silent --show-error --location --max-redirs 3 --max-time 20 --connect-timeout 7 --proto "=https" --proto-redir "=https" --output NUL --write-out "' + $format + '" "' + $url + '"'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $info
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            [pscustomobject]@{ Url = $url; CurlExitCode = $process.ExitCode;
                Result = $stdout.GetAwaiter().GetResult(); Error = $stderr.GetAwaiter().GetResult() }
        } finally { $process.Dispose() }
    }
})
if ($PingTarget) {
    $report.Icmp = Capture {
        $pinger = New-Object System.Net.NetworkInformation.Ping
        $samples = @()
        try {
            for ($i = 0; $i -lt $PingCount; $i++) {
                $reply = $pinger.Send($PingTarget, 1500)
                $samples += [pscustomobject]@{ Status = [string]$reply.Status; RttMs = if ($reply.Status -eq 'Success') { $reply.RoundtripTime } else { $null } }
                if ($i -lt ($PingCount - 1)) { Start-Sleep -Milliseconds 500 }
            }
        } finally { $pinger.Dispose() }
        $ok = @($samples | Where-Object { $_.Status -eq 'Success' })
        [pscustomobject]@{ Target = $PingTarget; Samples = $samples;
            LossPercent = 100.0 * ($PingCount - $ok.Count) / $PingCount;
            Rtt = if ($ok.Count -gt 0) { $ok.RttMs | Measure-Object -Average -Minimum -Maximum } else { $null };
            Note = 'ICMP is not CS2 UDP latency or loss. No response may mean ICMP is filtered.' }
    }
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Saved local report: ' + $out)
Write-Host 'Inspect before sharing: paths, DNS addresses, process arguments and target addresses can identify your setup.'
