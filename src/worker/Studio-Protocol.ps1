# Shared, nonsecret management protocol policy. No installation or network side effects.
function GetStudioError([string]$Code) {
    $messages=@{
        invalid_request='Choose a supported management action and valid input.'
        unsupported_capability='This check is not implemented yet. Choose a supported check.'
        invalid_result='The provider check returned an invalid result. No response details were retained.'
        unsupported_schema='This request version is not supported. Update Router Studio.'
        acknowledgement_required='Save your work and close Codex, then confirm the restart acknowledgement.'
        invalid_key='Enter a non-empty API key.'
        installation_incomplete='Installation is incomplete. Use setup or your installation backup.'
        installation_failed='Setup could not finish. Review prerequisites and the installation backup before retrying.'
        endpoint_override='OPENAI_BASE_URL may redirect official requests. Remove the override before selecting subscription access.'
        config_changed='Connection settings changed. Refresh status and review Diagnostics before applying changes. Current settings were kept.'
        busy='Another management action is running. Wait for it to finish and try again.'
        recovery_required='Recovery needs attention. Current files were kept unless a transaction had already committed. Inspect the encrypted backups before continuing.'
        startup_failed='The router did not start with the saved configuration. Saved keys and routes were kept; a restart is still required.'
        operation_failed='The operation failed. Refresh status and check the local installation. Credentials are not included in diagnostics.'
    }
    if(-not $messages.ContainsKey($Code)){$Code='operation_failed'}
    return @{code=$Code;message=$messages[$Code]}
}
function StopStudioAction([string]$Code) {
    $safe=GetStudioError $Code
    $exception=[InvalidOperationException]::new($safe.message)
    $exception.Data['StudioCode']=$safe.code
    throw $exception
}
function GetStudioSnapshotDigest([string]$InstallRoot) {
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try{
        foreach($name in @('router-config.json','codex-router-catalog.json','secrets.xml')){
            $bytes=[IO.File]::ReadAllBytes((Join-Path $InstallRoot $name))
            # Unsigned 64-bit big-endian byte length, then the exact file bytes.
            $length=[BitConverter]::GetBytes([uint64]$bytes.LongLength)
            if([BitConverter]::IsLittleEndian){[Array]::Reverse($length)}
            $hash.AppendData($length);$hash.AppendData($bytes)
        }
        return [BitConverter]::ToString($hash.GetHashAndReset()).Replace('-','').ToLowerInvariant()
    }finally{$hash.Dispose()}
}
function WriteStudioJson([string]$Path,$Value) {
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function GetStudioPreviewDigest([string]$InstallRoot,[string]$ConfigPath,[string]$BackupPath='') {
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $paths=@('router-config.json','codex-router-catalog.json','secrets.xml','provider-state.json')|ForEach-Object{Join-Path $InstallRoot $_}
        $paths+=@($ConfigPath);if($BackupPath){$paths+=@($BackupPath)}
        foreach($path in $paths){
            $bytes=if(Test-Path -LiteralPath $path){[IO.File]::ReadAllBytes($path)}else{[byte[]]@()}
            $length=[BitConverter]::GetBytes([uint64]$bytes.LongLength);if([BitConverter]::IsLittleEndian){[Array]::Reverse($length)}
            $hash.AppendData($length);if($bytes.Length){$hash.AppendData([byte[]]$bytes)}
        }
        return [BitConverter]::ToString($hash.GetHashAndReset()).Replace('-','').ToLowerInvariant()
    }finally{$hash.Dispose()}
}
function SetStudioRestartRequired([string]$InstallRoot,[string]$Reason) {
    WriteStudioJson (Join-Path $InstallRoot 'studio-restart-required.json') @{version=1;id=[guid]::NewGuid().ToString('N');reason=$Reason}
}
function TestStudioRestartRequired([string]$InstallRoot,[string]$Digest,[bool]$Healthy) {
    $marker=Join-Path $InstallRoot 'studio-restart-required.json'
    if(-not(Test-Path -LiteralPath $marker)){return $false}
    # Reachability alone cannot prove that the running router loaded restored keys.
    try{
        $pending=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
        $loaded=Get-Content -LiteralPath (Join-Path $InstallRoot 'router-loaded-snapshot.json') -Raw|ConvertFrom-Json
        if($Healthy -and $pending.version -eq 1 -and $pending.id -match '^[a-f0-9]{32}$' -and $loaded.markerId -eq $pending.id -and $loaded.snapshotDigest -eq $Digest){
            Remove-Item -LiteralPath $marker
            return $false
        }
    }catch{}
    return $true
}

