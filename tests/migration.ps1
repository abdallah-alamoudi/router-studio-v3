param([string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop';$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
. (Join-Path $ProjectRoot 'tools/packaging/Desktop-Package.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('Studio migration Ω '+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
$checks=0
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start()
function Assert($condition,$name){if(-not $condition){throw $name};$script:checks++;Write-Output "PASS $name"}
function Fixture($name){$app=Join-Path $root ($name+'/app');$data=Join-Path $root ($name+'/data');$package=Join-Path $root ($name+'/package');New-Item -ItemType Directory -Force -Path $app,$data,$package|Out-Null;foreach($file in @('secrets.xml','router-config.json','codex-router-catalog.json','provider-state.json')){[IO.File]::WriteAllText((Join-Path $data $file),'fixture '+$file)};[IO.File]::WriteAllText((Join-Path $package 'RouterStudio.Desktop.exe'),'fixture binary');[IO.File]::WriteAllText((Join-Path $package 'router.mjs'),'new engine');WriteDesktopManifest $package '1.0.0-preview.1';return @{app=$app;data=$data;package=$package}}
try{
 $f=Fixture 'preserve';$before=@{};foreach($file in @('secrets.xml','router-config.json','codex-router-catalog.json','provider-state.json')){$before[$file]=[IO.File]::ReadAllText((Join-Path $f.data $file))}
 InstallDesktopPayload $f.package $f.app $f.data -Acknowledge -Fixture
 Assert $listener.Server.IsBound 'occupied_port_kept'
 $foreignConfig=Join-Path $root 'externally-edited-codex-config.toml';[IO.File]::WriteAllText($foreignConfig,'external Codex preferences');
 foreach($file in $before.Keys){Assert ([IO.File]::ReadAllText((Join-Path $f.data $file)) -ceq $before[$file]) ('v3_migration_preserves_'+$file)}
 Assert (Test-Path -LiteralPath (Join-Path $f.app 'current.json')) 'current_pointer_committed'
 $pointer=[IO.File]::ReadAllText((Join-Path $f.app 'current.json'));[IO.File]::WriteAllText((Join-Path $f.package 'router.mjs'),'engine two');WriteDesktopManifest $f.package '1.0.0-preview.2'
 try{InstallDesktopPayload $f.package $f.app $f.data -Acknowledge -Fixture -FailAfterControls;throw 'Expected failure'}catch{Write-Output $_.ScriptStackTrace;Write-Output $_.Exception.Message;Assert ($_.Exception.Message -eq 'Injected upgrade interruption') 'partial_upgrade_injected'}
 Assert ([IO.File]::ReadAllText((Join-Path $f.app 'current.json')) -ceq $pointer) 'partial_upgrade_recovers_pointer';Assert ([IO.File]::ReadAllText((Join-Path $f.data 'router.mjs')) -ceq 'new engine') 'partial_upgrade_recovers_control'
 $record=[IO.File]::ReadAllText((Join-Path $f.app 'install-record.json'))
 try{InstallDesktopPayload $f.package $f.app $f.data -Acknowledge -Fixture -FailAfterPointer;throw 'Expected failure'}catch{Assert ($_.Exception.Message -eq 'Injected pointer interruption') 'pointer_interruption_injected'}
 Assert ([IO.File]::ReadAllText((Join-Path $f.app 'current.json')) -ceq $pointer) 'pointer_interruption_restores_previous_release'
 Assert ([IO.File]::ReadAllText((Join-Path $f.app 'install-record.json')) -ceq $record) 'pointer_interruption_restores_ownership_record'
 [IO.File]::WriteAllText((Join-Path $f.data 'router.mjs'),'external engine edit');$blocked=$false;try{InstallDesktopPayload $f.package $f.app $f.data -Acknowledge -Fixture}catch{$blocked=$true};Assert $blocked 'upgrade_refuses_external_control_edit';Assert ([IO.File]::ReadAllText((Join-Path $f.data 'router.mjs')) -ceq 'external engine edit') 'upgrade_keeps_external_control_edit';[IO.File]::WriteAllText((Join-Path $f.data 'router.mjs'),'new engine')
 $orphan=Join-Path $f.app 'releases/.stage-interrupted-fixture';New-Item -ItemType Directory -Path $orphan|Out-Null;[IO.File]::WriteAllText((Join-Path $orphan 'partial'),'partial staged copy');InstallDesktopPayload $f.package $f.app $f.data -Acknowledge -Fixture;Assert ((Get-Content -LiteralPath (Join-Path $f.app 'current.json') -Raw|ConvertFrom-Json).version -eq '1.0.0-preview.2') 'orphan_staging_does_not_block_retry';$pointer=[IO.File]::ReadAllText((Join-Path $f.app 'current.json'))
 [IO.File]::WriteAllText((Join-Path $f.package 'router.mjs'),'tampered');$blocked=$false;try{InstallDesktopPayload $f.package $f.app $f.data -Acknowledge -Fixture}catch{$blocked=$true};Assert $blocked 'tampered_runtime_rejected';Assert ([IO.File]::ReadAllText((Join-Path $f.app 'current.json')) -ceq $pointer) 'tamper_changes_nothing'
 $ownerPath=Join-Path $f.app 'owner.json';$owner=[IO.File]::ReadAllText($ownerPath);[IO.File]::WriteAllText($ownerPath,'{"sid":"S-1-5-21-wrong"}');$blocked=$false;try{RemoveDesktopPayload $f.app $f.data -Fixture}catch{$blocked=$true};Assert $blocked 'wrong_user_store_refused';[IO.File]::WriteAllText($ownerPath,$owner)
 [IO.File]::WriteAllText((Join-Path $f.data 'router.mjs'),'external engine edit');RemoveDesktopPayload $f.app $f.data -Fixture;Assert ([IO.File]::ReadAllText((Join-Path $f.data 'router.mjs')) -ceq 'external engine edit') 'uninstall_keeps_external_edits';foreach($file in $before.Keys){Assert ([IO.File]::ReadAllText((Join-Path $f.data $file)) -ceq $before[$file]) ('uninstall_retains_'+$file)}
 Assert ([IO.File]::ReadAllText($foreignConfig) -ceq 'external Codex preferences') 'uninstall_does_not_overwrite_external_config'
 $edited=Join-Path $f.app 'releases/1.0.0-preview.1/router.mjs';[IO.File]::WriteAllText($edited,'external release edit');RemoveDesktopRecoveryFiles $f.app $f.data -Fixture
 Assert ([IO.File]::ReadAllText($edited) -ceq 'external release edit') 'cleanup_keeps_edited_release'
 Assert (-not(Test-Path -LiteralPath (Join-Path $f.app 'releases/1.0.0-preview.2'))) 'cleanup_removes_verified_application_files'
 Assert ([IO.File]::ReadAllText((Join-Path $f.data 'secrets.xml')) -ceq $before['secrets.xml']) 'cleanup_retains_encrypted_user_data'
 $r=Fixture 'reactivate';[IO.File]::WriteAllText((Join-Path $r.data 'router.mjs'),'original pre-desktop engine')
 InstallDesktopPayload $r.package $r.app $r.data -Acknowledge -Fixture;RemoveDesktopPayload $r.app $r.data -Fixture
 Assert ([IO.File]::ReadAllText((Join-Path $r.data 'router.mjs')) -ceq 'original pre-desktop engine') 'first_uninstall_restores_original_engine'
 InstallDesktopPayload $r.package $r.app $r.data -Acknowledge -Fixture
 Assert (Test-Path -LiteralPath (Join-Path $r.app 'current.json')) 'reinstall_after_restored_controls_reactivates'
 RemoveDesktopPayload $r.app $r.data -Fixture
 Assert ([IO.File]::ReadAllText((Join-Path $r.data 'router.mjs')) -ceq 'original pre-desktop engine') 'second_uninstall_preserves_original_preimage'
 [IO.File]::WriteAllText((Join-Path $r.data 'router.mjs'),'external after uninstall');$blocked=$false
 try{InstallDesktopPayload $r.package $r.app $r.data -Acknowledge -Fixture}catch{$blocked=$true}
 Assert ($blocked -and [IO.File]::ReadAllText((Join-Path $r.data 'router.mjs')) -ceq 'external after uninstall') 'reinstall_refuses_new_external_edits'
 Write-Output "MIGRATION: PASS - $checks checks; isolated fixtures only."
}finally{$listener.Stop();if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
