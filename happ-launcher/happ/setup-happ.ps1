param(
    [Parameter(Mandatory=$true)][string]$Root,
    [switch]$ValidateOnly,
    [switch]$PrintFixtureProfile
)
$ErrorActionPreference = 'Stop'

function New-HappRoutingProfile {
    param(
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][string[]]$Networks,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name
    )
    if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$') {
        throw 'HAPP_PROFILE_NAME_INVALID'
    }
    $validated = @(Convert-TelegramCidrText ($Networks -join "`n"))
    if (-not $validated.Count) { throw 'HAPP_OFFICIAL_CIDR_INVALID' }
    # Match the official Happ routing generator's field names and JSON types.
    # In particular, GlobalProxy/FakeDNS are strings and DnsHosts is an object.
    return [pscustomobject][ordered]@{
        Name = $Name
        GlobalProxy = 'false'
        RemoteDNSType = 'DoH'
        RemoteDNSDomain = 'https://dns.google/dns-query'
        RemoteDNSIP = '8.8.8.8'
        DomesticDNSType = 'DoH'
        DomesticDNSDomain = 'https://common.dot.dns.yandex.net/dns-query'
        DomesticDNSIP = '77.88.8.8'
        Geoipurl = ''
        Geositeurl = ''
        LastUpdated = ''
        DnsHosts = [pscustomobject]@{}
        DirectSites = @()
        DirectIp = @()
        ProxySites = @(
            'domain:chatgpt.com',
            'domain:openai.com',
            'domain:oaistatic.com',
            'domain:oaiusercontent.com',
            'domain:challenges.cloudflare.com',
            'domain:telegram.org',
            'domain:t.me',
            'domain:telegram.me',
            'domain:telegram-cdn.org'
        )
        ProxyIp = @($validated)
        BlockSites = @()
        BlockIp = @()
        DomainStrategy = 'IPIfNonMatch'
        FakeDNS = 'false'
    }
}

function ConvertTo-HappImportUri {
    param([Parameter(Mandatory=$true)]$Profile)
    $json = $Profile | ConvertTo-Json -Depth 5
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    return 'happ://routing/add/' + [Convert]::ToBase64String($bytes)
}

function Get-OfficialTelegramCidrs {
    $process = New-Object Diagnostics.Process
    $started = $false
    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = Join-Path $env:SystemRoot 'System32/curl.exe'
        # No redirects, insecure TLS, user config file, shell, or authenticated URL.
        $info.Arguments = '--disable --silent --show-error --fail --max-filesize 65536 --max-time 18 --connect-timeout 8 --proto =https --proto-redir =https -- https://core.telegram.org/resources/cidr.txt'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process.StartInfo = $info
        $started = $process.Start()
        if (-not $started) { throw 'HAPP_OFFICIAL_CIDR_UNAVAILABLE' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(22000)) { throw 'HAPP_OFFICIAL_CIDR_UNAVAILABLE' }
        if (-not $stdout.Wait(3000) -or -not $stderr.Wait(3000)) {
            throw 'HAPP_OFFICIAL_CIDR_UNAVAILABLE'
        }
        $body = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'HAPP_OFFICIAL_CIDR_UNAVAILABLE' }
        try { $networks = @(Convert-TelegramCidrText $body) }
        catch { throw 'HAPP_OFFICIAL_CIDR_INVALID' }
        if (-not $networks.Count) { throw 'HAPP_OFFICIAL_CIDR_INVALID' }
        return $networks
    } catch {
        if ($_.Exception.Message -eq 'HAPP_OFFICIAL_CIDR_INVALID') { throw }
        throw 'HAPP_OFFICIAL_CIDR_UNAVAILABLE'
    } finally {
        if ($started) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    $null = $process.WaitForExit(4000)
                }
            } catch { }
        }
        $process.Dispose()
    }
}