function ConvertToStudioActionRequest($Request) {
    if(-not $Request.PSObject.Properties['payload']){return $Request}
    if($Request.payload -isnot [pscustomobject]){StopStudioAction 'invalid_request'}
    $normalized=[ordered]@{schemaVersion=$Request.schemaVersion;action=$Request.action}
    $allowed=switch($Request.action){
        {$_ -in @('save-credential','rename-credential')}{@('credentialId','label','ack','expectedSnapshotDigest')}
        {$_ -in @('rotate-credential','delete-credential')}{@('credentialId','ack','expectedSnapshotDigest')}
        'fetch-credential-catalog'{@('credentialId','acknowledgement','expectedSnapshotDigest')}
        'save-custom-model'{@('customModelId','credentialId','originalModel','displayLabel','ack','expectedSnapshotDigest')}
        'delete-custom-model'{@('customModelId','ack','expectedSnapshotDigest')}
        'preview-routes'{@('label','ids')}
        'save-key'{@('label','ids','ack','expectedPreviewDigest')}
        'preview-backup'{@('id')}
        'restore'{@('id','ack','expectedPreviewDigest')}
        {$_ -in @('probe','preview-probe')}{@('kind','modelId','credentialLabel','outputTokenLimit','expectedSnapshotDigest','acknowledgement')}
        {$_ -in @('router','start','stop')}{@('ack')}
        default{@()}
    }
    foreach($field in $Request.payload.PSObject.Properties){if($field.Name -notin $allowed){StopStudioAction 'invalid_request'}}
    foreach($name in $allowed){
        if($Request.PSObject.Properties[$name]){StopStudioAction 'invalid_request'}
        $field=$Request.payload.PSObject.Properties[$name]
        if($field){$normalized[$name]=$field.Value}
    }
    if($normalized.expectedPreviewDigest -and $normalized.expectedPreviewDigest -notmatch '^[a-f0-9]{64}$'){StopStudioAction 'invalid_request'}
    return [pscustomobject]$normalized
}

