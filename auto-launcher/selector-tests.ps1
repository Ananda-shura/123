param([string]$Source = '/workspace/zapret-autopick-tool/autopick.ps1')
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ('Source parse failed: ' + ($errors -join '; ')) }
$definitions = @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $true))
foreach ($name in @('Get-Profiles', 'Select-Profile')) {
    $definition = @($definitions | Where-Object { $_.Name -eq $name })
    if ($definition.Count -ne 1) { throw ('Missing or ambiguous function: ' + $name) }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw ('ASSERTION FAILED: ' + $Message) }
}
function Assert-Sequence($Actual, $Expected, [string]$Message) {
    Assert-True ((@($Actual) -join '|') -ceq (@($Expected) -join '|')) $Message
}
function Reset-Fixture {
    $script:Root = '/tmp/owned selector fixture'
    $script:report = [ordered]@{ Candidates = @() }
    $script:Starts = New-Object 'System.Collections.Generic.List[string]'
    $script:Stops = New-Object 'System.Collections.Generic.List[string]'
    $script:Probes = New-Object 'System.Collections.Generic.List[string]'
    $script:Current = $null
    $script:CurrentProcess = $null
    $script:Answers = @{}
    $script:ProbeThrows = @{}
    $script:AlreadyExited = @{}
    $script:ExitDuringProbe = @{}
}
function Test-Profiles($Names) {
    foreach ($name in $Names) { [pscustomobject]@{ Name = $name; Arguments = @('fixture-only') } }
}
$start = {
    param($candidate)
    $script:Current = $candidate.Name
    [void]$script:Starts.Add($candidate.Name)
    $script:CurrentProcess = [pscustomobject]@{ Name = $candidate.Name; HasExited = [bool]$script:AlreadyExited[$candidate.Name] }
    $script:CurrentProcess
}
$probe = {
    param($mode)
    $key = $script:Current + '/' + $mode
    [void]$script:Probes.Add($key)
    if ($script:ProbeThrows[$key]) { throw 'FIXTURE_PROBE_EXCEPTION' }
    if ($script:ExitDuringProbe[$key]) { $script:CurrentProcess.HasExited = $true }
    [pscustomobject]@{ Success = [bool]$script:Answers[$key]; Fixture = $key }
}
$stop = {
    param($process)
    [void]$script:Stops.Add($process.Name)
}

# A rejected trial must be stopped once; the selected trial must remain owned
# and running, and a later profile must not be started.
Reset-Fixture
$script:Answers = @{ 'A/fixed' = $false; 'B/fixed' = $true; 'B/normal' = $true }
$selected = Select-Profile @(Test-Profiles @('A', 'B', 'C')) $start $probe $stop
Assert-True ($selected.Profile.Name -eq 'B' -and $selected.Process.Name -eq 'B') 'second successful trial is retained'
Assert-Sequence $script:Starts @('A', 'B') 'no candidate starts after a winner'
Assert-Sequence $script:Stops @('A') 'rejected child stopped once, winner not stopped'
Assert-Sequence $script:Probes @('A/fixed', 'B/fixed', 'B/normal') 'normal DNS is checked only after fixed-address success'
Assert-True ($script:report.Candidates.Count -eq 2 -and -not $script:report.Candidates[0].Passed -and $script:report.Candidates[1].Passed) 'report distinguishes rejected and selected trials'
Write-Output 'PASS: rejected trials stop exactly once; winner stays running; no later trial'

# A fixed-address-only success must not be called a working normal-DNS profile.
Reset-Fixture
$script:Answers = @{ 'A/fixed' = $true; 'A/normal' = $false; 'B/fixed' = $true; 'B/normal' = $true }
$selected = Select-Profile @(Test-Profiles @('A', 'B')) $start $probe $stop
Assert-True ($selected.Profile.Name -eq 'B') 'normal-DNS failure rejects fixed-address success'
Assert-Sequence $script:Stops @('A') 'fixed-only winner is stopped'
Assert-True ($script:report.Candidates[0].FixedAddress.Success -and -not $script:report.Candidates[0].NormalDns.Success -and -not $script:report.Candidates[0].Passed) 'fixed-only result remains distinguishable in report'
Write-Output 'PASS: normal-DNS failure rejects a fixed-address-only success'

