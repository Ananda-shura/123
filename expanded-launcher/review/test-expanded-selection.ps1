param([string]$Source=(Join-Path $PSScriptRoot '../expanded/expanded.ps1'))
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors -join '; ')}
$functions=@($ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
foreach($name in @('Get-Profiles','Get-TlsFlags','Convert-TelegramCidrText','Get-CombinedProfile','Restart-Combined','Select-ServiceMethod','Test-ControlRegression')){
    $found=@($functions|Where-Object{$_.Name -eq $name})
    if($found.Count -ne 1){throw ('Missing/ambiguous function: '+$name)}
    . ([scriptblock]::Create($found[0].Extent.Text))
}
function Check($Condition,[string]$Message){if(-not $Condition){throw ('ASSERTION: '+$Message)}}
function Equal-Sequence($Actual,$Expected,[string]$Message){Check ((@($Actual)-join '|') -ceq (@($Expected)-join '|')) $Message}
function Expect-Throw([scriptblock]$Action,[string]$Message){$thrown=$false;try{&$Action|Out-Null}catch{$thrown=$true};Check $thrown $Message}

$fixture=Join-Path ([IO.Path]::GetTempPath()) ("expanded путь ! ' & "+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
try{
    $script:Root=$fixture
    $script:telegramSet=Join-Path $fixture 'telegram-bootstrap.txt'
    $bundleRoot=Split-Path -Parent (Split-Path -Parent $Source)
    Copy-Item -LiteralPath (Join-Path $bundleRoot 'lists/telegram-bootstrap-ipset.txt') -Destination $script:telegramSet
    $methods=@(Get-Profiles $fixture)
    Check ($methods.Count -eq 4) 'four source methods'
    $q=[char]34
    foreach($ytMethod in $methods){
        foreach($serviceMethod in $methods){
            $combined=Get-CombinedProfile $ytMethod $serviceMethod $methods[0] $fixture $script:telegramSet
            $a=@($combined.Arguments)
            Equal-Sequence $a[0..($ytMethod.Arguments.Count-1)] $ytMethod.Arguments 'selected YouTube byte-for-byte argument prefix survives every service combination'
            Check ($a[$ytMethod.Arguments.Count] -eq '--new') 'extra services start after complete YouTube profiles'
            Check (@($a|Where-Object{$_ -like '--wf-*'}).Count -eq 2) 'no service broadens capture ports'
            Check ($a -contains '--wf-tcp=443' -and $a -contains '--wf-udp=443') 'capture remains TCP/UDP443'
            $groups=New-Object 'Collections.Generic.List[object]'
            $group=New-Object 'Collections.Generic.List[string]'
            foreach($arg in $a){if($arg -eq '--new'){[void]$groups.Add($group.ToArray());$group.Clear()}else{[void]$group.Add($arg)}}
            [void]$groups.Add($group.ToArray())
            Check ($groups.Count -eq 6) 'two YouTube plus four service profiles'
            foreach($g in $groups){
                Check (@($g|Where-Object{$_ -like '--filter-*'}).Count -gt 0) 'no empty/catch-all group'
                Check (@($g|Where-Object{$_ -like '--hostlist=*' -or $_ -like '--ipset=*'}).Count -gt 0) 'every modifying group has a domain or IP selector'
            }
            $native=$groups[$groups.Count-1]
            Check ($native -contains '--filter-tcp=443' -and $native -contains '--filter-l7=unknown') 'native Telegram is unknown-L7 TCP443 only'
            Check ($native -contains ('--ipset='+$q+$script:telegramSet+$q)) 'native Telegram uses exact validated quoted IPSet path'
            Check (@($a|Where-Object{$_ -eq '--dpi-desync-any-protocol=1'}).Count -eq 1 -and $native -contains '--dpi-desync-any-protocol=1') 'any-protocol is confined to native Telegram IPSet group'
        }
    }
    Write-Output 'PASS: selected YouTube prefix survives all 16 service combinations; capture and native-IPSet scope remain constrained'

    $noYoutube=[pscustomobject]@{Name='NO-YOUTUBE-DESYNC';Arguments=@('--wf-tcp=443','--wf-udp=443')}
    foreach($method in $methods){
        $combined=Get-CombinedProfile $noYoutube $method $method $fixture $script:telegramSet
        $a=@($combined.Arguments)
        Equal-Sequence $a[0..2] @('--wf-tcp=443','--wf-udp=443','--filter-udp=443') 'no-YouTube branch starts directly with a scoped service filter'
        Check (@($a|Where-Object{$_ -eq '--new'}).Count -eq 3) 'no-YouTube branch has four service groups, no empty leading group'
        Check (@($a|Where-Object{$_ -like '*list-youtube-optimized*'}).Count -eq 0) 'no-YouTube branch does not add YouTube desync'
    }
    Write-Output 'PASS: no-YouTube-needed mode has no leading empty/catch-all profile'

    foreach($path in @($null,'',(Join-Path $fixture 'missing.txt'))){
        $bad=$path
        Expect-Throw {Get-CombinedProfile $methods[0] $methods[0] $methods[0] $fixture $bad} 'missing Telegram selector must refuse assembly'
    }
    foreach($text in @('',"# comment only`n",'0.0.0.0/0','::/0','127.0.0.1/32','not-a-network','<html><body>upstream error</body></html>')){
        $bad=Join-Path $fixture 'bad-set.txt';[IO.File]::WriteAllText($bad,$text)
        Expect-Throw {Get-CombinedProfile $methods[0] $methods[0] $methods[0] $fixture $bad} 'empty/broad/malformed Telegram selector must refuse assembly'
    }
    Write-Output 'PASS: missing, empty, comment-only, catch-all, loopback, malformed and HTML native IPSets refuse assembly'

    function Reset-ServiceFixture {
        $script:report=[ordered]@{WebAttempts=@()}
        $script:current=@{Process=$null}
        $script:Started=New-Object 'Collections.Generic.List[object]'
        $script:Stopped=New-Object 'Collections.Generic.List[int]'
        $script:Replies=New-Object 'Collections.Generic.Queue[object]'
        $script:FatalStartAt=0
        $script:StopThrows=$false
    }
    function Start-Tracked($Profile){
        $n=$script:Started.Count+1
        [void]$script:Started.Add($Profile)
        if($n -eq $script:FatalStartAt){throw 'AUTOPICK_JOB_ASSIGN_FAILED'}
        [pscustomobject]@{Token=$n;HasExited=$false}
    }
    function Stop-Owned($Process){
        if($null -ne $Process){
            [void]$script:Stopped.Add([int]$Process.Token)
            if($script:StopThrows){throw 'FIXTURE_CLEANUP_FAILED'}
            $Process.HasExited=$true
        }
    }
    function Invoke-ServiceHttps([string]$Url,[switch]$Body){
        if(-not $script:Replies.Count){throw 'FIXTURE_NO_REPLY'}
        $reply=$script:Replies.Dequeue()
        if($reply -is [string]){throw $reply}
        if($reply.ExitDuring){$script:current.Process.HasExited=$true}
        return $reply
    }
    function Reply([int]$Http,[bool]$Reached,[bool]$ExitDuring=$false){
        [pscustomobject]@{HttpCode=$Http;ResponseReached=$Reached;AppVerified=$false;ExitDuring=$ExitDuring}
    }

    Reset-ServiceFixture
    $script:Replies.Enqueue((Reply 403 $true))
    $winner=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $methods $methods[0] $methods[0] $methods[0]
    Check ($winner.Name -eq $methods[0].Name) 'HTTP403 can select an HTTP-reachable method'
    Check ($script:Started.Count -eq 1 -and $script:Stopped.Count -eq 0 -and -not $script:current.Process.HasExited) 'HTTP403 winner is retained and no later trial runs'
    Check ($script:report.WebAttempts.Count -eq 1 -and $script:report.WebAttempts[0].Result.HttpCode -eq 403 -and -not $script:report.WebAttempts[0].Result.AppVerified) 'HTTP403 never becomes application verified'
    Write-Output 'PASS: HTTP403 retains a reached transport method while AppVerified remains false'

    Reset-ServiceFixture
    $script:Replies.Enqueue((Reply 0 $false));$script:Replies.Enqueue((Reply 200 $true))
    $winner=Select-ServiceMethod 'TelegramWeb' 'https://core.telegram.org/' $methods $methods[0] $methods[0] $methods[0]
    Check ($winner.Name -eq $methods[1].Name -and $script:Started.Count -eq 2) 'ordinary failure proceeds to next service method'
    Equal-Sequence $script:Stopped @(1) 'rejected process stopped once; winner retained'
    Check ($script:current.Process.Token -eq 2 -and -not $script:current.Process.HasExited) 'live next winner remains current'
    Check ($script:report.WebAttempts.Count -eq 2) 'attempts recorded exactly once'
    Write-Output 'PASS: failed service candidate cleans up once and later winner stays live'

    Reset-ServiceFixture
    foreach($m in $methods){$script:Replies.Enqueue((Reply 0 $false))}
    $winner=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $methods $methods[0] $methods[0] $methods[0]
    Check ($null -eq $winner -and $null -eq $script:current.Process) 'all-failure returns no winner and no dangling trial'
    Equal-Sequence $script:Stopped @(1,2,3,4) 'each failed child stops exactly once including last'
    Check ($script:report.WebAttempts.Count -eq 4) 'all failures recorded'
    Write-Output 'PASS: all failing service methods leave no trial running'

    Reset-ServiceFixture
    $script:Replies.Enqueue('FIXTURE_PROBE_FAILURE');$script:Replies.Enqueue((Reply 403 $true))
    $winner=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $methods $methods[0] $methods[0] $methods[0]
    Check ($winner.Name -eq $methods[1].Name -and $script:report.WebAttempts[0].Error -eq 'FIXTURE_PROBE_FAILURE') 'probe exception recorded and later candidate tried'
    Equal-Sequence $script:Stopped @(1) 'probe-exception child cleaned once'
    Write-Output 'PASS: service probe exception cleans up its trial and is recorded'

    Reset-ServiceFixture
    $script:FatalStartAt=1
    $caught=$null
    try{$null=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $methods $methods[0] $methods[0] $methods[0]}catch{$caught=$_.Exception.Message}
    Check ($caught -eq 'AUTOPICK_JOB_ASSIGN_FAILED' -and $script:Started.Count -eq 1) 'fatal Job failure aborts without later startup'
    Check ($script:report.WebAttempts.Count -eq 1 -and $script:report.WebAttempts[0].Error -eq 'AUTOPICK_JOB_ASSIGN_FAILED') 'fatal attempt recorded once'
    Write-Output 'PASS: fatal service Job-assignment failure aborts immediately'

    Reset-ServiceFixture
    $script:StopThrows=$true;$script:Replies.Enqueue((Reply 0 $false))
    $caught=$null
    try{$null=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $methods $methods[0] $methods[0] $methods[0]}catch{$caught=$_.Exception.Message}
    Check ($caught -eq 'FIXTURE_CLEANUP_FAILED' -and $script:Started.Count -eq 1) 'cleanup failure is fatal rather than starting another process'
    Write-Output 'PASS: failed cleanup aborts service selection'

    Reset-ServiceFixture
    $script:Replies.Enqueue((Reply 200 $true $true));$script:Replies.Enqueue((Reply 403 $true))
    $winner=Select-ServiceMethod 'ChatGPT' 'https://chatgpt.com/' $methods $methods[0] $methods[0] $methods[0]
    Check ($winner.Name -eq $methods[1].Name) 'exited process is not selected even if HTTP response reached'
    Equal-Sequence $script:Stopped @(1) 'exited candidate is cleaned once'
    Write-Output 'PASS: service child exiting during probe cannot become a winner'

    foreach($status in @(403,500,0)){
        Check (Test-ControlRegression (Reply 200 $true) (Reply $status ($status -ne 0))) 'loss of baseline page counts as regression'
    }
    Check (-not (Test-ControlRegression (Reply 200 $true) (Reply 302 $true))) 'successful redirect is not a regression'
    Check (-not (Test-ControlRegression (Reply 403 $true) (Reply 403 $true))) 'unchanged prior denial is not a new regression'
    Check (Test-ControlRegression (Reply 403 $true) (Reply 0 $false)) 'loss of any previously reached response is a regression'
    Write-Output 'PASS: control regressions include baseline2xx/3xx becoming HTTP403/500/unreachable'
    Write-Output 'ALL EXPANDED SELECTION FIXTURES PASSED; no main Windows branch or network/native process executed.'
}finally{
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
