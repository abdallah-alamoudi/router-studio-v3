param(
    [string]$InstallRoot=$PSScriptRoot,
    [uri]$HealthUri='http://127.0.0.1:18761/__router/health'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($InstallRoot)
. (Join-Path $PSScriptRoot 'Studio-Protocol.ps1')
$mutex=New-Object System.Threading.Mutex($false,('Local\Safe8stokenRouter-'+$env:USERNAME))
$held=$false;$secrets=$null;$value=$null;$child=$null;$childStarted=$false;$ready=$false
try{
    if($HealthUri.Scheme -ne 'http' -or $HealthUri.Host -ne '127.0.0.1' -or $HealthUri.AbsolutePath -ne '/__router/health' -or $HealthUri.Query -or $HealthUri.Fragment -or $HealthUri.UserInfo){StopStudioAction 'invalid_request'}
    # Explicit fixture roots never compete with the real router's lifetime mutex.
    if($PSBoundParameters.ContainsKey('InstallRoot')){
        $mutex.Dispose()
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$suffix=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToUpperInvariant()))).Replace('-','')}finally{$hash.Dispose()}
        $mutex=[Threading.Mutex]::new($false,('Local\Safe8stokenRouter-'+$env:USERNAME+'-test-'+$suffix))
    }
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){exit 0}
    $digest=GetStudioSnapshotDigest $root
    $marker=Join-Path $root 'studio-restart-required.json'
    $markerId=if(Test-Path -LiteralPath $marker){(Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json).id}else{$null}
    $secrets=Import-Clixml -LiteralPath (Join-Path $root 'secrets.xml')
    $token=[Net.NetworkCredential]::new('',$secrets['SAFE_8STOKEN_LOCAL_TOKEN']).Password
    foreach($name in $secrets.Keys){
        $value=(New-Object System.Net.NetworkCredential('',$secrets[$name])).Password
        [Environment]::SetEnvironmentVariable($name,$value,'Process')
    }
    $node=(Get-Content -LiteralPath (Join-Path $root 'node-path.txt') -Raw -Encoding UTF8).Trim()
    $routerPath=if(Test-Path (Join-Path $root 'router.mjs')){Join-Path $root 'router.mjs'}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'router/router.mjs'};$configPath=Join-Path $root 'router-config.json'
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$node;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    # Windows file names cannot contain quotes; preserve legacy startup links that
    # invoke Windows PowerShell 5.1, whose ProcessStartInfo has no ArgumentList.
    $start.Arguments='"'+$routerPath+'" "'+$configPath+'"'
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $child=[Diagnostics.Process]::new();$child.StartInfo=$start
    [void]$child.Start();$childStarted=$true
    # Drain into a sink; raw child errors can contain configuration/credential bytes.
    $outDrain=$child.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
    $errDrain=$child.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
    $child.Id|Set-Content (Join-Path $root 'router.pid')
    foreach($name in $secrets.Keys){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    $value=$null
    $healthy=$false
    for($attempt=0;$attempt -lt 30;$attempt++){
        if($child.HasExited){break}
        try{$h=Invoke-RestMethod -MaximumRedirection 0 -Uri $HealthUri -Headers @{Authorization=('Bearer '+$token)} -TimeoutSec 1;if($h.ok -eq $true){
            $listener=Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $HealthUri.Port -State Listen -ErrorAction Stop
            if(@($listener|Where-Object{$_.OwningProcess -eq $child.Id}).Count){$healthy=$true;break}
        }}catch{}
        Start-Sleep -Milliseconds 250
    }
    $token=$null
    if(-not $healthy -or $child.HasExited -or (GetStudioSnapshotDigest $root) -ne $digest){StopStudioAction 'startup_failed'}
    # This acknowledgement names the marker seen before loading credentials. A newer
    # recovery marker or changed snapshot cannot be cleared by an older launcher.
    WriteStudioJson (Join-Path $root 'router-loaded-snapshot.json') @{schemaVersion=1;markerId=$markerId;snapshotDigest=$digest;startedAtUtc=[DateTime]::UtcNow.ToString('o')}
    $ready=$true
    'Local router started. Upstream access has not been tested.'|Set-Content (Join-Path $root 'router.log')
    $child.WaitForExit()
    if($child.ExitCode -ne 0){StopStudioAction 'startup_failed'}
}catch{
    # Never write exception text or imported credential contents.
    try{WriteStudioJson (Join-Path $root 'launcher-error.json') (GetStudioError 'startup_failed')}catch{}
    'Router launcher failed. Check Node installation and rerun setup.'|Set-Content (Join-Path $root 'launcher-error.log')
    exit 1
}finally{
    if($secrets){foreach($name in $secrets.Keys){[Environment]::SetEnvironmentVariable($name,$null,'Process')}}
    $value=$null;$token=$null
    if($held){$mutex.ReleaseMutex()};$mutex.Dispose()
    if($child){
        if($childStarted -and -not $ready -and -not $child.HasExited){$child.Kill();[void]$child.WaitForExit(2000)}
        $child.Dispose()
    }
}
