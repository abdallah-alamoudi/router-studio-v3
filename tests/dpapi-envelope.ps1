param(
 [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent),
 [string]$CipherFile,
 [ValidateSet('All','SaveKey','Install','Corrupt','MismatchedLabel','RecoveryLease')][string]$Case='All',
 [switch]$VerifyWrongUser,
 [string]$CreatorSid
)
$ErrorActionPreference='Stop'
if($VerifyWrongUser){
 if(-not $CipherFile -or -not $CreatorSid){throw 'Supply the ciphertext path and creator SID.'}
 $currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($currentSid -eq $CreatorSid){throw 'Wrong-user verification requires a different Windows identity.'}
 try{
  $bytes=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($CipherFile),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  [Array]::Clear($bytes,0,$bytes.Length)
 }catch [Security.Cryptography.CryptographicException] {Write-Output 'DPAPI: PASS - different-user decryption denied.';exit 0}
 throw 'DPAPI: FAIL - different-user decryption succeeded.'
}
$project=[IO.Path]::GetFullPath($ProjectRoot)
$base=Join-Path ([IO.Path]::GetTempPath()) ('router DPAPI Ω '+[guid]::NewGuid().ToString('N'))
$root=Join-Path $base 'installation';$job=Join-Path $base 'job';$cp=Join-Path $base 'config.toml'
$checks=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "DPAPI: FAIL - $Name"};$script:checks++;Write-Output "PASS: $Name"}
function Envelope([string]$Json){
 $plain=[Text.Encoding]::UTF8.GetBytes($Json)
 try{$cipher=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);[IO.File]::WriteAllBytes((Join-Path $job 'secret.dpapi'),$cipher)}
 finally{[Array]::Clear($plain,0,$plain.Length)}
}
try{
 New-Item $root,$job -ItemType Directory -Force|Out-Null
 . (Join-Path $project 'src/worker/Studio-Protocol.ps1')
 foreach($name in @('provider-switch.mjs','model-manager.mjs')){Copy-Item (Join-Path $project ('src/router/'+$name)) $root}
 (Get-Command node).Source|Set-Content (Join-Path $root 'node-path.txt')
 'model = "deepseek-v4.1-flash"'|Set-Content $cp
 @{defaultKeyEnv='SAFE_8STOKEN_PLUS';aliases=@{}}|ConvertTo-Json|Set-Content (Join-Path $root 'router-config.json')
 @{models=@(@{slug='deepseek-v4.1-flash'})}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'codex-router-catalog.json')
 @{SAFE_8STOKEN_LOCAL_TOKEN=(ConvertTo-SecureString 'fake-local-DPAPI-token' -AsPlainText -Force)}|Export-Clixml (Join-Path $root 'secrets.xml')
 'exit 0'|Set-Content (Join-Path $root 'run-router.ps1')
 if($Case -in @('All','SaveKey')){
  if($CipherFile){Copy-Item -LiteralPath $CipherFile (Join-Path $job 'secret.dpapi')}else{Envelope '{"label":"CHINESE","key":"fake-BRIDGE-canary-key"}'}
  @{schemaVersion=1;action='save-key';payload=@{label='CHINESE';ids=@('deepseek-v4.1-flash');ack=$true}}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $job 'request.json')
  # Pick an unused loopback port; no listener is started, and startup deliberately fails after commit.
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
  & (Join-Path $project 'src/worker/Studio-Worker.ps1') -Job $job -InstallRoot $root -ConfigPath $cp -HealthUri "http://127.0.0.1:$port/__router/health"
  $result=Get-Content (Join-Path $job 'result.json') -Raw|ConvertFrom-Json
  Check ($result.error.code -eq 'startup_failed') 'encrypted input reaches controlled post-commit startup failure'
  $stored=Import-Clixml (Join-Path $root 'secrets.xml')
  Check ($stored['SAFE_8STOKEN_EXTRA_CHINESE'] -is [Security.SecureString]) 'worker stores decrypted input as SecureString'
  Check ([Net.NetworkCredential]::new('',$stored['SAFE_8STOKEN_EXTRA_CHINESE']).Password -eq 'fake-BRIDGE-canary-key') 'C# compatible current-user envelope round trip'
  Check (-not(Test-Path (Join-Path $job 'secret.dpapi'))) 'worker deletes encrypted input after action'
  foreach($file in Get-ChildItem $job -File){Check (-not([IO.File]::ReadAllText($file.FullName).Contains('fake-BRIDGE-canary-key'))) 'job outputs omit canary'}
 }
 if($Case -in @('All','Install')){
  Envelope '{"PLUS":"fake-plus-DPAPI-key","PRO":"","FULL":""}'
  $decoded=ReadStudioSecretInput -Job $job -Action install -Request ([pscustomobject]@{action='install'})
  Check ($decoded.initialKeys.PLUS -is [Security.SecureString]) 'installation receives PLUS SecureString'
  Check ($decoded.initialKeys.PRO.Length -eq 0 -and $decoded.initialKeys.FULL.Length -eq 0) 'installation preserves optional empty PRO/FULL fields'
  Check (-not(Test-Path (Join-Path $job 'secret.dpapi'))) 'installation input deleted after decryption'
 }
 if($Case -in @('All','Corrupt')){
  [IO.File]::WriteAllBytes((Join-Path $job 'secret.dpapi'),[byte[]](1,2,3))
  $code=$null;try{ReadStudioSecretInput -Job $job -Action save-key -Request ([pscustomobject]@{label='CHINESE'})|Out-Null}catch{$code=$_.Exception.Data['StudioCode']}
  Check ($code -eq 'invalid_key') 'corrupt ciphertext reports controlled invalid_key'
  Check (-not(Test-Path (Join-Path $job 'secret.dpapi'))) 'corrupt ciphertext is deleted'
 }
 if($Case -in @('All','MismatchedLabel')){
  Envelope '{"label":"OTHER","key":"fake-BRIDGE-canary-key"}'
  $code=$null;try{ReadStudioSecretInput -Job $job -Action save-key -Request ([pscustomobject]@{label='CHINESE'})|Out-Null}catch{$code=$_.Exception.Data['StudioCode']}
  Check ($code -eq 'invalid_request') 'mismatched secret label rejected'
 }
 if($Case -in @('All','RecoveryLease')){
  foreach($name in @('secrets.xml','router-config.json','codex-router-catalog.json')){Copy-Item (Join-Path $root $name) (Join-Path $root ($name+'.before-studio-key'))}
  '{"version":1}'|Set-Content (Join-Path $root 'studio-key.pending.json')
  '{"sentinel":true}'|Set-Content (Join-Path $root 'router-config.json')
  @{schemaVersion=1;action='status';payload=@{}}|ConvertTo-Json|Set-Content (Join-Path $job 'request.json')
  $lock=[IO.File]::Open((Join-Path $job 'commit.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
   & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'src/worker/Studio-Worker.ps1') -Job $job -InstallRoot $root -ConfigPath $cp -HealthUri 'http://127.0.0.1:1/__router/health'
  }finally{$lock.Dispose()}
  $result=Get-Content (Join-Path $job 'result.json') -Raw|ConvertFrom-Json
  Check ($result.error.code -eq 'busy') 'cancellation commit lock prevents read-triggered recovery'
  Check (Test-Path (Join-Path $root 'studio-key.pending.json')) 'blocked recovery preserves pending transaction'
  Check ((Get-Content (Join-Path $root 'router-config.json') -Raw|ConvertFrom-Json).sentinel -eq $true) 'blocked recovery writes no configuration bytes'
  Check (Test-Path (Join-Path $job 'active.lock')) 'actual worker creates its independent active lease'
  $active=[IO.File]::Open((Join-Path $job 'active.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $active.Dispose();Check $true 'worker releases active lease on completion'
 }
 if(-not $checks){throw 'No DPAPI checks ran.'}
 Write-Output "DPAPI: PASS - $checks checks; isolated fixtures only."
}finally{
 if(Test-Path -LiteralPath $base){
  $resolved=[IO.Path]::GetFullPath($base)
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing fixture cleanup outside temp.'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
