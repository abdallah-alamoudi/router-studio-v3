param([string]$Node,[ValidateRange(0,65535)][int]$HealthPort=18761)
$ErrorActionPreference='Stop'
if(-not $Node){$Node=(Get-Command node -ErrorAction Stop).Source}
if(-not(Test-Path -LiteralPath $Node -PathType Leaf)){throw 'Node executable was not found.'}
# A bind-check also works without process inventory permissions.
if($HealthPort -ne 0){
    $preflight=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$HealthPort)
    $preflight.ExclusiveAddressUse=$true
    try{$preflight.Start()}
    catch [Net.Sockets.SocketException]{
        if($_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::AddressAlreadyInUse){
            Write-Output "INTEGRATION: SKIP - health port $HealthPort is occupied; no existing listener was stopped."
            exit 0
        }
        throw
    }finally{$preflight.Stop()}
}
$base=Join-Path ([IO.Path]::GetTempPath()) ('studio test Ω '+[guid]::NewGuid().ToString('N'))
$originalEnvironment=@{}
foreach($name in @('LOCALAPPDATA','USERPROFILE','OPENAI_BASE_URL','CODEX_HOME')){
    $originalEnvironment[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}
$healthProcess=$null
$assertions=0
$project=Split-Path $PSScriptRoot -Parent
function Assert($ok,$name){if(-not $ok){throw "FAILED: $name"};$script:assertions++;Write-Output "PASS: $name"}
function Job($request,$key=$null){
    $j=Join-Path $base ([guid]::NewGuid().ToString('N'));New-Item $j -ItemType Directory|Out-Null
    $request|ConvertTo-Json -Depth 20|Set-Content (Join-Path $j 'request.json')
    if($key){$key|Export-Clixml (Join-Path $j 'key.xml')}
    & $workerPath -Job $j -InstallRoot $root -ConfigPath (Join-Path $codex 'config.toml') -HealthUri $workerHealthUri
    return (Get-Content (Join-Path $j 'result.json') -Raw|ConvertFrom-Json)
}
try{
    $env:LOCALAPPDATA=Join-Path $base 'local';$env:USERPROFILE=Join-Path $base 'user'
    [Environment]::SetEnvironmentVariable('OPENAI_BASE_URL',$null,'Process')
    [Environment]::SetEnvironmentVariable('CODEX_HOME',$null,'Process')
    $root=Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter';$codex=Join-Path $env:USERPROFILE '.codex'
    New-Item $root,$codex -ItemType Directory -Force|Out-Null
    foreach($name in @('provider-switch.mjs','model-manager.mjs','custom-models.mjs','management.mjs','Studio-Protocol.ps1')){$source=if($name -eq 'Studio-Protocol.ps1'){Join-Path $project 'src/worker/Studio-Protocol.ps1'}else{Join-Path $project ('src/router/'+$name)};Copy-Item $source (Join-Path $root $name)}
    $Node|Set-Content (Join-Path $root 'node-path.txt')
    @('model_provider = "safe_8stoken"','model = "gpt-6.1-sol"','','[model_providers.safe_8stoken]','base_url = "http://127.0.0.1:18761/v1"','env_key = "SAFE_8STOKEN_LOCAL_TOKEN"','wire_api = "responses"') | Set-Content (Join-Path $codex 'config.toml')
    & $Node (Join-Path $root 'provider-switch.mjs') init (Join-Path $codex 'config.toml') $root|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Fixture switcher initialization failed.'}
    @{SAFE_8STOKEN_LOCAL_TOKEN=(ConvertTo-SecureString 'fake-local-token' -AsPlainText -Force);SAFE_8STOKEN_PLUS=(ConvertTo-SecureString 'fake-plus-key' -AsPlainText -Force)}|Export-Clixml (Join-Path $root 'secrets.xml')
    @{defaultKeyEnv='SAFE_8STOKEN_PLUS';aliases=@{}}|ConvertTo-Json|Set-Content (Join-Path $root 'router-config.json')
    @{models=@(@{slug='gpt-6.1-sol';supported_reasoning_levels=@(@{effort='medium'},@{effort='xhigh'})},@{slug='deepseek-v4.1-flash'})}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $root 'codex-router-catalog.json')
    $readyFile=Join-Path $base 'health ready.json'
    $healthProcess=Start-Process -FilePath $Node -WindowStyle Hidden -ArgumentList ('"'+(Join-Path $PSScriptRoot 'health-fixture.mjs')+'" --port '+$HealthPort+' --ready-file "'+$readyFile+'"') -PassThru -RedirectStandardError (Join-Path $base 'health-error.txt') -RedirectStandardOutput (Join-Path $base 'health-output.txt')
    for($attempt=0;$attempt -lt 50 -and -not(Test-Path -LiteralPath $readyFile);$attempt++){
        if($healthProcess.HasExited){throw 'Health fixture failed to start. No existing listener was stopped.'}
        Start-Sleep -Milliseconds 100
    }
    if(-not(Test-Path -LiteralPath $readyFile)){throw 'Health fixture startup timed out.'}
    $ready=Get-Content -LiteralPath $readyFile -Raw|ConvertFrom-Json
    if($ready.pid -ne $healthProcess.Id -or $ready.port -lt 1 -or $ready.port -gt 65535){throw 'Invalid health fixture readiness.'}
    $workerPath=Join-Path $project 'src/worker/Studio-Worker.ps1'
    $workerHealthUri='http://127.0.0.1:'+$ready.port+'/__router/health'
    # Simulate only the launcher acknowledgement; the health service stays owned by
    # this harness. No installed router or product file is adapted or started.
    $testLauncher=@'
. (Join-Path $PSScriptRoot 'Studio-Protocol.ps1')
$marker=Get-Content (Join-Path $PSScriptRoot 'studio-restart-required.json') -Raw|ConvertFrom-Json
WriteStudioJson (Join-Path $PSScriptRoot 'router-loaded-snapshot.json') @{schemaVersion=1;markerId=$marker.id;snapshotDigest=(GetStudioSnapshotDigest $PSScriptRoot)}
'@
    [IO.File]::WriteAllText((Join-Path $root 'run-router.ps1'),$testLauncher)
    $r=Job @{action='status'};Assert $r.ok 'status worker succeeds with absent modelRoutes';Assert ($r.data.models.Count -eq 2) 'catalog rows returned';Assert (($r|ConvertTo-Json -Depth 20) -notmatch 'fake-plus-key|fake-local-token') 'status omits fake credentials'
    $r=Job @{action='official'};Assert $r.ok 'official switch worker';Assert ($r.data.connection.selected -eq 'official') 'actual configuration reports official'
    $r=Job @{action='save-key';label='CHINESE';ids=@('deepseek-v4.1-flash');ack=$false} (ConvertTo-SecureString 'fake-key' -AsPlainText -Force);Assert (-not $r.ok) 'key save requires acknowledgement'
    $r=Job @{action='restore';id='../config.toml';ack=$true};Assert (-not $r.ok) 'restore rejects traversal'
    $r=Job @{action='save-key';label='CHINESE';ids=@('deepseek-v4.1-flash');ack=$true} (ConvertTo-SecureString 'fake-chinese-private-key' -AsPlainText -Force)
    Assert $r.ok 'key save worker completes against local health fixture'
    $routes=Get-Content (Join-Path $root 'router-config.json') -Raw|ConvertFrom-Json
    Assert ($routes.modelRoutes.'deepseek-v4.1-flash' -eq 'SAFE_8STOKEN_EXTRA_CHINESE') 'selected exact model assigned to key'
    $stored=Import-Clixml (Join-Path $root 'secrets.xml')
    Assert ($stored.ContainsKey('SAFE_8STOKEN_EXTRA_CHINESE')) 'credential persisted as SecureString'
    Assert (($r|ConvertTo-Json -Depth 20) -notmatch 'fake-chinese-private-key') 'key save response omits credential'
    $files=@('secrets.xml','router-config.json','codex-router-catalog.json');foreach($f in $files){Copy-Item (Join-Path $root $f) (Join-Path $root ($f+'.before-studio-key'))}
    '{"version":1}'|Set-Content (Join-Path $root 'studio-key.pending.json');'{"bad":true}'|Set-Content (Join-Path $root 'router-config.json')
    $r=Job @{action='status'};Assert $r.ok 'interrupted key save recovers before status';Assert (-not(Test-Path (Join-Path $root 'studio-key.pending.json'))) 'recovery marker removed'
    if($assertions -ne 13){throw 'Worker assertion count changed unexpectedly.'}
    Write-Output "INTEGRATION: PASS - $assertions assertions; fake keys and isolated user data only."
}finally{
    if($healthProcess -and -not $healthProcess.HasExited){Stop-Process -Id $healthProcess.Id -Force}
    foreach($name in $originalEnvironment.Keys){[Environment]::SetEnvironmentVariable($name,$originalEnvironment[$name],'Process')}
    if(Test-Path -LiteralPath $base){
        $resolvedBase=[IO.Path]::GetFullPath($base)
        $resolvedTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
        if(-not $resolvedBase.StartsWith($resolvedTemp,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing to remove a test directory outside TEMP.'}
        Remove-Item -LiteralPath $resolvedBase -Recurse -Force
    }
}
