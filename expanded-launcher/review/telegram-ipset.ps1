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
