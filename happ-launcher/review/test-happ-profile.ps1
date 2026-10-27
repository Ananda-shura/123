param([string]$Source=(Join-Path $PSScriptRoot '../happ/setup-happ.ps1'))
$ErrorActionPreference='Stop'
$script:Checks=0

function Check([bool]$Condition,[string]$Message) {
    if(-not $Condition){throw ('ASSERTION: '+$Message)}
    $script:Checks++
}
function Equal-Sequence($Actual,$Expected,[string]$Message) {
    Check ((@($Actual) -join "`n") -ceq (@($Expected) -join "`n")) $Message
}
function Load-PureFunction([string]$Path,[string]$Name) {
    $tokens=$null;$errors=$null
    $tree=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors -join '; ')}
    $found=@($tree.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|Where-Object{$_.Name -eq $Name})
    if($found.Count -ne 1){throw ('Missing/ambiguous pure function: '+$Name)}
    return $found[0].Extent.Text
}

# Parse source instead of dot-sourcing it: never invoke its Windows/import/network branch.
$helper=Join-Path (Split-Path -Parent $Source) 'telegram-ipset.ps1'
. ([scriptblock]::Create((Load-PureFunction $helper 'Convert-TelegramCidrText')))
. ([scriptblock]::Create((Load-PureFunction $Source 'New-HappRoutingProfile')))

$sample=@('149.154.160.0/20','91.108.4.0/22','2001:0B28:F23D::/48')
$canonical=@('149.154.160.0/20','91.108.4.0/22','2001:b28:f23d::/48')
$profile=New-HappRoutingProfile -Networks $sample -Name 'ChatGPT-Telegram-Fixture'
# JSON makes dictionary and PSCustomObject implementations comparable without invoking main.
$json=$profile|ConvertTo-Json -Depth 8 -Compress
$decoded=$json|ConvertFrom-Json
$fields=@('Name','GlobalProxy','RemoteDNSType','RemoteDNSDomain','RemoteDNSIP','DomesticDNSType','DomesticDNSDomain','DomesticDNSIP','Geoipurl','Geositeurl','LastUpdated','DnsHosts','DirectSites','DirectIp','ProxySites','ProxyIp','BlockSites','BlockIp','DomainStrategy','FakeDNS')
Equal-Sequence (@($decoded.PSObject.Properties.Name)|Sort-Object) ($fields|Sort-Object) 'exact official 20-field schema, no server/subscription fields'
$arrayFields=@('DirectSites','DirectIp','ProxySites','ProxyIp','BlockSites','BlockIp')
foreach($field in $fields) {
    if($field -eq 'DnsHosts' -or $field -in $arrayFields){continue}
    Check ($decoded.$field -is [string]) ('scalar field is string: '+$field)
}
Check ($decoded.Name -ceq 'ChatGPT-Telegram-Fixture') 'explicit new profile name retained'
Check ($decoded.GlobalProxy -ceq 'false') 'unmatched traffic remains direct'
Check ($decoded.FakeDNS -ceq 'false') 'FakeDNS is disabled'
Check (($decoded.DnsHosts|ConvertTo-Json -Compress) -ceq '{}') 'DnsHosts is an empty JSON object'
foreach($field in $arrayFields){Check ($decoded.$field -is [array]) ('array field remains an array: '+$field)}
foreach($field in @('DirectSites','DirectIp','BlockSites','BlockIp')){Check (@($decoded.$field).Count -eq 0) ('no direct/block override rules: '+$field)}
Check ($decoded.DomainStrategy -ceq 'IPIfNonMatch') 'documented domain strategy selected'
Check ($decoded.RemoteDNSType -ceq 'DoH' -and $decoded.RemoteDNSDomain -ceq 'https://dns.google/dns-query' -and $decoded.RemoteDNSIP -ceq '8.8.8.8') 'explicit profile-only remote Google DoH'
Check ($decoded.DomesticDNSType -ceq 'DoH' -and $decoded.DomesticDNSDomain -ceq 'https://common.dot.dns.yandex.net/dns-query' -and $decoded.DomesticDNSIP -ceq '77.88.8.8') 'explicit profile-only domestic Yandex DoH'
Check ($decoded.Geoipurl -ceq '' -and $decoded.Geositeurl -ceq '') 'no external geodata downloads configured'
Check ($decoded.LastUpdated -ceq '') 'no fabricated geodata timestamp'
Check ($json -notmatch '(?i)"(?:password|passwd|token|uuid|subscription|outbounds|inbounds|server|secret|privateKey|publicKey)"\s*:') 'no server credentials or replacement connection configuration'

$hosts=@('chatgpt.com','openai.com','oaistatic.com','oaiusercontent.com','challenges.cloudflare.com','telegram.org','t.me','telegram.me','telegram-cdn.org')
Equal-Sequence (@($decoded.ProxySites)|Sort-Object) (@($hosts|ForEach-Object{'domain:'+$_})|Sort-Object) 'only the exact nine service domain suffix rules'
foreach($rule in $decoded.ProxySites){Check ($rule -cmatch '^domain:[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$') 'domain suffix syntax is explicit and bounded'}
Equal-Sequence $decoded.ProxyIp $canonical 'Telegram IP rules equal canonical validated source networks'
foreach($network in $decoded.ProxyIp){Check ($network -notmatch '^(?:geoip:|geosite:|ext:|0\.0\.0\.0/0|::/0)') 'no wildcard, tags or external geodata dependency in Telegram IP rules'}

