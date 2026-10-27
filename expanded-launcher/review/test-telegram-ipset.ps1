param([string]$Source = (Join-Path $PSScriptRoot 'telegram-ipset.ps1'))
$ErrorActionPreference = 'Stop'
. $Source

$script:Checks = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if (($Actual | ConvertTo-Json -Compress) -ne ($Expected | ConvertTo-Json -Compress)) {
        throw ('Mismatch: ' + $Name)
    }
    $script:Checks++
}
function Reject([string]$Text, [string]$Name) {
    $rejected = $false
    try { $null = @(Convert-TelegramCidrText $Text) }
    catch { $rejected = $true }
    if (-not $rejected) { throw ('Unsafe CIDR accepted: ' + $Name) }
    $script:Checks++
}

$valid = @'
# Only fixtures; no network requests performed.
149.154.160.0/20
91.108.4.0/22
91.108.8.0/22
91.108.12.0/22
91.108.16.0/22
91.108.56.0/22
95.161.76.100/32
2001:0B28:F23D::/48
2001:067C:04E8::/48
'@
$actual = @(Convert-TelegramCidrText $valid)
Assert-Equal $actual.Count 9 'Valid Telegram fixture count'
Assert-Equal $actual[0] '149.154.160.0/20' 'IPv4 preserved'
Assert-Equal $actual[7] '2001:b28:f23d::/48' 'IPv6 canonical lowercase compression'
Assert-Equal $actual[8] '2001:67c:4e8::/48' 'IPv6 leading zeros compressed'
Assert-Equal @(Convert-TelegramCidrText '149.154.175.50/32') @('149.154.175.50/32') 'Single /32 array wrapper'
Assert-Equal @(Convert-TelegramCidrText "91.108.4.0/22`r`n91.108.4.0/22") @('91.108.4.0/22') 'Ordered duplicate removed'
Assert-Equal @(Convert-TelegramCidrText ([char]0xFEFF + '149.154.160.0/20')) @('149.154.160.0/20') 'Leading UTF8 BOM character accepted'

foreach ($case in @(
    @('', 'empty'), @("`r`n  `t", 'whitespace'), @('# just a comment', 'comment only'),
    @('<html>upstream denied</html>', 'HTML'), @('not-a-network', 'malformed'),
    @('149.154.160.0', 'missing prefix'), @('example.org/24', 'hostname'),
    @('149.154.160.0/020', 'leading prefix zeros'), @('149.154.160.0/20 trailing', 'trailing token'),
    @('149.154.160.0/15', 'IPv4 wide'), @('149.154.160.0/33', 'IPv4 invalid prefix'),
    @('149.154.160.1/20', 'IPv4 host bits'), @('149.154.160.00/20', 'IPv4 leading zero'),
    @('256.154.160.0/20', 'IPv4 malformed octet'), @('10.0.0.0/16', 'private 10'),
    @('172.16.0.0/16', 'private 172'), @('192.168.0.0/16', 'private 192'),
    @('127.0.0.1/32', 'loopback'), @('0.0.0.0/16', 'unspecified block'),
    @('169.254.0.0/16', 'link-local'), @('100.64.0.0/16', 'CGNAT'),
    @('224.0.0.0/16', 'multicast'), @('255.255.255.255/32', 'broadcast reserved'),
    @('192.0.2.0/24', 'documentation 192'), @('198.51.100.0/24', 'documentation 198'),
    @('203.0.113.0/24', 'documentation 203'), @('198.51.0.0/16', 'IPv4 overlap documentation'),
    @('192.0.0.0/16', 'IPv4 overlap protocol/documentation'), @('198.18.0.0/16', 'benchmarking'),
    @('2001:b28::/31', 'IPv6 wide'), @('2001:b28::/129', 'IPv6 invalid prefix'),
    @('2001:b28:f23d::1/48', 'IPv6 host bits'), @('2001:db8::/32', 'IPv6 RFC3849 documentation'),
    @('3fff::/32', 'IPv6 RFC9637 documentation'), @('3fff:fff::/32', 'IPv6 RFC9637 upper overlap'),
    @('fc00::/32', 'IPv6 private'), @('fe80::/64', 'IPv6 link local'),
    @('ff02::/32', 'IPv6 multicast'), @('::1/128', 'IPv6 loopback'),
    @('::/128', 'IPv6 unspecified'), @('::ffff:149.154.175.50/128', 'IPv4 mapped IPv6'),
    @('2001:b28::%1/32', 'IPv6 zone identifier')
)) {
    Reject $case[0] $case[1]
}

Reject ((1..65 | ForEach-Object { '149.154.175.50/32' }) -join "`n") 'More than 64 raw networks even when duplicates'
Reject ('#' + ('x' * 65536)) 'Oversized body'
$boundary = @(1..64 | ForEach-Object { '149.154.175.' + $_ + '/32' })
Assert-Equal @(Convert-TelegramCidrText ($boundary -join "`n")).Count 64 '64-network bound accepted'
Assert-Equal @(Convert-TelegramCidrText '3fff:1000::/32') @('3fff:1000::/32') 'Global IPv6 outside documentation boundary'
Write-Output ('PASS: ' + $script:Checks + ' CIDR fixture assertions; no network/Windows APIs used.')