Reset-Fixture
$selected = Select-Profile @(Test-Profiles @('A', 'B', 'C')) $start $probe $stop
Assert-True ($null -eq $selected) 'all failing probes return no selected profile'
Assert-Sequence $script:Starts @('A', 'B', 'C') 'all ordinary failures are tried'
Assert-Sequence $script:Stops @('A', 'B', 'C') 'all failing owned trials are stopped once'
Assert-True ($script:report.Candidates.Count -eq 3 -and @($script:report.Candidates | Where-Object Passed).Count -eq 0) 'all-failure report contains no pass'
Write-Output 'PASS: all failures return null and stop each owned child'

Reset-Fixture
$script:ProbeThrows = @{ 'A/fixed' = $true }
$script:Answers = @{ 'B/fixed' = $true; 'B/normal' = $true }
$selected = Select-Profile @(Test-Profiles @('A', 'B')) $start $probe $stop
Assert-True ($selected.Profile.Name -eq 'B') 'probe exception permits a later ordinary trial'
Assert-Sequence $script:Stops @('A') 'probe exception cleans up its own child'
Assert-True ($script:report.Candidates[0].Error -eq 'FIXTURE_PROBE_EXCEPTION') 'probe exception is recorded'
Write-Output 'PASS: probe exceptions clean up the trial and remain visible'

# Start is responsible for cleanup before returning its Process object. A Job
# failure must retain its fatal marker and prevent every subsequent trial.
Reset-Fixture
$fatalStart = {
    param($candidate)
    [void]$script:Starts.Add($candidate.Name)
    throw 'AUTOPICK_JOB_ASSIGN_FAILED'
}
$thrown = $null
try { $null = Select-Profile @(Test-Profiles @('A', 'B')) $fatalStart $probe $stop }
catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -eq 'AUTOPICK_JOB_ASSIGN_FAILED') 'Job assignment failure propagates'
Assert-Sequence $script:Starts @('A') 'Job assignment failure stops selection immediately'
Assert-Sequence $script:Stops @() 'selector does not stop a Process object it never received'
Assert-True ($script:report.Candidates.Count -eq 1 -and $script:report.Candidates[0].Error -eq 'AUTOPICK_JOB_ASSIGN_FAILED') 'fatal startup outcome is recorded'
Write-Output 'PASS: fatal Job assignment failure aborts without any later startup'

Reset-Fixture
$cleanupFailure = { param($process) [void]$script:Stops.Add($process.Name); throw 'FIXTURE_CLEANUP_FAILURE' }
$thrown = $null
try { $null = Select-Profile @(Test-Profiles @('A', 'B')) $start $probe $cleanupFailure }
catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -eq 'FIXTURE_CLEANUP_FAILURE') 'failed cleanup is fatal'
Assert-Sequence $script:Starts @('A') 'no later trial starts after cleanup failure'
Assert-Sequence $script:Stops @('A') 'cleanup failure is not retried or hidden by selection'
Write-Output 'PASS: cleanup failure aborts instead of starting another process'

Reset-Fixture
$script:AlreadyExited = @{ 'A' = $true }
$script:Answers = @{ 'B/fixed' = $true; 'B/normal' = $true }
$selected = Select-Profile @(Test-Profiles @('A', 'B')) $start $probe $stop
Assert-True ($selected.Profile.Name -eq 'B') 'an already-exited startup is rejected'
Assert-Sequence $script:Probes @('B/fixed', 'B/normal') 'no HTTPS request is attributed to an exited trial'
Assert-Sequence $script:Stops @('A') 'exited trial is handed to cleanup once'
Write-Output 'PASS: exited startup is rejected before probing'

Reset-Fixture
$script:Answers = @{ 'A/fixed' = $true; 'A/normal' = $true; 'B/fixed' = $true; 'B/normal' = $true }
$script:ExitDuringProbe = @{ 'A/normal' = $true }
$selected = Select-Profile @(Test-Profiles @('A', 'B', 'C')) $start $probe $stop
Assert-True ($selected.Profile.Name -eq 'B' -and -not $selected.Process.HasExited) 'dead process cannot be retained after successful HTTP probes'
Assert-Sequence $script:Starts @('A', 'B') 'selection continues after a process exits during probes and stops after live winner'
Assert-Sequence $script:Stops @('A') 'process that exits during probes is cleaned up once'
Assert-True ($script:report.Candidates[0].FixedAddress.Success -and $script:report.Candidates[0].NormalDns.Success -and -not $script:report.Candidates[0].Passed -and [bool]$script:report.Candidates[0].Error) 'HTTP success and dead-child rejection remain separately recorded'
Write-Output 'PASS: process exiting during successful probes is rejected; a live subsequent winner is retained'

