param(
    [Parameter(Mandatory)][string]$Job,
    [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter'),
    [string]$ConfigPath=(Join-Path $env:USERPROFILE '.codex\config.toml'),
    [uri]$HealthUri='http://127.0.0.1:18761/__router/health'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Studio-Protocol.ps1')
$root=[IO.Path]::GetFullPath($InstallRoot);$cp=[IO.Path]::GetFullPath($ConfigPath)
$testMode=$PSBoundParameters.ContainsKey('InstallRoot') -or $PSBoundParameters.ContainsKey('ConfigPath') -or $PSBoundParameters.ContainsKey('HealthUri')
$mutexName='Local\RouterStudioManagement-'+$env:USERNAME
if($testMode){
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$suffix=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToUpperInvariant()))).Replace('-','')}finally{$hash.Dispose()}
    $mutexName+='-test-'+$suffix
}
# Production uses the control modules shipped beside this worker; fixtures retain injectable installation modules.
$moduleRoot=if($testMode){$root}else{ $candidate=Join-Path (Split-Path $PSScriptRoot -Parent) 'router'; if(Test-Path (Join-Path $candidate 'provider-switch.mjs')){$candidate}else{$PSScriptRoot} }
$mutex=[Threading.Mutex]::new($false,$mutexName);$held=$false;$activeLease=$null;$commitLease=$null
function WriteUtf8($path,$value){[IO.File]::WriteAllText($path,$value,[Text.UTF8Encoding]::new($false))}
function InvokeNode([string[]]$Arguments,[string]$FailureCode='operation_failed'){
    $node=(Get-Content -LiteralPath (Join-Path $root 'node-path.txt') -Raw -Encoding UTF8).Trim()
    $out=@(& $node @Arguments 2>&1)
    if($LASTEXITCODE -ne 0){StopStudioAction $FailureCode}
    return ($out -join [Environment]::NewLine)
}
function RunSwitch($action,$id='',$configDigest='',$backupDigest=''){
    $code=if($action -in @('official','router','repair','restore-backup')){'config_changed'}else{'operation_failed'}
    if(Test-Path -LiteralPath (Join-Path $root 'provider-state.json.pending')){$code='recovery_required'}
    InvokeNode -Arguments @((Join-Path $moduleRoot 'provider-switch.mjs'),$action,$cp,$root,$id,$configDigest,$backupDigest) -FailureCode $code
}
function GetBackupPreview($id) {
    if($id -isnot [string] -or $id -notmatch '^\d{1,20}-[a-f0-9]{6}\.toml$'){StopStudioAction 'invalid_request'}
    RunSwitch 'preview-backup' $id|ConvertFrom-Json
}
function AssertPreviewCurrent($request) {
    if(-not $request.PSObject.Properties['expectedPreviewDigest']){return} # Legacy UI keeps its existing contract.
    if($request.expectedPreviewDigest -isnot [string] -or $request.expectedPreviewDigest -notmatch '^[a-f0-9]{64}$'){StopStudioAction 'invalid_request'}
    $backup=if($request.action -eq 'restore'){GetBackupPreview $request.id|Out-Null;Join-Path $root ('backups/'+$request.id)}else{''}
    if((GetStudioPreviewDigest $root $cp $backup) -cne $request.expectedPreviewDigest){StopStudioAction 'config_changed'}
}
function GetToken{
    $s=Import-Clixml -LiteralPath (Join-Path $root 'secrets.xml')
    return [Net.NetworkCredential]::new('',$s['SAFE_8STOKEN_LOCAL_TOKEN']).Password
}
function GetHealth{
    try{
        $health=Invoke-RestMethod -MaximumRedirection 0 -Uri $HealthUri -Headers @{Authorization=('Bearer '+(GetToken))} -TimeoutSec 1
        if($health.ok -eq $true){return $health}
    }catch{}
    return $null
}
function InvokeProbeNode($InputValue,[string]$Credential='', [switch]$Plan,[switch]$Preview,[switch]$Catalog) {
    $launch=[Diagnostics.ProcessStartInfo]::new()
    $launch.FileName=(Get-Content -LiteralPath (Join-Path $root 'node-path.txt') -Raw -Encoding UTF8).Trim()
    $launch.UseShellExecute=$false;$launch.CreateNoWindow=$true
    $launch.RedirectStandardInput=$true;$launch.RedirectStandardOutput=$true;$launch.RedirectStandardError=$true
    $launch.StandardInputEncoding=[Text.UTF8Encoding]::new($false)
    $launch.StandardOutputEncoding=[Text.UTF8Encoding]::new($false,$true)
    $launch.ArgumentList.Add((Join-Path $moduleRoot 'probe-cli.mjs'));if($Catalog){$launch.ArgumentList.Add('--catalog')}elseif($Preview){$launch.ArgumentList.Add('--preview')}elseif($Plan){$launch.ArgumentList.Add('--plan')}
    # Build a dedicated environment rather than inheriting API keys or Node startup hooks.
    $launch.Environment.Clear()
    foreach($name in @('SystemRoot','WINDIR','TEMP','TMP','PATH','PATHEXT','USERPROFILE','LOCALAPPDATA')){
        $value=[Environment]::GetEnvironmentVariable($name);if($value){$launch.Environment[$name]=$value}
    }
    if($Credential){$launch.Environment['ROUTER_STUDIO_PROBE_KEY']=$Credential}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$launch
    try {
        if(-not $process.Start()){StopStudioAction 'operation_failed'}
        $launch.Environment.Remove('ROUTER_STUDIO_PROBE_KEY')|Out-Null;$Credential=$null
        # Drain errors without retaining or forwarding arbitrary child text.
        $errors=$process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        $output=$process.StandardOutput.ReadToEndAsync()
        $process.StandardInput.Write(($InputValue|ConvertTo-Json -Depth 100 -Compress));$process.StandardInput.Close()
        if(-not $process.WaitForExit(35000)){$process.Kill($true);StopStudioAction 'operation_failed'}
        $errors.GetAwaiter().GetResult()|Out-Null
        $text=$output.GetAwaiter().GetResult()
        if($text.Length -gt $(if($Catalog){2MB}else{16384})){StopStudioAction 'invalid_result'}
        try{$response=$text|ConvertFrom-Json}catch{StopStudioAction 'invalid_result'}
        if($response.schemaVersion -ne 1 -or $response.ok -isnot [bool]){StopStudioAction 'invalid_result'}
        if(-not $response.ok){
            $code=$response.error.code
            if($code -notin @('invalid_request','unsupported_capability','acknowledgement_required','config_changed')){$code='invalid_result'}
            StopStudioAction $code
        }
        if($process.ExitCode -ne 0){StopStudioAction 'invalid_result'}
        return $response.data
    }finally {
        $launch.Environment.Remove('ROUTER_STUDIO_PROBE_KEY')|Out-Null;$Credential=$null
        if($process.Id -and -not $process.HasExited){$process.Kill($true)}
        $process.Dispose()
    }
}
function GetProbe($request) {
    $digest=GetStudioSnapshotDigest $root
    $probeRequest=[ordered]@{}
    foreach($property in $request.PSObject.Properties){
        if($property.Name -in @('schemaVersion','action')){continue}
        if($property.Name -notin @('kind','modelId','credentialId','credentialLabel','outputTokenLimit','expectedSnapshotDigest','acknowledgement')){StopStudioAction 'invalid_request'}
        $probeRequest[$property.Name]=$property.Value
    }
    $preview=$request.action -eq 'preview-probe'
    $plan=InvokeProbeNode -Plan -Preview:$preview -InputValue @{config=(Get-Content -LiteralPath (Join-Path $root 'router-config.json') -Raw -Encoding UTF8|ConvertFrom-Json);catalog=(Get-Content -LiteralPath (Join-Path $root 'codex-router-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json);request=$probeRequest;snapshotDigest=$digest}
    if($preview){
        if((GetStudioSnapshotDigest $root) -cne $digest){StopStudioAction 'config_changed'}
        return @{kind=$plan.kind;modelId=$plan.modelId;resolvedModel=$plan.resolvedModel;effort=$plan.effort;outputTokenLimit=$plan.outputTokenLimit;credentialId=$plan.credentialId;credentialLabel=$plan.credentialLabel;endpointName=$plan.endpointName;snapshotDigest=$digest}
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $result=@{kind=$plan.kind;modelId=$null;credentialId=$plan.credentialId;credentialLabel=$null;endpointName=$plan.endpointName;outcome='not_verified';errorCode=$null;httpStatus=$null;elapsedMs=0;firstEventMs=$null;completedAtUtc=[DateTime]::UtcNow.ToString('o');snapshotDigest=$digest}
    switch($plan.kind) {
        'local' {
            if(GetHealth){$result.outcome='passed'}else{$result.outcome='failed';$result.errorCode='network_error'}
        }
        'official_config' {
            $status=RunSwitch 'status'|ConvertFrom-Json
            if($status.selected -ne 'official' -or $env:OPENAI_BASE_URL -or [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL','User') -or [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL','Machine')){$result.errorCode='protocol_mismatch'}
            # Configuration cannot prove account authentication, workspace or quota.
        }
        {$_ -in @('catalog','responses','stream','tool')} {
            if($plan.keyEnv -notmatch '^SAFE_8STOKEN_(PLUS|PRO|FULL|EXTRA_[A-Z][A-Z0-9_]{0,39})$'){StopStudioAction 'invalid_request'}
            if($plan.credentialId){
                if($plan.credentialId -notmatch '^[A-Za-z][A-Za-z0-9._:-]{0,79}$' -or $plan.credentialLabel -isnot [string] -or $plan.credentialLabel.Length -gt 80 -or -not $plan.credentialLabel.Trim() -or $plan.credentialLabel -match '[\x00-\x1f\x7f]'){StopStudioAction 'invalid_request'}
            }elseif($plan.credentialLabel -notmatch '^[A-Z][A-Z0-9_]{0,39}$'){StopStudioAction 'invalid_request'}
            $stored=Import-Clixml -LiteralPath (Join-Path $root 'secrets.xml')
            $selected=$stored[$plan.keyEnv]
            if($selected -isnot [Security.SecureString] -or $selected.Length -eq 0){StopStudioAction 'invalid_key'}
            try{
                $credential=[Net.NetworkCredential]::new('',$selected).Password
                $observed=InvokeProbeNode -InputValue $plan -Credential $credential
            }finally{$credential=$null;foreach($value in $stored.Values){if($value -is [Security.SecureString]){$value.Dispose()}};$stored=$null}
            if($observed.outcome -notin @('passed','failed','incomplete','cancelled','timed_out','not_verified') -or ($null -ne $observed.errorCode -and $observed.errorCode -notin @('auth_rejected','rate_limited','network_error','protocol_mismatch','response_limit','unsupported_capability','output_limit','upstream_error'))){StopStudioAction 'invalid_result'}
            if($null -ne $observed.httpStatus -and ($observed.httpStatus -isnot [long] -and $observed.httpStatus -isnot [int] -or $observed.httpStatus -lt 100 -or $observed.httpStatus -gt 599)){StopStudioAction 'invalid_result'}
            $result.credentialLabel=$plan.credentialLabel;$result.outcome=$observed.outcome;$result.errorCode=$observed.errorCode;$result.httpStatus=$observed.httpStatus
            $result.modelId=$plan.modelId
            if($plan.kind -eq 'stream' -and $null -ne $observed.firstEventMs){
                if($observed.firstEventMs -isnot [ValueType] -or -not [double]::IsFinite([double]$observed.firstEventMs) -or $observed.firstEventMs -lt 0 -or $observed.firstEventMs -gt 35000){StopStudioAction 'invalid_result'}
                $result.firstEventMs=[double]$observed.firstEventMs
            }
        }
        default {StopStudioAction 'unsupported_capability'}
    }
    $result.elapsedMs=$timer.Elapsed.TotalMilliseconds;$result.completedAtUtc=[DateTime]::UtcNow.ToString('o')
    if((GetStudioSnapshotDigest $root) -cne $digest){StopStudioAction 'config_changed'}
    return $result
}
function StopOwnedRouter{
    $file=Join-Path $root 'router.pid'
    if(Test-Path -LiteralPath $file){
        $rid=[int](Get-Content -LiteralPath $file -Raw -Encoding UTF8)
        $p=Get-CimInstance Win32_Process -Filter "ProcessId = $rid" -ErrorAction Stop
        if($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -and $p.CommandLine.Contains((Join-Path $root 'router.mjs'))){Stop-Process -Id $rid -Force -ErrorAction Stop}
    }
}
function StartRouter{
    $digest=GetStudioSnapshotDigest $root
    $healthy=[bool](GetHealth)
    if($healthy -and -not(TestStudioRestartRequired $root $digest $healthy)){return}
    try{
        $ps=(Get-Process -Id $PID).Path
        $launchArguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'run-router.ps1')+'"'
        if($testMode){$launchArguments+=' -InstallRoot "'+$root+'" -HealthUri "'+$HealthUri.AbsoluteUri+'"'}
        $launcher=Start-Process -FilePath $ps -WindowStyle Hidden -PassThru -ArgumentList $launchArguments
        try{
            for($i=0;$i -lt 30;$i++){
                $healthy=[bool](GetHealth)
                if($healthy -and -not(TestStudioRestartRequired $root (GetStudioSnapshotDigest $root) $healthy)){return}
                if($launcher.HasExited){break}
                Start-Sleep -Milliseconds 250
            }
        }finally{$launcher.Dispose()}
    }catch{StopStudioAction 'startup_failed'}
    StopStudioAction 'startup_failed'
}
function RecoverKeySave{
    $marker=Join-Path $root 'studio-key.pending.json'
    if(Test-Path -LiteralPath $marker){
        foreach($name in @('secrets.xml','router-config.json','codex-router-catalog.json')){
            if(-not(Test-Path -LiteralPath (Join-Path $root ($name+'.before-studio-key')))){StopStudioAction 'recovery_required'}
        }
        # Write before the first restored byte; a second interruption must keep the reminder.
        SetStudioRestartRequired $root 'key_save_recovered'
        try{
            foreach($name in @('secrets.xml','router-config.json','codex-router-catalog.json')){Copy-Item -LiteralPath (Join-Path $root ($name+'.before-studio-key')) -Destination (Join-Path $root $name) -Force}
            Remove-Item -LiteralPath $marker
        }catch{StopStudioAction 'recovery_required'}
    }
}
function AssertCustomSnapshotCurrent($request) {
    if((GetStudioSnapshotDigest $root) -cne $request.expectedSnapshotDigest){StopStudioAction 'config_changed'}
}
function ReadCredentialRegistry([switch]$Persist) {
    $secrets=Import-Clixml -LiteralPath (Join-Path $root 'secrets.xml')
    try{
        $prefix=if($Persist){'registry-write'}else{'registry-status'};$inputFile=Join-Path $Job ($prefix+'-input.json');$outputFile=Join-Path $Job ($prefix+'-output.json')
        WriteStudioJson $inputFile @{savedEnvironments=@($secrets.Keys)}
        InvokeNode -Arguments @((Join-Path $moduleRoot 'management.mjs'),(Join-Path $root 'router-config.json'),(Join-Path $root 'codex-router-catalog.json'),$inputFile,$outputFile,'--registry') -FailureCode 'invalid_request'|Out-Null
        return (Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8|ConvertFrom-Json)
    }finally{foreach($value in $secrets.Values){if($value -is [Security.SecureString]){$value.Dispose()}}}
}
function SaveCustomManagement($request,$secretInput) {
    AssertCustomSnapshotCurrent $request
    $rc=Join-Path $root 'router-config.json';$cat=Join-Path $root 'codex-router-catalog.json';$secretsFile=Join-Path $root 'secrets.xml'
    $fetched=$null
    if($request.action -eq 'fetch-credential-catalog'){
        $config=ReadCredentialRegistry
        $credential=@($config.credentials|Where-Object{$_.id -ceq $request.credentialId})
        if($credential.Count -ne 1){StopStudioAction 'invalid_request'}
        $credential=$credential[0]
        $stored=Import-Clixml -LiteralPath $secretsFile;$selected=$stored[$credential.keyEnv]
        if($selected -isnot [Security.SecureString] -or $selected.Length -eq 0){StopStudioAction 'invalid_key'}
        $plan=@{kind='catalog';credentialId=$credential.id;credentialLabel=$credential.label;keyEnv=$credential.keyEnv;endpointName='8stoken';snapshotDigest=$request.expectedSnapshotDigest}
        try{$plain=[Net.NetworkCredential]::new('',$selected).Password;$response=InvokeProbeNode -Catalog -InputValue $plan -Credential $plain}finally{$plain=$null}
        if($response.outcome -ne 'passed' -or -not $response.catalog){StopStudioAction 'invalid_result'}
        $fetched=$response.catalog
    }
    $requestFile=Join-Path $Job 'management-request.json';$outputFile=Join-Path $Job 'management-result.json'
    $savedSecrets=Import-Clixml -LiteralPath $secretsFile
    try{WriteStudioJson $requestFile @{request=$request;catalog=$fetched;savedEnvironments=@($savedSecrets.Keys)}}finally{foreach($value in $savedSecrets.Values){if($value -is [Security.SecureString]){$value.Dispose()}}}
    InvokeNode -Arguments @((Join-Path $moduleRoot 'management.mjs'),$rc,$cat,$requestFile,$outputFile) -FailureCode 'invalid_request'|Out-Null
    $updated=Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8|ConvertFrom-Json
    $stored=Import-Clixml -LiteralPath $secretsFile
    if($request.action -in @('save-credential','rotate-credential')){
        if(-not $secretInput -or $secretInput.key -isnot [Security.SecureString] -or $secretInput.key.Length -eq 0){StopStudioAction 'invalid_key'}
        $stored[$updated.keyEnv]=$secretInput.key
    }elseif($request.action -eq 'delete-credential'){$stored.Remove($updated.keyEnv)}
    $stored|Export-Clixml ($secretsFile+'.studio-new')
    WriteUtf8 ($rc+'.studio-new') ($updated.config|ConvertTo-Json -Depth 100)
    WriteUtf8 ($cat+'.studio-new') ($updated.catalog|ConvertTo-Json -Depth 100)
    AssertCustomSnapshotCurrent $request
    $files=@($secretsFile,$rc,$cat)
    foreach($file in $files){Copy-Item -LiteralPath $file -Destination ($file+'.before-studio-key') -Force}
    WriteUtf8 (Join-Path $root 'studio-key.pending.json') '{"version":1}'
    SetStudioRestartRequired $root 'custom_management_updated'
    # Never let an owned router continue using a deleted/rotated secret after commit.
    StopOwnedRouter
    try{foreach($file in $files){Move-Item -LiteralPath ($file+'.studio-new') -Destination $file -Force};Remove-Item -LiteralPath (Join-Path $root 'studio-key.pending.json')}
    catch{RecoverKeySave;StopStudioAction 'recovery_required'}
    $result=GetStatus;$result.message='Saved securely. Restart the local router explicitly before using the updated catalog or credentials. Provider access has not been verified.'
    return $result
}
function GetStatus{
    $digest=GetStudioSnapshotDigest $root
    $s=RunSwitch 'status'|ConvertFrom-Json
    $health=GetHealth
    $cfg=ReadCredentialRegistry
    $catalog=Get-Content -LiteralPath (Join-Path $root 'codex-router-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $keys=Import-Clixml -LiteralPath (Join-Path $root 'secrets.xml')
    $rows=@(foreach($m in $catalog.models){
        $alias=$cfg.aliases.PSObject.Properties[$m.slug]
        $route=if($cfg.modelRoutes){$cfg.modelRoutes.PSObject.Properties[$m.slug]}else{$null}
        $custom=@($cfg.customModels|Where-Object{$_.id -ceq $m.slug})|Select-Object -First 1
        $credential=if($custom){@($cfg.credentials|Where-Object{$_.id -ceq $custom.credentialId})|Select-Object -First 1}else{$null}
        $key=if($custom){$credential.keyEnv}elseif($alias){$alias.Value.keyEnv}elseif($route){$route.Value}else{$cfg.defaultKeyEnv}
        $levels=@($m.supported_reasoning_levels|ForEach-Object{if($_.effort -is [string] -and $_.effort -match '^[a-z][a-z0-9_]{0,31}$'){$_.effort}})
        [pscustomobject]@{Id=$m.slug;Name=$(if($m.display_name){$m.display_name}else{$m.slug});Credential=$(if($custom){$credential.label}else{($key -replace '^SAFE_8STOKEN_EXTRA_','' -replace '^SAFE_8STOKEN_','')});Kind=$(if($custom){'Custom model'}elseif($alias){'Preset'}else{'Raw model'});Saved=[bool]$keys.ContainsKey($key);hasExplicitRoute=[bool]($custom -or $alias -or $route);KeyStatus=$(if($keys.ContainsKey($key)){'Saved'}else{'Missing'});supportedReasoningLevels=$levels}
    })
    $credentials=@(foreach($credential in $cfg.credentials){
        $source=$credential.catalog
        $models=@(foreach($m in $source.models){@{id=$m.slug;name=$(if($m.display_name){$m.display_name}else{$m.slug});supportedReasoningLevels=@($m.supported_reasoning_levels|ForEach-Object{$_.effort})}})
        @{id=$credential.id;label=$credential.label;saved=[bool]$keys.ContainsKey($credential.keyEnv);catalogFetchedAtUtc=$source.fetchedAtUtc;catalogModels=$models}
    })
    $customModels=@(foreach($custom in $cfg.customModels){
        $credential=@($cfg.credentials|Where-Object{$_.id -ceq $custom.credentialId})|Select-Object -First 1
        @{id=$custom.id;credentialId=$custom.credentialId;originalModel=$custom.originalModel;displayLabel=$custom.displayLabel;availability=$(if(-not $credential){'credential_missing'}elseif($custom.availability -eq 'unavailable'){'unavailable'}else{'available'});saved=[bool]($credential -and $keys.ContainsKey($credential.keyEnv));supportedReasoningLevels=@($custom.metadata.supported_reasoning_levels|ForEach-Object{$_.effort})}
    })
    $nodeVersion=InvokeNode -Arguments @('--version')
    if($nodeVersion -notmatch '^v\d+\.\d+\.\d+$'){StopStudioAction 'operation_failed'}
    if((GetStudioSnapshotDigest $root) -ne $digest){StopStudioAction 'config_changed'}
    $restart=TestStudioRestartRequired $root $digest ([bool]$health)
    $configurationCurrent=$false
    try{$loaded=Get-Content -LiteralPath (Join-Path $root 'router-loaded-snapshot.json') -Raw -Encoding UTF8|ConvertFrom-Json;$configurationCurrent=([bool]$health -and -not $restart -and $loaded.snapshotDigest -eq $digest)}catch{}
    $message=if($restart){'Saved files were recovered or updated. Save your work, close Codex and restart the router. Reachability does not prove the running router loaded these files.'}else{'Status refreshed. No paid upstream request was sent.'}
    return @{credentials=$credentials;customModels=$customModels;connection=$s;healthy=[bool]$health;models=$rows;keys=@($keys.Keys|Where-Object{$_ -ne 'SAFE_8STOKEN_LOCAL_TOKEN'}|ForEach-Object{$_ -replace '^SAFE_8STOKEN_EXTRA_','' -replace '^SAFE_8STOKEN_',''});backups=@(RunSwitch 'backups'|ConvertFrom-Json);message=$message;runtimeVersions=@{node=$nodeVersion;powershell=$PSVersionTable.PSVersion.ToString()};snapshotDigest=$digest;checkedAtUtc=[DateTime]::UtcNow.ToString('o');restartRequired=$restart;routerHealth=@{reachable=[bool]$health;configurationCurrent=$configurationCurrent}}
}
try{
    try{$activeLease=[IO.File]::Open((Join-Path $Job 'active.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{StopStudioAction 'busy'}
    if($HealthUri.Scheme -ne 'http' -or $HealthUri.Host -ne '127.0.0.1' -or $HealthUri.AbsolutePath -ne '/__router/health' -or $HealthUri.UserInfo -or $HealthUri.Query -or $HealthUri.Fragment){StopStudioAction 'invalid_request'}
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){StopStudioAction 'busy'}
    try{$request=Get-Content -LiteralPath (Join-Path $Job 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{StopStudioAction 'invalid_request'}
    if($null -ne $request.schemaVersion -and $request.schemaVersion -ne 1){StopStudioAction 'unsupported_schema'}
    $request=ConvertToStudioActionRequest $request
    $customManagement=TestStudioCustomManagement $request
    $secretInput=ReadStudioSecretInput -Job $Job -Action $request.action -Request $request
    if($request.action -notin @('install','status','official','router','start','stop','repair','restore','save-key','preview-routes','preview-backup','probe','preview-probe','save-credential','rotate-credential','rename-credential','delete-credential','fetch-credential-catalog','save-custom-model','delete-custom-model')){StopStudioAction 'invalid_request'}
    $previewOnly=$request.action -in @('preview-routes','preview-backup','probe','preview-probe')
    $pending=(Test-Path -LiteralPath (Join-Path $root 'studio-key.pending.json')) -or (Test-Path -LiteralPath (Join-Path $root 'provider-state.json.pending'))
    if($previewOnly -and $pending){StopStudioAction 'recovery_required'}
    if((-not $previewOnly -and $request.action -ne 'status') -or $pending){
        try{$commitLease=[IO.File]::Open((Join-Path $Job 'commit.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{StopStudioAction 'busy'}
    }
    if($request.action -eq 'install'){
        if($testMode){StopStudioAction 'invalid_request'}
        if($secretInput){$secretInput.initialKeys|Export-Clixml (Join-Path $Job 'initial-keys.xml')}
        if(-not(Test-Path -LiteralPath (Join-Path $Job 'initial-keys.xml'))){StopStudioAction 'invalid_key'}
        $output=@(& (Join-Path $PSScriptRoot 'Setup.ps1') -Action Install -CredentialFile (Join-Path $Job 'initial-keys.xml') 2>&1)
        if($LASTEXITCODE -ne 0){StopStudioAction 'installation_failed'}
        $result=@{message='Installed. Sign out of Windows and back in once so Codex can load the local token. Then open Router Studio.'}
    }else{
        if(-not $previewOnly){RecoverKeySave}
        foreach($f in @('router-config.json','secrets.xml','codex-router-catalog.json','node-path.txt')){if(-not(Test-Path -LiteralPath (Join-Path $root $f))){StopStudioAction 'installation_incomplete'}}
        if(Test-Path -LiteralPath (Join-Path $root 'provider-state.json.pending')){
            SetStudioRestartRequired $root 'provider_state_recovered'
            RunSwitch 'init'|Out-Null
        }
        switch($request.action){
            {$customManagement}{$result=SaveCustomManagement $request $secretInput}
            {$_ -in @('probe','preview-probe')}{$result=GetProbe $request}
            'status'{$result=GetStatus}
            'stop'{if($request.ack -isnot [bool] -or -not $request.ack){StopStudioAction 'acknowledgement_required'};StopOwnedRouter;$result=GetStatus;$result.message='Owned router stop requested. Existing Codex requests may have been interrupted.'}
            'preview-routes'{
                $previewDigest=GetStudioPreviewDigest $root $cp
                $routeRequest=Join-Path $Job 'route-request.json';$outFile=Join-Path $Job 'preview.json'
                WriteStudioJson $routeRequest @{label=$request.label;ids=@($request.ids)}
                InvokeNode -Arguments @((Join-Path $moduleRoot 'model-manager.mjs'),(Join-Path $root 'router-config.json'),(Join-Path $root 'codex-router-catalog.json'),$routeRequest,$outFile,'--preview') -FailureCode 'invalid_request'|Out-Null
                if((GetStudioPreviewDigest $root $cp) -cne $previewDigest){StopStudioAction 'config_changed'}
                $result=Get-Content -LiteralPath $outFile -Raw -Encoding UTF8|ConvertFrom-Json
                $result|Add-Member -NotePropertyName previewDigest -NotePropertyValue $previewDigest
                $result|Add-Member -NotePropertyName snapshotDigest -NotePropertyValue (GetStudioSnapshotDigest $root)
            }
            'preview-backup'{
                $preview=GetBackupPreview $request.id
                $backup=Join-Path $root ('backups/'+$request.id);$previewDigest=GetStudioPreviewDigest $root $cp $backup
                $result=GetBackupPreview $request.id
                if($preview.configDigest -cne $result.configDigest -or $preview.backupDigest -cne $result.backupDigest -or (GetStudioPreviewDigest $root $cp $backup) -cne $previewDigest){StopStudioAction 'config_changed'}
                $result|Add-Member -NotePropertyName previewDigest -NotePropertyValue $previewDigest
                $result|Add-Member -NotePropertyName snapshotDigest -NotePropertyValue (GetStudioSnapshotDigest $root)
            }
            'official'{
                if($env:OPENAI_BASE_URL -or [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL','User') -or [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL','Machine')){StopStudioAction 'endpoint_override'}
                RunSwitch 'official'|Out-Null;$result=GetStatus;$result.message='Subscription selected. Restart Codex and use official ChatGPT sign-in. Select your Business workspace and start a new session.'
            }
            'router'{
                if(Test-Path -LiteralPath (Join-Path $root 'studio-restart-required.json')){
                    if($request.ack -isnot [bool] -or -not $request.ack){StopStudioAction 'acknowledgement_required'}
                    StopOwnedRouter
                }
                StartRouter;RunSwitch 'router'|Out-Null;$result=GetStatus;$result.message='8stoken selected. Restart Codex and start a new session. Select a preset or supported raw model.'}
            'start'{
                if((Test-Path -LiteralPath (Join-Path $root 'studio-restart-required.json')) -and ($request.ack -isnot [bool] -or -not $request.ack)){StopStudioAction 'acknowledgement_required'}
                if(Test-Path -LiteralPath (Join-Path $root 'studio-restart-required.json')){StopOwnedRouter}
                StartRouter;$result=GetStatus;$result.message='Local router is reachable. Upstream model access has not been tested.'
            }
            'repair'{RunSwitch 'repair'|Out-Null;$result=GetStatus;$result.message='Verified local connection adopted. Codex settings were kept.'}
            'restore'{
                if($request.ack -isnot [bool] -or -not $request.ack){StopStudioAction 'acknowledgement_required'}
                AssertPreviewCurrent $request
                $preview=GetBackupPreview $request.id
                RunSwitch 'restore-backup' $request.id $preview.configDigest $preview.backupDigest|Out-Null;$result=GetStatus;$result.message='Backup restored. Reopen Codex and start a new session.'
            }
            'save-key'{
                if($request.ack -isnot [bool] -or -not $request.ack){StopStudioAction 'acknowledgement_required'}
                AssertPreviewCurrent $request
                $key=if($secretInput){$secretInput.key}else{Import-Clixml -LiteralPath (Join-Path $Job 'key.xml')}
                if($key -isnot [Security.SecureString] -or $key.Length -eq 0){StopStudioAction 'invalid_key'}
                $rc=Join-Path $root 'router-config.json';$cat=Join-Path $root 'codex-router-catalog.json';$outFile=Join-Path $Job 'routes.json'
                $routeRequest=Join-Path $Job 'route-request.json'
                WriteStudioJson $routeRequest @{label=$request.label;ids=$request.ids}
                InvokeNode -Arguments @((Join-Path $moduleRoot 'model-manager.mjs'),$rc,$cat,$routeRequest,$outFile) -FailureCode 'invalid_request'|Out-Null
                $updated=Get-Content -LiteralPath $outFile -Raw -Encoding UTF8|ConvertFrom-Json
                $secretsFile=Join-Path $root 'secrets.xml';$stored=Import-Clixml -LiteralPath $secretsFile;$stored[$updated.envName]=$key
                $stored|Export-Clixml ($secretsFile+'.studio-new')
                WriteUtf8 ($rc+'.studio-new') ($updated.config|ConvertTo-Json -Depth 100)
                WriteUtf8 ($cat+'.studio-new') ($updated.catalog|ConvertTo-Json -Depth 100)
                AssertPreviewCurrent $request
                $files=@($secretsFile,$rc,$cat)
                foreach($file in $files){Copy-Item -LiteralPath $file -Destination ($file+'.before-studio-key') -Force}
                WriteUtf8 (Join-Path $root 'studio-key.pending.json') '{"version":1}'
                SetStudioRestartRequired $root 'key_save_updated'
                StopOwnedRouter
                try{foreach($file in $files){Move-Item -LiteralPath ($file+'.studio-new') -Destination $file -Force};Remove-Item -LiteralPath (Join-Path $root 'studio-key.pending.json')}
                catch{RecoverKeySave;StopStudioAction 'recovery_required'}
                StartRouter
                $result=GetStatus;$result.message='Key saved encrypted for this Windows user. Routes applied and router restarted. Reopen Codex. Group permissions and model compatibility still depend on 8stoken.'
            }
        }
    }
    WriteStudioJson (Join-Path $Job 'result.json') @{schemaVersion=1;ok=$true;data=$result}
}catch{
    $code=$_.Exception.Data['StudioCode']
    if(-not $code){$code='operation_failed'}
    $safeError=GetStudioError $code
    WriteStudioJson (Join-Path $Job 'result.json') @{schemaVersion=1;ok=$false;error=$safeError}
}finally{
    foreach($name in @('key.xml','initial-keys.xml','secret.dpapi')){Remove-Item -LiteralPath (Join-Path $Job $name) -ErrorAction SilentlyContinue}
    if($secretInput){if($secretInput.key){$secretInput.key.Dispose()};if($secretInput.initialKeys){foreach($secure in $secretInput.initialKeys.Values){$secure.Dispose()}}}
    if($commitLease){$commitLease.Dispose()};if($activeLease){$activeLease.Dispose()}
    if($held){$mutex.ReleaseMutex()};$mutex.Dispose()
}
