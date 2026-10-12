param([string]$PackageRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/desktop/win-x64/1.0.0-preview.8'))
$ErrorActionPreference='Stop';$project=Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'tools/packaging/Desktop-Package.ps1')
$checks=0
function Assert($value,$name){if(-not $value){throw $name};$script:checks++;Write-Output ('PASS '+$name)}
$manifest=TestDesktopManifest $PackageRoot
Assert ($manifest.version -eq [IO.Path]::GetFileName($PackageRoot)) 'complete_package_manifest'
$runtime=Get-Content -LiteralPath (Join-Path $PackageRoot 'runtime-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$node=Join-Path $PackageRoot 'runtime/node/node.exe';$pwsh=Join-Path $PackageRoot 'runtime/powershell/pwsh.exe'
Assert ((& $node --version) -ceq ('v'+$runtime.node.version)) 'private_node_version'
Assert ((& $pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') -ceq $runtime.powershell.version) 'private_powershell_version'
foreach($entry in @(@($node,$runtime.node.signer),@($pwsh,$runtime.powershell.signer))){$signature=Get-AuthenticodeSignature -LiteralPath $entry[0];Assert ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -like ('*'+$entry[1]+'*')) 'private_runtime_executable_signature'}
foreach($file in Get-ChildItem -LiteralPath $PackageRoot -Filter '*.mjs'){& $node --check $file.FullName;if($LASTEXITCODE -ne 0){throw 'Packaged Node module syntax failed.'}}
Assert (-not @($manifest.files|Where-Object path -Match '(^|/)(secrets\.xml|auth\.json|router-config\.json|provider-state\.json|\.env|node-path\.txt)$').Count) 'package_excludes_user_credentials_and_configuration'
Assert ((Test-Path -LiteralPath (Join-Path $PackageRoot 'USER-GUIDE.md')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'MANAGEMENT-CONTRACT.md')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'RELEASE-ACCEPTANCE.md')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'DESKTOP-ACCEPTANCE-RESULTS.md'))) 'current_usage_contract_and_acceptance_guides_included'
foreach($file in @('custom-models.mjs','management.mjs')){Assert (Test-Path -LiteralPath (Join-Path $PackageRoot $file)) ('custom_management_module_included_'+$file)}
Assert ((Test-Path -LiteralPath (Join-Path $PackageRoot 'scripts/New-DesktopSandbox.ps1')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'scripts/Test-SecondUserEncryption.ps1'))) 'external_acceptance_helpers_included'
Assert ((Test-Path -LiteralPath (Join-Path $PackageRoot 'runtime/node/LICENSE')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'runtime/powershell/ThirdPartyNotices.txt'))) 'redistribution_notices_present'
Assert ((Test-Path -LiteralPath (Join-Path $PackageRoot 'licenses/dotnet-core/THIRD-PARTY-NOTICES.TXT')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'licenses/windows-desktop/LICENSE')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'licenses/protected-data/THIRD-PARTY-NOTICES.TXT')) -and (Test-Path -LiteralPath (Join-Path $PackageRoot 'licenses/protected-data/system.security.cryptography.protecteddata.nuspec'))) 'dotnet_and_dependency_licenses_present'
try{& (Join-Path $PackageRoot 'scripts/Install-Desktop.ps1') -RequireSignature -Acknowledge;throw 'Signed mode unexpectedly accepted'}catch{Assert ($_.Exception.Message -like '*unsigned preview requires*') 'signed_install_mode_refuses_unsigned_preview'}
$runtimeConfig=Get-Content -LiteralPath (Join-Path $PackageRoot 'RouterStudio.Desktop.runtimeconfig.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert (@($runtimeConfig.runtimeOptions.includedFrameworks|Where-Object { $_.name -eq 'Microsoft.NETCore.App' -and $_.version -eq $runtime.dotnet.runtime }).Count -eq 1) 'self_contained_dotnet_runtime_pinned'
$zip=$PackageRoot+'.zip';$expected=([IO.File]::ReadAllText($zip+'.sha256').Split(' ')[0])
Assert ((DesktopHash $zip) -ceq $expected) 'archive_checksum_matches'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('Packaged Studio Ω '+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture|Out-Null
$owned=$null
try {
 $launch=[Diagnostics.ProcessStartInfo]::new((Join-Path $PackageRoot 'RouterStudio.Desktop.exe'));$launch.UseShellExecute=$false;$launch.CreateNoWindow=$true
 $launch.Environment['PATH']=Join-Path $env:SystemRoot 'System32';$launch.Environment['DOTNET_ROOT']=Join-Path $fixture 'no-global-runtime'
 foreach($argument in @('--project-root',$fixture)){$launch.ArgumentList.Add($argument)}
 $owned=[Diagnostics.Process]::Start($launch);$deadline=[DateTime]::UtcNow.AddSeconds(15)
 do{$owned.Refresh();if($owned.HasExited){throw 'Packaged app exited before opening.'};if($owned.MainWindowHandle -ne [IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
 Assert ($owned.MainWindowHandle -ne [IntPtr]::Zero -and $owned.MainWindowTitle -like 'Router Studio*') 'packaged_app_opens_without_runtime_on_PATH'
 $second=[Diagnostics.Process]::Start($launch)
 try{Assert ($second.WaitForExit(5000) -and $second.ExitCode -eq 0) 'packaged_second_instance_activates_existing_window'}finally{if(-not $second.HasExited){$second.Kill()};$second.Dispose()}
 Assert ($owned.CloseMainWindow() -and $owned.WaitForExit(5000) -and $owned.ExitCode -eq 0) 'packaged_app_closes_normally'
}finally{if($owned){if(-not $owned.HasExited){$owned.Kill();$owned.WaitForExit()};$owned.Dispose()};$target=[IO.Path]::GetFullPath($fixture);if($target.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $target -Recurse -Force}}
Write-Output "PACKAGE: PASS - $checks checks; isolated empty-root smoke, not clean-machine acceptance."
