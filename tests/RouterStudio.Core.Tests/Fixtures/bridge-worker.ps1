param([string]$Job,[string]$InstallRoot,[string]$ConfigPath,[uri]$HealthUri)
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$mode=(Get-Content (Join-Path $base 'mode.txt') -Raw).Trim()
$request=Get-Content (Join-Path $Job 'request.json') -Raw|ConvertFrom-Json
[IO.File]::WriteAllText((Join-Path $base 'args.txt'),[Environment]::CommandLine)
Copy-Item (Join-Path $Job 'request.json') (Join-Path $base 'captured-request.json')
[IO.File]::WriteAllText((Join-Path $base 'worker.pid'),"$PID")
[IO.File]::WriteAllText((Join-Path $base 'worker.start.txt'),((Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks).ToString())
[IO.File]::WriteAllText((Join-Path $base 'job.txt'),$Job)
$good=@{schemaVersion=1;ok=$true;data=@{marker='final';snapshotDigest=('a'*64);checkedAtUtc=[DateTime]::UtcNow.ToString('o');models=@();keys=@();backups=@();connection=@{selected='official';actual='official';consistent=$true};healthy=$false;restartRequired=$false;routerHealth=@{reachable=$false;configurationCurrent=$false};runtimeVersions=@{node='v24.21.0';powershell='7.6.6'};message='Status refreshed.'}}
if($mode -eq 'secret'){
 $cipher=[IO.File]::ReadAllBytes((Join-Path $Job 'secret.dpapi'))
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 try { $value=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json; if($value.key -ne 'fake-BRIDGE-canary-key'){throw 'Unexpected fixture secret'} }
 finally {[Array]::Clear($plain,0,$plain.Length)}
 [IO.File]::WriteAllText((Join-Path $base 'secret-checked.txt'),'ok')
}
switch($mode){
 'early' {
  @{schemaVersion=1;ok=$true;data=@{marker='early'}}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $Job 'result.json')
  [IO.File]::WriteAllText((Join-Path $base 'ready.txt'),'ready')
  for($i=0;$i -lt 200 -and -not(Test-Path (Join-Path $base 'release.txt'));$i++){Start-Sleep -Milliseconds 50}
 }
 'corrupt' {[IO.File]::WriteAllText((Join-Path $Job 'result.json'),'{bad');exit 0}
 'wrong-schema' { $good.schemaVersion=99 }
 'bad-error' {$good=@{schemaVersion=1;ok=$false;error=@{code='startup_failed';message='fake-BRIDGE-canary-key'}}}
 'bad-shape' {$good=@{schemaVersion=1;ok='true';data=@{}}}
 'exit-error' {[IO.File]::WriteAllText((Join-Path $Job 'result.json'),($good|ConvertTo-Json -Depth 20));exit 9}
 'tree' {
  $child=Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 20"'
  $child.Id|Set-Content (Join-Path $base 'child.pid')
  [IO.File]::WriteAllText((Join-Path $base 'child.start.txt'),$child.StartTime.ToUniversalTime().Ticks.ToString())
  [IO.File]::WriteAllText((Join-Path $base 'ready.txt'),'ready')
  Start-Sleep -Seconds 20
 }
 'mutation' {
  [IO.File]::WriteAllText((Join-Path $base 'ready.txt'),'ready')
  for($i=0;$i -lt 200 -and -not(Test-Path (Join-Path $base 'release.txt'));$i++){Start-Sleep -Milliseconds 50}
  [IO.File]::WriteAllText((Join-Path $base 'committed.txt'),'committed')
 }
 'read-commit' {
  $commit=[IO.File]::Open((Join-Path $Job 'commit.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
   [IO.File]::WriteAllText((Join-Path $base 'ready.txt'),'ready')
   for($i=0;$i -lt 200 -and -not(Test-Path (Join-Path $base 'release.txt'));$i++){Start-Sleep -Milliseconds 50}
   [IO.File]::WriteAllText((Join-Path $base 'committed.txt'),'recovered')
  }finally{$commit.Dispose()}
 }
 'null-digest' {$good.data.snapshotDigest=$null}
 'missing' {exit 0}
 'oversized' {[IO.File]::WriteAllText((Join-Path $Job 'result.json'),('x'*(4MB+1)));exit 0}
}
$good|ConvertTo-Json -Depth 20|Set-Content (Join-Path $Job 'result.json')