# Check real generated arguments against the upstream Google-TCP rules, while
# independently enforcing capture/hostlist boundaries for every candidate.
$directory = "/tmp/Zapret путь ! ' & fixture"
$profiles = @(Get-Profiles $directory)
Assert-True ($profiles.Count -eq 4 -and @($profiles.Name | Select-Object -Unique).Count -eq 4) 'four distinct candidate profiles'
$upstream = @{
    'BASE-MULTISPLIT' = 'general.bat'
    'FAKE-TLS-AUTO-ALT' = 'general (FAKE TLS AUTO ALT).bat'
    'ALT8-FAKE' = 'general (ALT8).bat'
    'ALT7-SNI-SPLIT' = 'general (ALT7).bat'
}
foreach ($profile in $profiles) {
    $arguments = @($profile.Arguments)
    Assert-True (@($arguments | Where-Object { $_ -eq '--new' }).Count -eq 1) 'exactly two profiles'
    Assert-True ($arguments -contains '--wf-tcp=443' -and $arguments -contains '--wf-udp=443') 'only required capture ports are present'
    Assert-True (@($arguments | Where-Object { $_ -like '--wf-*' }).Count -eq 2) 'no extra capture range'
    Assert-True (@($arguments | Where-Object { $_ -match '^--(?:ipset|hostlist-auto|dpi-desync-any-protocol)' }).Count -eq 0) 'no broad IPSet, autolist or unknown-protocol mode'
    $expectedHost = '--hostlist=' + [char]34 + (Join-Path $directory 'lists/list-youtube-optimized.txt') + [char]34
    Assert-True (@($arguments | Where-Object { $_ -eq $expectedHost }).Count -eq 2) 'both protocol profiles share the same quoted YouTube hostlist'
    foreach ($argument in $arguments) {
        if ($argument -match '^--(?:hostlist|dpi-desync-fake-quic|dpi-desync-split-seqovl-pattern)=') {
            $value = $argument.Split('=', 2)[1]
            Assert-True ($value.StartsWith('"') -and $value.EndsWith('"')) 'native file argument retains literal quotes'
        }
    }
    $split = [Array]::IndexOf([object[]]$arguments, '--new')
    $tcp = @($arguments[($split + 1)..($arguments.Count - 1)] | Where-Object { $_ -match '^--(?:dpi-|ip-id=)' } | ForEach-Object {
        if ($_ -like '--dpi-desync-split-seqovl-pattern=*') { '--dpi-desync-split-seqovl-pattern={PATTERN}' } else { $_ }
    } | Sort-Object)
    $bat = Join-Path '/workspace/zapret-audit/zapret-discord-youtube-1.10.4' $upstream[$profile.Name]
    $line = @(Get-Content -LiteralPath $bat | Where-Object { $_ -match '^--filter-tcp=443 ' })
    Assert-True ($line.Count -eq 1) 'unambiguous upstream Google TCP rule'
    $expected = @([regex]::Matches($line[0], '--[a-z0-9-]+=(?:"[^"]*"|\S+)') | ForEach-Object Value | Where-Object { $_ -match '^--(?:dpi-|ip-id=)' } | ForEach-Object {
        if ($_ -like '--dpi-desync-split-seqovl-pattern=*') { '--dpi-desync-split-seqovl-pattern={PATTERN}' } else { $_ }
    } | Sort-Object)
    Assert-Sequence $tcp $expected ('TCP strategy matches upstream: ' + $profile.Name)
}
Write-Output 'PASS: four generated profiles preserve upstream TLS flags, narrow port/hostlist scope and special-character path quoting'
Write-Output 'ALL SELECTOR FIXTURE TESTS PASSED; no main Windows branch or Windows binary was executed.'
