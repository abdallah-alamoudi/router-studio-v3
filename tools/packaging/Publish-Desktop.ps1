param([string]$Version='1.0.0-preview.1',[string]$ProjectRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
. (Join-Path $PSScriptRoot 'Desktop-Package.ps1')
$installationRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'installation'
$verificationRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'verification'
$runtime=Get-Content -LiteralPath (Join-Path $ProjectRoot 'src/router/runtime-manifest.json') -Raw|ConvertFrom-Json
$dotnet=Join-Path $ProjectRoot '.tools/dotnet/dotnet.exe';$env:DOTNET_CLI_HOME=Join-Path $ProjectRoot '.tools/cli-home'
if((& $dotnet --version) -cne $runtime.dotnet.sdk){throw 'The pinned .NET SDK is required.'}
$output=Join-Path $ProjectRoot ('artifacts/desktop/win-x64/'+$Version)
if(Test-Path -LiteralPath $output){throw 'Output already exists. Choose a new preview version; old artifacts are retained.'}
# Re-extract verified archives into a fresh staging tree rather than trusting a reused executable cache.
$stage=Join-Path $ProjectRoot ('artifacts/desktop/runtime-stage-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force|Out-Null
try {
 foreach($name in @('node','powershell')){
  $archive=Join-Path $ProjectRoot ('.tools/desktop-runtimes/'+$name+'-'+$runtime.$name.version+'.zip')
  if((DesktopHash $archive) -cne $runtime.$name.sha256){throw 'Runtime archive integrity failed.'}
  Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $stage $name)
 }
 $node=Join-Path $stage ('node/'+$runtime.node.archiveDirectory+'/node.exe');$pwsh=Join-Path $stage 'powershell/pwsh.exe'
 foreach($entry in @(@($node,$runtime.node.signer),@($pwsh,$runtime.powershell.signer))){$signature=Get-AuthenticodeSignature -LiteralPath $entry[0];if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike ('*'+$entry[1]+'*')){throw 'Runtime signature verification failed.'}}
 & $dotnet publish (Join-Path $ProjectRoot 'src/RouterStudio.Desktop/RouterStudio.Desktop.csproj') -c Release -r win-x64 --self-contained true '-p:RestoreLockedMode=true' ('-p:RuntimeFrameworkVersion='+$runtime.dotnet.runtime) -o $output
 if($LASTEXITCODE -ne 0){throw 'Self-contained publish failed.'}
 $routerControls=@('router.mjs','codex-config.mjs','provider-switch.mjs','model-manager.mjs','route-policy.mjs','custom-models.mjs','management.mjs','probe-engine.mjs','probe-cli.mjs','probe-sse.mjs')
 $workerControls=@('run-router.ps1','Studio-Worker.ps1','Studio-Protocol.ps1','Setup.ps1')
  foreach($name in $routerControls){Copy-Item -LiteralPath (Join-Path $ProjectRoot ('src/router/'+$name)) -Destination $output}
 foreach($name in $workerControls){Copy-Item -LiteralPath (Join-Path $ProjectRoot ('src/worker/'+$name)) -Destination $output}
 Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src/router/runtime-manifest.json') -Destination (Join-Path $output 'runtime-manifest.json')
 Copy-Item -LiteralPath (Join-Path $ProjectRoot 'Install-Desktop.cmd') -Destination $output
 New-Item -ItemType Directory -Path (Join-Path $output 'scripts'),(Join-Path $output 'runtime/node'),(Join-Path $output 'runtime/powershell') -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Desktop-Package.ps1') -Destination (Join-Path $output 'scripts')
 foreach($name in @('Install-Desktop.ps1','Uninstall-Desktop.ps1','Launch-Installed.ps1')){Copy-Item -LiteralPath (Join-Path $installationRoot $name) -Destination (Join-Path $output 'scripts')}
 foreach($name in @('New-DesktopSandbox.ps1','Test-SecondUserEncryption.ps1')){Copy-Item -LiteralPath (Join-Path $verificationRoot $name) -Destination (Join-Path $output 'scripts')}
 foreach($name in @('node.exe','LICENSE')){Copy-Item -LiteralPath (Join-Path $stage ('node/'+$runtime.node.archiveDirectory+'/'+$name)) -Destination (Join-Path $output 'runtime/node')}
 Get-ChildItem -LiteralPath (Join-Path $stage 'powershell') -Force|Copy-Item -Destination (Join-Path $output 'runtime/powershell') -Recurse
 $licenses=@(
  @('microsoft.netcore.app.runtime.win-x64',$runtime.dotnet.runtime,'LICENSE.TXT','dotnet-core'),
  @('microsoft.netcore.app.runtime.win-x64',$runtime.dotnet.runtime,'THIRD-PARTY-NOTICES.TXT','dotnet-core'),
  @('microsoft.windowsdesktop.app.runtime.win-x64',$runtime.dotnet.runtime,'LICENSE','windows-desktop'),
  @('system.security.cryptography.protecteddata',$runtime.dotnet.runtime,'THIRD-PARTY-NOTICES.TXT','protected-data'),
  @('system.security.cryptography.protecteddata',$runtime.dotnet.runtime,'system.security.cryptography.protecteddata.nuspec','protected-data'))
 foreach($entry in $licenses){$directory=Join-Path $output ('licenses/'+$entry[3]);New-Item -ItemType Directory -Path $directory -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $ProjectRoot ('.tools/nuget-packages/'+$entry[0]+'/'+$entry[1]+'/'+$entry[2])) -Destination $directory}
 foreach($name in @('DESKTOP-INSTALLATION.md','RELEASE-CHECKLIST.md','TASKS-8-12-RESULTS.md','USER-GUIDE.md','MANAGEMENT-CONTRACT.md','RELEASE-ACCEPTANCE.md','DESKTOP-ACCEPTANCE-RESULTS.md')){Copy-Item -LiteralPath (Join-Path $ProjectRoot ('docs/'+$name)) -Destination $output}
 WriteDesktopManifest $output $Version
 [void](TestDesktopManifest $output)
 $zip=$output+'.zip';Compress-Archive -LiteralPath $output -DestinationPath $zip
 [IO.File]::WriteAllText($zip+'.sha256',((DesktopHash $zip)+'  '+[IO.Path]::GetFileName($zip)),[Text.UTF8Encoding]::new($false))
 Write-Output ('Unsigned offline preview: '+$zip)
}finally{if([IO.Path]::GetFullPath($stage).StartsWith((Join-Path $ProjectRoot 'artifacts/desktop')+'\',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $stage -Recurse -Force}}