function ReadStudioSecretInput([string]$Job,[string]$Action,$Request) {
    $path=Join-Path $Job 'secret.dpapi'
    if(-not(Test-Path -LiteralPath $path)){return $null}
    $plain=$null;$value=$null;$text=$null
    try {
        if($Action -notin @('save-key','install','save-credential','rotate-credential')){StopStudioAction 'invalid_request'}
        if((Test-Path -LiteralPath (Join-Path $Job 'key.xml')) -or (Test-Path -LiteralPath (Join-Path $Job 'initial-keys.xml'))){StopStudioAction 'invalid_request'}
        if((Get-Item -LiteralPath $path).Length -gt 131072){StopStudioAction 'invalid_key'}
        try{
            $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            if($plain.Length -gt 65536){StopStudioAction 'invalid_key'}
            $text=[Text.UTF8Encoding]::new($false,$true).GetString($plain)
            $value=$text|ConvertFrom-Json
        }catch{if($_.Exception.Data['StudioCode']){throw};StopStudioAction 'invalid_key'}
        if($value -isnot [pscustomobject]){StopStudioAction 'invalid_request'}
        if($Action -in @('save-credential','rotate-credential')){
            if(@($value.PSObject.Properties).Count -ne 2 -or $value.credentialId -isnot [string] -or $value.credentialId -cne $Request.credentialId -or $value.key -isnot [string]){StopStudioAction 'invalid_request'}
            if([string]::IsNullOrWhiteSpace($value.key) -or $value.key.Length -gt 8192){StopStudioAction 'invalid_key'}
            $secure=ConvertTo-SecureString $value.key -AsPlainText -Force;$secure.MakeReadOnly()
            return @{key=$secure}
        }
        if($Action -eq 'save-key'){
            if(@($value.PSObject.Properties).Count -ne 2 -or $value.label -isnot [string] -or $value.key -isnot [string]){StopStudioAction 'invalid_request'}
            if($value.label -cne $Request.label){StopStudioAction 'invalid_request'}
            if($value.key.Length -eq 0 -or $value.key.Length -gt 8192 -or [string]::IsNullOrWhiteSpace($value.key)){StopStudioAction 'invalid_key'}
            $secure=ConvertTo-SecureString $value.key -AsPlainText -Force
            $secure.MakeReadOnly()
            return @{key=$secure}
        }
        if(@($value.PSObject.Properties).Count -ne 3){StopStudioAction 'invalid_request'}
        $keys=@{}
        foreach($name in @('PLUS','PRO','FULL')){
            $field=$value.PSObject.Properties[$name]
            if(-not $field -or $field.Value -isnot [string] -or $field.Value.Length -gt 8192){StopStudioAction 'invalid_request'}
            if($name -eq 'PLUS' -and [string]::IsNullOrWhiteSpace($field.Value)){StopStudioAction 'invalid_key'}
            if($field.Value.Length){$secure=ConvertTo-SecureString $field.Value -AsPlainText -Force}else{$secure=[Security.SecureString]::new()}
            $secure.MakeReadOnly();$keys[$name]=$secure
        }
        return @{initialKeys=$keys}
    }finally{
        if($plain){[Array]::Clear($plain,0,$plain.Length)}
        $value=$null;$text=$null
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function TestStudioCustomManagement($Request) {
    if($Request.action -notin @('save-credential','rotate-credential','rename-credential','delete-credential','fetch-credential-catalog','save-custom-model','delete-custom-model')){return $false}
    $allowed=@('schemaVersion','action','expectedSnapshotDigest')
    if($Request.action -eq 'delete-custom-model'){$allowed+=@('customModelId','ack')}
    elseif($Request.action -eq 'save-custom-model'){$allowed+=@('credentialId','customModelId','originalModel','displayLabel','ack')}
    elseif($Request.action -eq 'fetch-credential-catalog'){$allowed+=@('credentialId','acknowledgement')}
    elseif($Request.action -in @('save-credential','rename-credential')){$allowed+=@('credentialId','label','ack')}
    else{$allowed+=@('credentialId','ack')}
    foreach($p in $Request.PSObject.Properties){if($p.Name -cnotin $allowed){StopStudioAction 'invalid_request'}}
    foreach($name in @('credentialId','customModelId')){
        if($name -in $allowed -and ($Request.$name -isnot [string] -or $Request.$name -cnotmatch '\A[A-Za-z][A-Za-z0-9._:-]{0,79}\z')){StopStudioAction 'invalid_request'}
    }
    foreach($name in @('label','displayLabel')){
        if($name -in $allowed -and ($Request.$name -isnot [string] -or $Request.$name.Length -eq 0 -or $Request.$name.Length -gt 80 -or $Request.$name -cne $Request.$name.Trim() -or $Request.$name -match '[\x00-\x1f\x7f]')){StopStudioAction 'invalid_request'}
    }
    if($Request.action -eq 'save-custom-model' -and ($Request.originalModel -isnot [string] -or $Request.originalModel -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_./:-]{0,159}\z')){StopStudioAction 'invalid_request'}
    if($Request.expectedSnapshotDigest -isnot [string] -or $Request.expectedSnapshotDigest -cnotmatch '\A[a-f0-9]{64}\z'){StopStudioAction 'invalid_request'}
    $name=if($Request.action -eq 'fetch-credential-catalog'){'acknowledgement'}else{'ack'}
    if($Request.PSObject.Properties[$name] -and $Request.$name -isnot [bool]){StopStudioAction 'invalid_request'}
    if($Request.$name -ne $true){StopStudioAction 'acknowledgement_required'}
    return $true
}