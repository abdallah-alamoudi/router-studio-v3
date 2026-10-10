param(
 [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent),
 [string]$DotNet,
 [string]$OutputDirectory,
 [ValidateSet('Debug','Release')][string]$Configuration='Release',
 [switch]$NoBuild
)
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$env:DOTNET_CLI_HOME=Join-Path $ProjectRoot '.tools/cli-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
if(-not $IsWindows){throw 'Native acceptance requires Windows and an interactive desktop.'}
if(-not $DotNet){$DotNet=Join-Path $ProjectRoot '.tools/dotnet/dotnet.exe'}
if(-not(Test-Path -LiteralPath $DotNet -PathType Leaf)){throw 'The .NET 10 SDK is required.'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $ProjectRoot '.superpowers/sdd/2026-10-05-router-studio-desktop/task-4/native'}
$project=Join-Path $ProjectRoot 'tests/RouterStudio.Desktop.Acceptance/RouterStudio.Desktop.Acceptance.csproj'
if(-not $NoBuild){
 & $DotNet build $project -c $Configuration -p:RestoreLockedMode=true
 if($LASTEXITCODE -ne 0){throw 'Native acceptance build failed.'}
}
$assembly=Join-Path $ProjectRoot "tests/RouterStudio.Desktop.Acceptance/bin/$Configuration/net10.0-windows/RouterStudio.Desktop.Acceptance.dll"
& $DotNet $assembly ([IO.Path]::GetFullPath($OutputDirectory))
if($LASTEXITCODE -ne 0){throw 'Native acceptance failed. Read the saved acceptance evidence.'}
$fixture=Join-Path $OutputDirectory 'startup-fixture'
$null=New-Item -ItemType Directory -Force -Path $fixture
$desktop=Join-Path $ProjectRoot "src/RouterStudio.Desktop/bin/$Configuration/net10.0-windows/RouterStudio.Desktop.dll"
$launch=[Diagnostics.ProcessStartInfo]::new($DotNet)
$launch.UseShellExecute=$false
$launch.CreateNoWindow=$true
foreach($argument in @($desktop,'--project-root',[IO.Path]::GetFullPath($fixture))){$launch.ArgumentList.Add($argument)}
$owned=[Diagnostics.Process]::Start($launch)
try{
 $deadline=[DateTime]::UtcNow.AddSeconds(15)
 do{$owned.Refresh();if($owned.HasExited){throw 'Desktop entry point exited before opening its window.'};if($owned.MainWindowHandle -ne [IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
 if($owned.MainWindowHandle -eq [IntPtr]::Zero -or $owned.MainWindowTitle -notlike 'Router Studio*'){throw 'Desktop entry point did not open the expected window.'}
 $second=[Diagnostics.Process]::Start($launch)
 try{if(-not $second.WaitForExit(5000) -or $second.ExitCode -ne 0){throw 'Second instance did not activate the existing window and exit.'}}finally{if(-not $second.HasExited){$second.Kill()};$second.Dispose()}
 if(-not $owned.CloseMainWindow() -or -not $owned.WaitForExit(5000)){throw 'Desktop entry point did not close normally.'}
 if($owned.ExitCode -ne 0){throw 'Desktop entry point returned an error.'}
 'PASS native entry point: isolated empty root, open and normal close' | Set-Content -LiteralPath (Join-Path $OutputDirectory 'startup-smoke.txt')
 Write-Output 'PASS native entry point: isolated empty root, second-instance activation, open and normal close'
}finally{
 if(-not $owned.HasExited){$owned.Kill();$owned.WaitForExit()}
 $owned.Dispose()
}
Write-Output 'Fixture only: no installed configuration or upstream requests.'