function Matches-ProxyDomain([string]$HostName,$Rules) {
    foreach($rule in $Rules) {
        $suffix=$rule.Substring('domain:'.Length)
        if($HostName -eq $suffix -or $HostName.EndsWith('.'+$suffix,[StringComparison]::OrdinalIgnoreCase)){return $true}
    }
    return $false
}
foreach($name in @('chatgpt.com','www.chatgpt.com','auth.openai.com','api.openai.com','cdn.oaistatic.com','files.oaiusercontent.com','challenges.cloudflare.com','web.telegram.org','kws2.web.telegram.org','core.telegram.org','t.me','telegram.me','cdn.telegram-cdn.org')) {
    Check (Matches-ProxyDomain $name $decoded.ProxySites) ('service hostname matches: '+$name)
}
foreach($name in @('ya.ru','yandex.ru','vk.com','gosuslugi.ru','sberbank.ru','ozon.ru','store.steampowered.com','steamcommunity.com','youtube.com','www.youtube.com','rr1.googlevideo.com','i.ytimg.com','youtubei.googleapis.com','www.google.com','cloudflare.com','example.cloudflare.com','notchatgpt.com','chatgpt.com.evil.example','telegram.org.evil.example')) {
    Check (-not (Matches-ProxyDomain $name $decoded.ProxySites)) ('unrelated or misleading hostname remains direct: '+$name)
}
Write-Output 'PASS: official schema, string types, narrow domain/IP rules, direct default and explicit profile-only DNS'

foreach($invalid in @(@(),@(''),@('10.0.0.0/16'),@('0.0.0.0/0'),@('::/0'),@('not-a-network'),@('149.154.160.1/20'),@('127.0.0.1/32'),@('geoip:telegram'))) {
    $rejected=$false
    try{$null=New-HappRoutingProfile -Networks $invalid -Name 'Invalid-Fixture'}catch{$rejected=$true}
    Check $rejected 'empty/private/broad/malformed networks rejected before import serialization'
}
$rejected=$false
try{$null=New-HappRoutingProfile -Networks @('149.154.160.0/20','0.0.0.0/0') -Name 'Mixed-Invalid-Fixture'}catch{$rejected=$true}
Check $rejected 'one invalid network rejects an otherwise-valid complete profile'
foreach($invalidName in @('','Has space','../path',('fixture-'+[char]0x0410),('a'*121))) {
    $reason=$null
    try{$null=New-HappRoutingProfile -Networks $sample -Name $invalidName}catch{$reason=$_.Exception.Message}
    Check ($reason -ceq 'HAPP_PROFILE_NAME_INVALID') 'invalid profile name is rejected explicitly'
}
Write-Output 'PASS: unsafe or empty Telegram rules cannot produce an importable profile'

$tokens=$null;$errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
$uriBuilder=@($tree.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|Where-Object{$_.Name -eq 'ConvertTo-HappImportUri'})
if($uriBuilder.Count -eq 1) {
    . ([scriptblock]::Create($uriBuilder[0].Extent.Text))
    $uri=ConvertTo-HappImportUri $profile
}else{
    Check ($uriBuilder.Count -eq 0) 'no ambiguous import URI function'
    $uri='happ://routing/add/'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    Write-Output 'NOTE: no separate pure URI builder; testing documented serialization format only.'
}
$prefix='happ://routing/add/'
Check ($uri -is [string] -and $uri.StartsWith($prefix,[StringComparison]::Ordinal)) 'official routing-only import prefix'
$payload=$uri.Substring($prefix.Length)
Check ($payload -cmatch '^[A-Za-z0-9+/]+={0,2}$') 'standard Base64 alphabet, not URL-safe or encoded subscription data'
$roundTrip=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))|ConvertFrom-Json
Check (($roundTrip|ConvertTo-Json -Depth 8 -Compress) -ceq $json) 'UTF8 JSON survives routing-only Base64 round trip'
Check ($roundTrip.GlobalProxy -ceq 'false') 'direct default survives URI serialization'
Equal-Sequence $roundTrip.ProxyIp $canonical 'Telegram networks survive URI serialization'
$unicodeName='ChatGPT-fixture-'+[char]0x0410
# The profile generator deliberately limits names to ASCII. Exercise UTF8 on the
# pure serializer separately, without claiming this synthetic name is importable.
$unicodeProfile=$json|ConvertFrom-Json
$unicodeProfile.Name=$unicodeName
if($uriBuilder.Count -eq 1){$unicodeUri=ConvertTo-HappImportUri $unicodeProfile}
else{$unicodeUri=$prefix+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($unicodeProfile|ConvertTo-Json -Depth 8 -Compress)))}
$unicodeRoundTrip=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($unicodeUri.Substring($prefix.Length)))|ConvertFrom-Json
Check ($unicodeRoundTrip.Name -ceq $unicodeName) 'non-ASCII profile name survives UTF8 import encoding'
Write-Output ('PASS: '+$script:Checks+' assertions; no network, Happ, native process, Windows branch or import action executed.')
