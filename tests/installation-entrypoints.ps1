param([string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
. (Join-Path $ProjectRoot 'tools/packaging/Desktop-Package.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('Studio installer '+[guid]::NewGuid().ToString('N'))
$savedLocal=$env:LOCALAPPDATA;$checks=0
function Assert($condition,$name){if(-not $condition){throw $name};$script:checks++;Write-Output "PASS $name"}
function Package($version){
 $package=Join-Path $root $version
 New-Item -ItemType Directory -Force -Path (Join-Path $package 'scripts'),(Join-Path $package 'runtime/node'),(Join-Path $package 'runtime/powershell')|Out-Null
 Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools/packaging/Desktop-Package.ps1') -Destination (Join-Path $package 'scripts')
 foreach($name in @('Install-Desktop.ps1','Uninstall-Desktop.ps1','Launch-Installed.ps1')){Copy-Item -LiteralPath (Join-Path $ProjectRoot ('tools/installation/'+$name)) -Destination (Join-Path $package 'scripts')}
 foreach($name in @('RouterStudio.Desktop.exe','router.mjs','runtime/node/node.exe','runtime/node/LICENSE','runtime/powershell/pwsh.exe','runtime/powershell/LICENSE.txt','runtime-manifest.json','Studio-Worker.ps1','Setup.ps1','codex-config.mjs','provider-switch.mjs','model-manager.mjs','route-policy.mjs','probe-engine.mjs','probe-cli.mjs','probe-sse.mjs','run-router.ps1','Studio-Protocol.ps1')){[IO.File]::WriteAllText((Join-Path $package $name),'synthetic payload '+$version)}
 WriteDesktopManifest $package $version
 return $package
}
function Install($package){
 # Capture the child process streams explicitly. Expected refusal cases write diagnostics
 # to stderr; redirecting native stderr directly into a parent Stop pipeline can abort
 # this harness before it can assert the nonzero exit code.
 $stdout=Join-Path $root ([guid]::NewGuid().ToString('N')+'.out.txt')
 $stderr=Join-Path $root ([guid]::NewGuid().ToString('N')+'.err.txt')
 $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
 $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $package 'scripts/Install-Desktop.ps1')+'"'),'-Acknowledge','-AllowUnsignedPreview')
 $process=Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList $args -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 if(Test-Path -LiteralPath $stdout){Get-Content -LiteralPath $stdout | ForEach-Object {Write-Host $_}}
 if(Test-Path -LiteralPath $stderr){Get-Content -LiteralPath $stderr | ForEach-Object {Write-Host $_}}
 Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
 return $process.ExitCode
}
try{
 $env:LOCALAPPDATA=Join-Path $root 'profile';$app=Join-Path $env:LOCALAPPDATA 'RouterStudio';$data=Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter'
 New-Item -ItemType Directory -Force -Path $data|Out-Null
 @{SAFE_8STOKEN_LOCAL_TOKEN=(ConvertTo-SecureString 'synthetic-local-token' -AsPlainText -Force)}|Export-Clixml -LiteralPath (Join-Path $data 'secrets.xml')
 foreach($name in @('router-config.json','codex-router-catalog.json','provider-state.json')){[IO.File]::WriteAllText((Join-Path $data $name),'synthetic existing '+$name)}
 $before=@{};foreach($name in @('secrets.xml','router-config.json','codex-router-catalog.json','provider-state.json')){$before[$name]=DesktopHash (Join-Path $data $name)}
 $first=Package '1.0.0-preview.101';Assert ((Install $first) -eq 0) 'actual_PS5_installer_first_install'
 $second=Package '1.0.0-preview.102'
 Add-Content -LiteralPath (Join-Path $second 'scripts/Desktop-Package.ps1') -Value '# new compatible helper version' -Encoding UTF8
 WriteDesktopManifest $second '1.0.0-preview.102'
 Assert ((Install $second) -eq 0) 'owned_bootstrap_upgrades_without_manual_replacement'
 Assert ((DesktopHash (Join-Path $app 'scripts/Desktop-Package.ps1')) -ceq (DesktopHash (Join-Path $second 'scripts/Desktop-Package.ps1'))) 'bootstrap_matches_active_package'
 $failed=Package '1.0.0-preview.104';$helperBefore=DesktopHash (Join-Path $app 'scripts/Desktop-Package.ps1')
 [IO.File]::WriteAllText((Join-Path $data 'router.mjs'),'external control edit')
 Assert ((Install $failed) -ne 0) 'payload_conflict_refused_after_bootstrap_update'
 Assert ((DesktopHash (Join-Path $app 'scripts/Desktop-Package.ps1')) -ceq $helperBefore) 'failed_payload_restores_bootstrap_preimage'
 Copy-Item -LiteralPath (Join-Path $second 'router.mjs') -Destination (Join-Path $data 'router.mjs') -Force
 $pointer=DesktopHash (Join-Path $app 'current.json');$third=Package '1.0.0-preview.103'
 Add-Content -LiteralPath (Join-Path $app 'scripts/Launch-Installed.ps1') -Value '# external user edit' -Encoding UTF8
 Assert ((Install $third) -ne 0) 'external_bootstrap_edit_refused'
 Assert ((DesktopHash (Join-Path $app 'current.json')) -ceq $pointer) 'refusal_preserves_active_pointer'
 foreach($name in $before.Keys){Assert ((DesktopHash (Join-Path $data $name)) -ceq $before[$name]) ('installer_preserves_'+$name)}
 & (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $second 'scripts/Uninstall-Desktop.ps1') -Acknowledge -RemoveRecoveryFiles
 Assert ($LASTEXITCODE -eq 0 -and -not(Test-Path -LiteralPath (Join-Path $app 'current.json'))) 'actual_PS5_uninstall_deactivates'
 & (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $second 'scripts/Uninstall-Desktop.ps1') -Acknowledge -RemoveRecoveryFiles
 Assert ($LASTEXITCODE -eq 0) 'repeated_uninstall_without_startup_entries_succeeds'
 Copy-Item -LiteralPath (Join-Path $second 'scripts/Launch-Installed.ps1') -Destination (Join-Path $app 'scripts/Launch-Installed.ps1') -Force
 Assert ((Install $second) -eq 0) 'retained_package_reinstalls_after_cleanup'
 Assert (Test-Path -LiteralPath (Join-Path $app 'current.json')) 'reinstall_reactivates_pointer'
 & (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $second 'scripts/Uninstall-Desktop.ps1') -Acknowledge
 Assert ($LASTEXITCODE -eq 0) 'reactivated_package_uninstalls_again'
 [IO.File]::WriteAllText((Join-Path $data 'router.mjs'),'external edit after deactivation')
 Assert ((Install $second) -ne 0) 'reinstall_keeps_external_control_edits'
 Assert ([IO.File]::ReadAllText((Join-Path $data 'router.mjs')) -ceq 'external edit after deactivation') 'refused_reinstall_preserves_control_bytes'
 foreach($name in $before.Keys){Assert ((DesktopHash (Join-Path $data $name)) -ceq $before[$name]) ('uninstall_preserves_'+$name)}
 Write-Output "INSTALLER: PASS $checks checks; synthetic payload and redirected process profile only; no launch, startup writes or upstream requests."
}finally{
 $env:LOCALAPPDATA=$savedLocal
 $resolved=[IO.Path]::GetFullPath($root);$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'Studio installer *' -and (Test-Path -LiteralPath $resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