function Write-AtomicUtf8New {
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $temporary = Join-Path (Split-Path -Parent $Path) ('.tmp-' + [guid]::NewGuid().ToString('N'))
    $stream = $null
    try {
        $encoding = New-Object Text.UTF8Encoding($false)
        $bytes = $encoding.GetBytes($Text)
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $stream.Dispose()
        $stream = $null
        # .NET File.Move refuses an existing destination: no old profile is replaced.
        [IO.File]::Move($temporary, $Path)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

try {
    $Root = [IO.Path]::GetFullPath($Root)
    $helperPath = Join-Path $Root 'happ/telegram-ipset.ps1'
    . ([scriptblock]::Create([IO.File]::ReadAllText($helperPath)))
    foreach ($functionName in @('Convert-TelegramCidrText','New-HappRoutingProfile','ConvertTo-HappImportUri','Get-OfficialTelegramCidrs','Write-AtomicUtf8New')) {
        $null = Get-Command -Name $functionName -CommandType Function -ErrorAction Stop
    }
    if ($ValidateOnly -or $PrintFixtureProfile) {
        $fixture = New-HappRoutingProfile -Networks @('149.154.160.0/20','2001:b28:f23d::/48') -Name 'ChatGPT-Telegram-Selective-FIXTURE'
        $uri = ConvertTo-HappImportUri -Profile $fixture
        if (-not $uri.StartsWith('happ://routing/add/')) { throw 'HAPP_FIXTURE_FAILED' }
        if ($PrintFixtureProfile) { $fixture | ConvertTo-Json -Depth 5 }
        else { Write-Output 'HAPP_SETUP_FILES_OK' }
        exit 0
    }
    if ($env:OS -ne 'Windows_NT') { throw 'HAPP_WINDOWS_REQUIRED' }
    Write-Host 'Оставьте рабочее подключение Happ включённым. Старый START.cmd должен быть закрыт.'
    Write-Host 'Получаю список адресов Telegram с официального HTTPS-источника.'
    $networks = @(Get-OfficialTelegramCidrs)
    $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
    $name = 'ChatGPT-Telegram-Selective-' + $suffix
    $profile = New-HappRoutingProfile -Networks $networks -Name $name
    $json = $profile | ConvertTo-Json -Depth 5
    $link = ConvertTo-HappImportUri -Profile $profile
    $state = Join-Path $Root 'happ-state'
    $destination = Join-Path $state $name
    if (Test-Path -LiteralPath $destination) { throw 'HAPP_OUTPUT_WRITE_FAILED' }
    try {
        $null = [IO.Directory]::CreateDirectory($destination)
        Write-AtomicUtf8New -Path (Join-Path $destination 'routing.json') -Text ($json + "`r`n")
        Write-AtomicUtf8New -Path (Join-Path $destination 'import-link.txt') -Text ($link + "`r`n")
    } catch { throw 'HAPP_OUTPUT_WRITE_FAILED' }
    Write-Host ('Новый профиль: ' + $name) -ForegroundColor Green
    Write-Host ('Через существующий сервер Happ: ChatGPT/OpenAI и Telegram; сетей Telegram: ' + $networks.Count + '.')
    Write-Host 'Весь остальной трафик, включая российские сайты и YouTube, направляется напрямую.'
    Write-Host 'Внутри этого профиля Happ: удалённый DNS Google DoH (8.8.8.8), прямой DNS Yandex DoH (77.88.8.8).'
    Write-Host 'Системный DNS Windows этим скриптом не изменяется. Серверы и подписки в файле отсутствуют.'
    Write-Host 'Сейчас откроется импорт Happ. Добавьте новый профиль и выберите его в маршрутизации Happ.'
    Write-Host 'Прежний профиль сохраните для возврата. Скрипт не выбирает профиль и не переключает VPN автоматически.'
    Write-Host 'После выбора подключите Happ в прежнем режиме, с которым работал Telegram, и запустите START.cmd из этой папки.'
    try {
        $open = New-Object Diagnostics.ProcessStartInfo
        $open.FileName = $link
        $open.UseShellExecute = $true
        $opened = [Diagnostics.Process]::Start($open)
        if ($null -ne $opened) { $opened.Dispose() }
    } catch { throw 'HAPP_IMPORT_OPEN_FAILED' }
    exit 0
} catch {
    $message = switch ($_.Exception.Message) {
        'HAPP_OFFICIAL_CIDR_UNAVAILABLE' { 'Официальный список Telegram недоступен. Оставьте рабочий Happ включённым и повторите SETUP-HAPP.cmd. Импорт не запускался.' }
        'HAPP_OFFICIAL_CIDR_INVALID' { 'Ответ официального источника не прошёл проверку адресов. Профиль не импортирован; пустые или широкие диапазоны не применяются.' }
        'HAPP_OUTPUT_WRITE_FAILED' { 'Не удалось сохранить новый профиль. Распакуйте папку в доступное для записи место и повторите. Импорт не запускался.' }
        'HAPP_IMPORT_OPEN_FAILED' { 'Happ не открыл ссылку импорта. Новый профиль и ссылка сохранены в happ-state. Убедитесь, что Happ установлен.' }
        'HAPP_WINDOWS_REQUIRED' { 'Для настройки требуется Windows с установленным Happ.' }
        default { 'Не удалось подготовить профиль Happ. Распакуйте весь архив заново; сохранённые серверы и настройки Windows не изменялись.' }
    }
    Write-Host $message -ForegroundColor Red
    exit 1
}
