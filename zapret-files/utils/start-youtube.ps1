#requires -Version 5.1
[CmdletBinding()]
param([switch]$TcpOnly, [switch]$PrintArguments, [switch]$ValidateFilesOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'bin'
$hostlist = Join-Path $root 'lists\list-youtube-optimized.txt'
$pattern = Join-Path $bin 'tls_clienthello_www_google_com.bin'
$quic = Join-Path $bin 'quic_initial_www_google_com.bin'
$exe = Join-Path $bin 'winws.exe'
# Literal double quotes are needed by Windows PowerShell 5.1 native argv handling.
function Quote-Path([string]$Value) { return '"' + $Value + '"' }
$winwsArgs = @('--wf-tcp=443')
if (-not $TcpOnly) { $winwsArgs += '--wf-udp=443' }
if (-not $TcpOnly) {
    $winwsArgs += @('--filter-udp=443', ('--hostlist=' + (Quote-Path $hostlist)),
        '--dpi-desync=fake', '--dpi-desync-repeats=6',
        ('--dpi-desync-fake-quic=' + (Quote-Path $quic)), '--new')
}
$winwsArgs += @('--filter-tcp=443', ('--hostlist=' + (Quote-Path $hostlist)),
    '--ip-id=zero', '--dpi-desync=multisplit', '--dpi-desync-split-seqovl=681',
    '--dpi-desync-split-pos=1', ('--dpi-desync-split-seqovl-pattern=' + (Quote-Path $pattern)))
if ($PrintArguments) {
    # Pure inspection: does not load binaries or require elevation.
    [pscustomobject]@{ Executable = $exe; Arguments = $winwsArgs } | ConvertTo-Json -Depth 4
    exit 0
}
$required = @($exe, $pattern, $hostlist, (Join-Path $bin 'WinDivert.dll'),
    (Join-Path $bin 'WinDivert64.sys'), (Join-Path $bin 'cygwin1.dll'))
if (-not $TcpOnly) { $required += $quic }
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing required file: $file" }
}
$names = @(Get-Content -LiteralPath $hostlist | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') })
if ($names.Count -eq 0) { throw 'The YouTube hostlist is empty. Refusing to launch an unscoped filter.' }
foreach ($name in $names) {
    if ($name -notmatch '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$' -or $name.Contains('..')) {
        throw "Invalid hostname in YouTube list: $name"
    }
}
$expected = Get-Content -LiteralPath (Join-Path $root 'ORIGINAL-SHA256.json') -Raw | ConvertFrom-Json
foreach ($entry in $expected.PSObject.Properties) {
    if ($entry.Name -like 'bin/*') {
        $file = Join-Path $root $entry.Name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing original binary/payload: $($entry.Name)" }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.Value) {
            throw "Original binary/payload checksum mismatch: $($entry.Name). Restore from verified release 1.10.4."
        }
    }
}
if ($ValidateFilesOnly) {
    Write-Output 'Required files, original bin SHA-256 and nonempty hostname list validated. No executable started.'
    exit 0
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run start-youtube.cmd from a terminal opened as administrator. No automatic elevation is performed.'
}
$mutex = New-Object System.Threading.Mutex($false, 'Global\ZapretYoutubeOptimized1104')
$locked = $false
$code = 1
try {
    try { $locked = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'This optimized launcher is already running.' }
    # Fail closed if CIM inventory is unavailable. Never kill other processes or services.
    $running = @(Get-CimInstance Win32_Process -Filter "Name='winws.exe' OR Name='winws2.exe' OR Name='goodbyedpi.exe'")
    if ($running.Count -gt 0) { throw 'Another bypass process is running. Inspect it and close your old launcher first.' }
    $conflicts = @(Get-Service -Name zapret,GoodbyeDPI,discordfix_zapret,winws1,winws2 -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'Stopped' })
    if ($conflicts.Count -gt 0) { throw 'A bypass service is active. This launcher will not stop or remove it.' }
    Write-Host 'YouTube-only profile. Close this window or press Ctrl+C to stop.'
    Write-Host 'WinDivert intercepts port 443; only matching YouTube hostnames receive desync.'
    if ($TcpOnly) { Write-Warning 'TCP-only diagnostic mode: QUIC remains untreated; it is not disabled.' }
    Push-Location -LiteralPath $bin
    try {
        & $exe @winwsArgs
        $code = $LASTEXITCODE
    } finally { Pop-Location }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $code
