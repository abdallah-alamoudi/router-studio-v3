param([string]$Node,[string]$TestName='*')
$ErrorActionPreference='Stop'
if(-not $Node){$Node=(Get-Command node).Source}
$project=Split-Path $PSScriptRoot -Parent
$base=Join-Path ([IO.Path]::GetTempPath()) ('studio contract Ω '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $base|Out-Null
$envBefore=@{};foreach($name in @('LOCALAPPDATA','USERPROFILE','CODEX_HOME','OPENAI_BASE_URL')){$envBefore[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$failures=0;$checks=0;$health=$null
function Assert($condition,$message){if(-not $condition){throw $message}}
function Check($name,[scriptblock]$body){if($name -notlike $script:TestName){return};$script:checks++;try{& $body;Write-Output "PASS: $name"}catch{$script:failures++;Write-Output "FAIL: $name - $($_.Exception.Message)";Write-Output $_.ScriptStackTrace}}
function Fixture {
    $dir=Join-Path $base ([guid]::NewGuid().ToString('N'))
    $root=Join-Path $dir 'local/Safe8stokenRouter';$cp=Join-Path $dir 'user/.codex/config.toml'
    New-Item -ItemType Directory -Path $root,(Split-Path $cp) -Force|Out-Null
    foreach($name in @('provider-switch.mjs','model-manager.mjs','custom-models.mjs','management.mjs')){Copy-Item (Join-Path $project ('src/router/'+$name)) $root}
    $Node|Set-Content (Join-Path $root 'node-path.txt')
    @('model_provider = "safe_8stoken"','model = "gpt-6.1-sol"','','[model_providers.safe_8stoken]','base_url = "http://127.0.0.1:18761/v1"','env_key = "SAFE_8STOKEN_LOCAL_TOKEN"','wire_api = "responses"')|Set-Content $cp
    & $Node (Join-Path $root 'provider-switch.mjs') init $cp $root|Out-Null
    if($LASTEXITCODE){throw 'Fixture initialization failed'}
    @{SAFE_8STOKEN_LOCAL_TOKEN=(ConvertTo-SecureString 'fake-local-token' -AsPlainText -Force);SAFE_8STOKEN_PLUS=(ConvertTo-SecureString 'contract-private-canary' -AsPlainText -Force)}|Export-Clixml (Join-Path $root 'secrets.xml')
    @{defaultKeyEnv='SAFE_8STOKEN_PLUS';aliases=@{}}|ConvertTo-Json|Set-Content (Join-Path $root 'router-config.json')
    @{models=@(@{slug='gpt-6.1-sol';supported_reasoning_levels=@(@{effort='medium'},@{effort='xhigh'})},@{slug='deepseek-v4.1-flash'})}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $root 'codex-router-catalog.json')
    'exit 1'|Set-Content (Join-Path $root 'run-router.ps1')
    return @{dir=$dir;root=$root;cp=$cp;mutex=('Local\RouterStudioTest-'+[guid]::NewGuid().ToString('N'))}
}
function RunWorker($f,$request,[string]$uri=$script:healthUri,$key=$null){
    $job=Join-Path $f.dir ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $job|Out-Null
    $request|ConvertTo-Json -Depth 20|Set-Content (Join-Path $job 'request.json')
    if($key){$key|Export-Clixml (Join-Path $job 'key.xml')}
    # Before implementation, adapt a test copy to reach missing-contract failures,
    # rather than failing because the new process parameters do not exist yet.
    $worker=Join-Path $project 'src/worker/Studio-Worker.ps1'
    $source=[IO.File]::ReadAllText($worker)
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
    $names=@($ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$worker,'-Job',$job)
    if($names -contains 'InstallRoot'){
        $args+=@('-InstallRoot',$f.root,'-ConfigPath',$f.cp,'-HealthUri',$uri)
    }else{
        $env:LOCALAPPDATA=Join-Path $f.dir 'local';$env:USERPROFILE=Join-Path $f.dir 'user'
        $source=$source.Replace('http://127.0.0.1:18761/__router/health',$uri).Replace('Local\RouterStudioManagement-',($f.mutex+'-'))
        $worker=Join-Path $f.dir 'baseline-worker.ps1';[IO.File]::WriteAllText($worker,$source)
        $args[4]=$worker
    }
    $ps=(Get-Process -Id $PID).Path
    $output=@(& $ps @args 2>&1)
    Assert ($LASTEXITCODE -eq 0) 'Worker host failed before returning a contract result'
    $r=Get-Content (Join-Path $job 'result.json') -Raw|ConvertFrom-Json
    Assert (($output -join '') -notmatch 'contract-private-canary') 'Credential leaked to worker output'
    Assert ((Get-Content (Join-Path $job 'result.json') -Raw) -notmatch 'contract-private-canary') 'Credential leaked to result'
    Assert (-not(Test-Path (Join-Path $job 'key.xml'))) 'Secret job envelope was not removed'
    return $r
}
try{
    $env:CODEX_HOME=$null;$env:OPENAI_BASE_URL=$null
    $ready=Join-Path $base 'health ready.json'
    $health=Start-Process -FilePath $Node -WindowStyle Hidden -ArgumentList ('"'+(Join-Path $PSScriptRoot 'health-fixture.mjs')+'" --port 0 --ready-file "'+$ready+'"') -PassThru -RedirectStandardOutput (Join-Path $base 'health.out') -RedirectStandardError (Join-Path $base 'health.err')
    for($i=0;$i -lt 50 -and -not(Test-Path $ready);$i++){if($health.HasExited){throw 'Health fixture exited'};Start-Sleep -Milliseconds 100}
    Assert (Test-Path $ready) 'Health fixture readiness timed out'
    $info=Get-Content $ready -Raw|ConvertFrom-Json
    $script:healthUri='http://127.0.0.1:'+$info.port+'/__router/health'
    Check 'worker_status_uses_versioned_result_envelope' {
        $f=Fixture;$r=RunWorker $f @{action='status'}
        Assert ($r.schemaVersion -eq 1 -and $r.ok) 'Missing versioned success envelope'
        foreach($field in @('connection','healthy','models','keys','credentials','customModels','backups','message')){Assert ($null -ne $r.data.$field) "Status field missing: $field"}
        Assert ($null -eq $r.error -and $r.data.connection.selected -eq 'router' -and $r.data.connection.provider -eq 'safe_8stoken') 'Success envelope is not a router status result'
    }
    Check 'unknown_action_is_safe' {
        $r=RunWorker (Fixture) @{action='contract-private-canary'}
        Assert ($r.schemaVersion -eq 1 -and -not $r.ok -and $r.error.code -eq 'invalid_request') 'Unknown action was not a controlled error'
    }
    Check 'error_canary_not_returned' {
        $f=Fixture;'console.error("contract-private-canary");process.exit(1);'|Set-Content (Join-Path $f.root 'provider-switch.mjs')
        $r=RunWorker $f @{action='status'}
        Assert (-not $r.ok -and $r.error.code -eq 'operation_failed' -and $r.error.message) 'Expected generic controlled Node error'
    }
    Check 'concurrent_mutation_refused' {
        $f=Fixture;$rootHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($f.root).ToUpperInvariant())))
        $mutex=[Threading.Mutex]::new($false,('Local\RouterStudioManagement-'+$env:USERNAME+'-test-'+$rootHash))
        $held=$mutex.WaitOne(0)
        try{$before=[IO.File]::ReadAllText($f.cp);$r=RunWorker $f @{action='official'};Assert (-not $r.ok -and $r.error.code -eq 'busy') 'Second mutation was not refused';Assert ([IO.File]::ReadAllText($f.cp) -eq $before) 'Busy mutation wrote config'}
        finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
    }
    Check 'interrupted_key_save_reports_restart_required' {
        $f=Fixture
        foreach($name in @('secrets.xml','router-config.json','codex-router-catalog.json')){Copy-Item (Join-Path $f.root $name) (Join-Path $f.root ($name+'.before-studio-key'))}
        '{"version":1}'|Set-Content (Join-Path $f.root 'studio-key.pending.json')
        '{"bad":true}'|Set-Content (Join-Path $f.root 'router-config.json')
        $r=RunWorker $f @{action='status'}
        Assert ($r.ok -and $r.data.healthy -and $r.data.restartRequired) 'Recovery silently treated live router as current'
        $again=RunWorker $f @{action='status'}
        Assert $again.data.restartRequired 'Restart reminder did not survive another worker'
        Assert (-not(Test-Path (Join-Path $f.root 'studio-key.pending.json'))) 'Legacy recovery marker retained after complete recovery'
    }
    Check 'missing_recovery_backup_is_controlled_and_preserves_files' {
        $f=Fixture;'{"version":1}'|Set-Content (Join-Path $f.root 'studio-key.pending.json');$before=[IO.File]::ReadAllBytes((Join-Path $f.root 'secrets.xml'))
        $r=RunWorker $f @{action='status'}
        Assert (-not $r.ok -and $r.error.code -eq 'recovery_required') 'Missing backup did not report recovery_required'
        Assert ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $f.root 'secrets.xml')))) 'Missing backup modified credentials'
    }
    Check 'snapshot_digest_runtime_and_declared_metadata' {
        $f=Fixture;$r=RunWorker $f @{action='status'}
        Assert ($r.ok -and $r.data.snapshotDigest -match '^[a-f0-9]{64}$') 'Snapshot digest missing'
        Assert ($r.data.runtimeVersions.node -match '^v\d+' -and $r.data.runtimeVersions.powershell) 'Runtime versions missing'
        Assert (($r.data.models[0].supportedReasoningLevels -join ',') -eq 'medium,xhigh') 'Declared reasoning levels lost'
        Assert ($r.data.models[1].supportedReasoningLevels.Count -eq 0) 'Missing metadata was invented'
        $original=$r.data.snapshotDigest
        'unrelated'|Set-Content (Join-Path $f.root 'launcher-error.log')
        Assert ((RunWorker $f @{action='status'}).data.snapshotDigest -eq $original) 'Digest includes unrelated files'
        Add-Content (Join-Path $f.root 'router-config.json') ' '
        Assert ((RunWorker $f @{action='status'}).data.snapshotDigest -ne $original) 'Changed configuration did not invalidate digest'
    }
    Check 'digest_has_independent_byte_and_length_expectation' {
        $f=Fixture;$r=RunWorker $f @{action='status'}
        $code='const fs=require("fs"),c=require("crypto"),h=c.createHash("sha256");for(const f of process.argv.slice(1)){const b=fs.readFileSync(f),n=Buffer.alloc(8);n.writeBigUInt64BE(BigInt(b.length));h.update(n);h.update(b);}console.log(h.digest("hex"));'
        $expected=& $Node -e $code (Join-Path $f.root 'router-config.json') (Join-Path $f.root 'codex-router-catalog.json') (Join-Path $f.root 'secrets.xml')
        Assert ($r.data.snapshotDigest -eq $expected) 'Digest differs from independent length-framed byte calculation'
    }
    Check 'external_config_change_has_controlled_code' {
        $f=Fixture;[IO.File]::WriteAllText($f.cp,([IO.File]::ReadAllText($f.cp).Replace('127.0.0.1:18761','127.0.0.1:9999')))
        $r=RunWorker $f @{action='official'};Assert (-not $r.ok -and $r.error.code -eq 'config_changed') 'Config change was not classified'
    }
    Check 'startup_failure_preserves_committed_key_and_restart_reminder' {
        $f=Fixture;$key=ConvertTo-SecureString 'contract-private-canary' -AsPlainText -Force
        $r=RunWorker $f @{action='save-key';label='CHINESE';ids=@('deepseek-v4.1-flash');ack=$true} 'http://127.0.0.1:1/__router/health' $key
        Assert (-not $r.ok -and $r.error.code -eq 'startup_failed') 'Startup failure not classified'
        $stored=Import-Clixml (Join-Path $f.root 'secrets.xml')
        Assert ($stored.ContainsKey('SAFE_8STOKEN_EXTRA_CHINESE')) 'Committed key was lost after startup failure'
        Assert ((RunWorker $f @{action='status'}).data.restartRequired) 'Committed startup failure lost restart reminder'
    }
    Check 'worker_errors_use_controlled_protocol_messages' {
        . (Join-Path $project 'src/worker/Studio-Protocol.ps1')
        $r=RunWorker (Fixture) @{action='unknown'}
        $expected=GetStudioError 'invalid_request'
        Assert ($r.schemaVersion -eq 1 -and -not $r.ok -and $r.error.code -eq $expected.code) 'Invalid action did not use a controlled envelope'
        Assert ($r.error.message -ceq $expected.message) 'Error text is not from the controlled protocol table'
        $unknown=GetStudioError 'contract-private-canary'
        Assert ($unknown.message -notmatch 'contract-private-canary') 'Protocol echoes untrusted error identifiers'
    }
    Check 'unsupported_schema_and_request_paths_are_not_forwarded' {
        $f=Fixture;$r=RunWorker $f @{action='status';schemaVersion=99}
        Assert (-not $r.ok -and $r.error.code -eq 'unsupported_schema') 'Unsupported schema accepted'
        $r=RunWorker $f @{action='status';InstallRoot='contract-private-canary';ConfigPath='contract-private-canary';HealthUri='https://example.invalid'}
        Assert ($r.ok -and $r.data.models.Count -eq 2) 'Request fields changed process-only boundaries'
        $r=RunWorker $f @{action='status'} 'https://example.invalid/__router/health'
        Assert (-not $r.ok -and $r.error.code -eq 'invalid_request') 'Non-loopback health target accepted'
    }
    Check 'restart_actions_require_acknowledgement' {
        $f=Fixture
        '{"version":1,"id":"00000000000000000000000000000000","reason":"test"}'|Set-Content (Join-Path $f.root 'studio-restart-required.json')
        foreach($action in @('start','router')){
            $r=RunWorker $f @{action=$action}
            Assert (-not $r.ok -and $r.error.code -eq 'acknowledgement_required') 'Restart action did not require acknowledgement'
        }
    }
    Check 'recovery_restores_a_missing_live_file' {
        $f=Fixture
        foreach($name in @('secrets.xml','router-config.json','codex-router-catalog.json')){Copy-Item (Join-Path $f.root $name) (Join-Path $f.root ($name+'.before-studio-key'))}
        '{"version":1}'|Set-Content (Join-Path $f.root 'studio-key.pending.json')
        Remove-Item (Join-Path $f.root 'secrets.xml')
        $r=RunWorker $f @{action='status'}
        Assert ($r.ok -and $r.data.restartRequired) 'Missing live file prevented recovery from complete backups'
    }
    Check 'provider_pending_transaction_recovers_before_status' {
        $f=Fixture
        $before=[IO.File]::ReadAllText($f.cp);$stateBefore=[IO.File]::ReadAllText((Join-Path $f.root 'provider-state.json'))
        & $Node (Join-Path $f.root 'provider-switch.mjs') official $f.cp $f.root|Out-Null
        Assert ($LASTEXITCODE -eq 0) 'Fixture switch failed'
        $after=[IO.File]::ReadAllText($f.cp);$state=Get-Content (Join-Path $f.root 'provider-state.json') -Raw|ConvertFrom-Json
        [IO.File]::WriteAllText((Join-Path $f.root 'provider-state.json'),$stateBefore)
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$previous=[Convert]::ToHexString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($before))).ToLowerInvariant();$next=[Convert]::ToHexString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($after))).ToLowerInvariant()}finally{$hash.Dispose()}
        @{previousHash=$previous;nextHash=$next;state=$state}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $f.root 'provider-state.json.pending')
        $r=RunWorker $f @{action='status'}
        Assert ($r.ok -and -not $r.data.connection.reviewNeeded -and $r.data.restartRequired) 'Pending provider transaction was not recovered and reported'
        Assert (-not(Test-Path (Join-Path $f.root 'provider-state.json.pending'))) 'Pending provider marker remains'
    }
    Check 'digest_changes_for_catalog_and_encrypted_store' {
        $f=Fixture;$original=(RunWorker $f @{action='status'}).data.snapshotDigest
        Add-Content (Join-Path $f.root 'codex-router-catalog.json') ' '
        $catalog=(RunWorker $f @{action='status'}).data.snapshotDigest
        Assert ($catalog -ne $original) 'Catalog change did not invalidate digest'
        $stored=Import-Clixml (Join-Path $f.root 'secrets.xml');$stored.SAFE_8STOKEN_PLUS=ConvertTo-SecureString 'replacement-private-value' -AsPlainText -Force
        $stored|Export-Clixml (Join-Path $f.root 'secrets.xml')
        Assert ((RunWorker $f @{action='status'}).data.snapshotDigest -ne $catalog) 'Encrypted credential change did not invalidate digest'
    }
    Check 'owned_launcher_proves_loaded_snapshot_without_logging_canary' {
        $hosts=@((Get-Process -Id $PID).Path,(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'))
        foreach($launcherHost in $hosts){
        $f=Fixture
        . (Join-Path $project 'src/worker/Studio-Protocol.ps1')
        SetStudioRestartRequired $f.root 'test'
        $socket=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$socket.Start();$port=$socket.LocalEndpoint.Port;$socket.Stop()
        $cfg=Get-Content (Join-Path $f.root 'router-config.json') -Raw|ConvertFrom-Json;$cfg|Add-Member port $port
        $cfg|ConvertTo-Json -Depth 20|Set-Content (Join-Path $f.root 'router-config.json')
        'import http from "node:http";import fs from "node:fs";const cfg=JSON.parse(fs.readFileSync(process.argv[2]));console.error("contract-private-canary");http.createServer((q,s)=>s.end("{\"ok\":true}")).listen(cfg.port,"127.0.0.1");'|Set-Content (Join-Path $f.root 'router.mjs')
        $ps=$launcherHost
        $launcher=Start-Process -FilePath $ps -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $project 'src/worker/run-router.ps1')+'" -InstallRoot "'+$f.root+'" -HealthUri "http://127.0.0.1:'+$port+'/__router/health"') -RedirectStandardOutput (Join-Path $f.dir 'launcher.out') -RedirectStandardError (Join-Path $f.dir 'launcher.err')
        try{
            $stamp=Join-Path $f.root 'router-loaded-snapshot.json'
            for($i=0;$i -lt 70 -and -not(Test-Path $stamp);$i++){if($launcher.HasExited){break};Start-Sleep -Milliseconds 100}
            Assert (Test-Path $stamp) 'Owned launcher did not acknowledge loaded snapshot'
            $digest=GetStudioSnapshotDigest $f.root
            Assert (-not(TestStudioRestartRequired $f.root $digest $true)) 'Matching owned startup did not clear restart marker'
            SetStudioRestartRequired $f.root 'newer_recovery'
            Assert (TestStudioRestartRequired $f.root $digest $true) 'Old startup cleared a newer recovery marker'
        }finally{
            $pidFile=Join-Path $f.root 'router.pid'
            if(Test-Path $pidFile){Stop-Process -Id ([int](Get-Content $pidFile -Raw)) -Force -ErrorAction SilentlyContinue}
            if(-not $launcher.WaitForExit(3000)){Stop-Process -Id $launcher.Id -Force}
            $launcher.Dispose()
        }
            foreach($file in @(Get-ChildItem -LiteralPath $f.root -Filter '*log')+@(Get-Item (Join-Path $f.dir 'launcher.out'),(Join-Path $f.dir 'launcher.err'))){
                $content=[IO.File]::ReadAllText($file.FullName)
                Assert ($content -notmatch 'contract-private-canary') ("Launcher persisted raw child error output: "+$file.Name)
            }
        }
    }
    Check 'acknowledgement_must_be_a_boolean' {
        $f=Fixture;$key=ConvertTo-SecureString 'contract-private-canary' -AsPlainText -Force
        $r=RunWorker $f @{action='save-key';label='CHINESE';ids=@('deepseek-v4.1-flash');ack='false'} $script:healthUri $key
        Assert (-not $r.ok -and $r.error.code -eq 'acknowledgement_required') 'String acknowledgement permitted a mutation'
    }
    Check 'setup_fixture_status_and_errors_do_not_leak_canary' {
        $f=Fixture;$ps=(Get-Process -Id $PID).Path
        $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $project 'src/worker/Setup.ps1'),'-Action','Status','-InstallRoot',$f.root,'-ConfigPath',$f.cp,'-HealthUri',$script:healthUri)
        $out=@(& $ps @args 2>&1)
        Assert ($LASTEXITCODE -eq 0 -and ($out -join '') -match 'Router reachable: True') 'Isolated setup status failed'
        'contract-private-canary'|Set-Content (Join-Path $f.root 'secrets.xml')
        $out=@(& $ps @args 2>&1)
        Assert ($LASTEXITCODE -eq 1 -and ($out -join '') -notmatch 'contract-private-canary') 'Setup returned raw parser error text'
    }
    Check 'health_redirect_is_not_followed' {
        $f=Fixture;$readyFile=Join-Path $f.dir 'redirect ready.json';$redirected=Join-Path $f.dir 'redirect-followed.txt'
        $server=Join-Path $f.dir 'redirect.mjs'
        'import http from "node:http";import fs from "node:fs";const [ready,hit]=process.argv.slice(2);const s=http.createServer((q,r)=>{if(q.url==="/__router/health"){r.writeHead(302,{Location:"/unexpected"});r.end();}else{fs.writeFileSync(hit,"followed");r.end("{\"ok\":true}");}});s.listen(0,"127.0.0.1",()=>fs.writeFileSync(ready,JSON.stringify({port:s.address().port})));'|Set-Content $server
        $owned=Start-Process -FilePath $Node -WindowStyle Hidden -PassThru -ArgumentList ('"'+$server+'" "'+$readyFile+'" "'+$redirected+'"')
        try{
            for($i=0;$i -lt 50 -and -not(Test-Path $readyFile);$i++){if($owned.HasExited){break};Start-Sleep -Milliseconds 100}
            Assert (Test-Path $readyFile) 'Redirect fixture failed to start'
            $port=(Get-Content $readyFile -Raw|ConvertFrom-Json).port
            $r=RunWorker $f @{action='status'} ('http://127.0.0.1:'+$port+'/__router/health')
            Assert ($r.ok -and -not $r.data.healthy -and -not(Test-Path $redirected)) 'Health redirected a credential-bearing local request'
        }finally{if(-not $owned.HasExited){Stop-Process -Id $owned.Id -Force};$owned.Dispose()}
    }
    Check 'launcher_does_not_trust_an_unrelated_health_listener' {
        $f=Fixture
        'setTimeout(()=>process.exit(0),2500);'|Set-Content (Join-Path $f.root 'router.mjs')
        $ps=(Get-Process -Id $PID).Path
        $out=@(& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'src/worker/run-router.ps1') -InstallRoot $f.root -HealthUri $script:healthUri 2>&1)
        Assert ($LASTEXITCODE -eq 1) 'Launcher accepted another process health response'
        Assert (-not(Test-Path (Join-Path $f.root 'router-loaded-snapshot.json'))) 'Unrelated health response acknowledged a snapshot'
        Assert (($out -join '') -notmatch 'contract-private-canary') 'Launcher failed unsafely'
    }
    Check 'review_fresh_setup_prepares_catalog_before_startup' {
        $f=Fixture
        $source=Join-Path (Split-Path $f.cp) '8stoken-model-catalog.json'
        Copy-Item (Join-Path $f.root 'codex-router-catalog.json') $source
        Remove-Item (Join-Path $f.root 'codex-router-catalog.json')
        [IO.File]::WriteAllText($f.cp,([IO.File]::ReadAllText($f.cp).Replace('http://127.0.0.1:18761/v1','https://8stoken.com/v1')))
        $cfg=Get-Content (Join-Path $f.root 'router-config.json') -Raw|ConvertFrom-Json;$cfg|Add-Member port 18761
        $cfg|ConvertTo-Json -Depth 20|Set-Content (Join-Path $f.root 'router-config.json')
        $before=[IO.File]::ReadAllText($f.cp)
        $out=@(& $Node (Join-Path $project 'src/router/codex-config.mjs') enable-extreme $f.cp $f.root 2>&1)
        Assert ($LASTEXITCODE -eq 0) 'Fresh preparation failed'
        Assert (Test-Path (Join-Path $f.root 'codex-router-catalog.json')) 'Fresh startup catalog was not prepared'
        Assert ([IO.File]::ReadAllText($f.cp) -eq $before) 'Preparation changed Codex config before startup'
        . (Join-Path $project 'src/worker/Studio-Protocol.ps1')
        Assert ((GetStudioSnapshotDigest $f.root) -match '^[a-f0-9]{64}$') 'Prepared installation cannot supply startup digest'
        Assert (-not(Test-Path (Join-Path $f.root 'rollback.json'))) 'Preparation committed installation state early'
    }
    Check 'review_worker_forwards_isolation_to_real_launcher' {
        $f=Fixture
        foreach($name in @('run-router.ps1','Studio-Protocol.ps1')){Copy-Item (Join-Path $project ('src/worker/'+$name)) $f.root -Force}
        $socket=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$socket.Start();$port=$socket.LocalEndpoint.Port;$socket.Stop()
        $cfg=Get-Content (Join-Path $f.root 'router-config.json') -Raw|ConvertFrom-Json;$cfg|Add-Member port $port
        $cfg|ConvertTo-Json -Depth 20|Set-Content (Join-Path $f.root 'router-config.json')
        'import http from "node:http";import fs from "node:fs";const cfg=JSON.parse(fs.readFileSync(process.argv[2]));http.createServer((q,s)=>s.end("{\"ok\":true}")).listen(cfg.port,"127.0.0.1");'|Set-Content (Join-Path $f.root 'router.mjs')
        try{
            $key=ConvertTo-SecureString 'contract-private-canary' -AsPlainText -Force
            $r=RunWorker $f @{action='save-key';label='CHINESE';ids=@('deepseek-v4.1-flash');ack=$true} ('http://127.0.0.1:'+$port+'/__router/health') $key
            Assert ($r.ok -and $r.data.healthy -and -not $r.data.restartRequired -and $r.data.routerHealth.configurationCurrent) 'Real worker/launcher composition did not start isolated snapshot'
        }finally{
            $pidFile=Join-Path $f.root 'router.pid'
            if(Test-Path $pidFile){
                $nodeId=[int](Get-Content $pidFile -Raw)
                $childInfo=Get-CimInstance Win32_Process -Filter "ProcessId=$nodeId" -ErrorAction SilentlyContinue
                Stop-Process -Id $nodeId -Force -ErrorAction SilentlyContinue
                if($childInfo){Wait-Process -Id $childInfo.ParentProcessId -Timeout 5 -ErrorAction SilentlyContinue}
            }
        }
    }
    Check 'review_provider_recovery_reminder_survives_worker_termination' {
        $f=Fixture;$pending=Join-Path $f.root 'provider-state.json.pending';'{}'|Set-Content $pending
        # Terminate only this test's worker parent immediately after simulated Node
        # recovery deletes its pending file. The controlling test process stays alive.
        'import fs from "node:fs";import path from "node:path";fs.unlinkSync(path.join(process.argv[4],"provider-state.json.pending"));process.kill(process.ppid,"SIGKILL");process.exit(0);'|Set-Content (Join-Path $f.root 'provider-switch.mjs')
        $job=Join-Path $f.dir 'interrupted job';New-Item -ItemType Directory -Path $job|Out-Null
        '{"action":"status"}'|Set-Content (Join-Path $job 'request.json')
        $ps=(Get-Process -Id $PID).Path
        $out=@(& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'src/worker/Studio-Worker.ps1') -Job $job -InstallRoot $f.root -ConfigPath $f.cp -HealthUri $script:healthUri 2>&1)
        Assert (-not(Test-Path $pending)) 'Termination fixture did not reach provider recovery'
        Assert (Test-Path (Join-Path $f.root 'studio-restart-required.json')) 'Provider recovery lost durable reminder on termination'
        Copy-Item (Join-Path $project 'src/router/provider-switch.mjs') $f.root -Force
        $r=RunWorker $f @{action='status'}
        Assert ($r.ok -and $r.data.restartRequired) 'Next worker forgot interrupted provider recovery'
    }
    Check 'versioned_payload_key_save_and_legacy_requests_are_compatible' {
        $f=Fixture
        Copy-Item (Join-Path $project 'src/worker/Studio-Protocol.ps1') $f.root
        $launcher=@'
. (Join-Path $PSScriptRoot 'Studio-Protocol.ps1')
$marker=Get-Content (Join-Path $PSScriptRoot 'studio-restart-required.json') -Raw|ConvertFrom-Json
WriteStudioJson (Join-Path $PSScriptRoot 'router-loaded-snapshot.json') @{schemaVersion=1;markerId=$marker.id;snapshotDigest=(GetStudioSnapshotDigest $PSScriptRoot)}
'@
        [IO.File]::WriteAllText((Join-Path $f.root 'run-router.ps1'),$launcher)
        $key=ConvertTo-SecureString 'contract-private-canary' -AsPlainText -Force
        $r=RunWorker $f @{schemaVersion=1;action='save-key';payload=@{label='CHINESE';ids=@('deepseek-v4.1-flash');ack=$true}} $script:healthUri $key
        Assert ($r.ok -and -not $r.data.restartRequired) 'Versioned payload mutation failed'
        Assert ((Import-Clixml (Join-Path $f.root 'secrets.xml')).ContainsKey('SAFE_8STOKEN_EXTRA_CHINESE')) 'Payload did not assign credential'
        Assert ((RunWorker $f @{action='status'}).ok) 'Legacy flat request stopped working'
    }
    Check 'versioned_payload_conflicting_or_invalid_input_is_refused' {
        $f=Fixture
        foreach($request in @(@{schemaVersion=1;action='save-key';ack=$true;payload=@{ack=$false}},@{schemaVersion=1;action='status';payload='contract-private-canary'})){
            $r=RunWorker $f $request
            Assert (-not $r.ok -and $r.error.code -eq 'invalid_request') 'Ambiguous/invalid payload was not refused'
        }
    }
    if(-not $checks){throw 'No contract tests selected'}
    Write-Output "CONTRACT: $checks checks; $failures failures."
}finally{
    if($health -and -not $health.HasExited){Stop-Process -Id $health.Id -Force}
    foreach($name in $envBefore.Keys){[Environment]::SetEnvironmentVariable($name,$envBefore[$name],'Process')}
    $resolved=[IO.Path]::GetFullPath($base);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if($failures){exit 1}
