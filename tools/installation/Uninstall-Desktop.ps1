param([switch]$Acknowledge,[switch]$RemoveRecoveryFiles)
$ErrorActionPreference='Stop'
if(-not $Acknowledge){throw 'Use -Acknowledge after closing Studio and stopping its router. Keys and settings will be retained.'}
$packageHelper=if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Desktop-Package.ps1')){Join-Path $PSScriptRoot 'Desktop-Package.ps1'}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'packaging/Desktop-Package.ps1'}
. $packageHelper
$app=Join-Path $env:LOCALAPPDATA 'RouterStudio';$data=Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter'
foreach($process in Get-CimInstance Win32_Process -Filter "Name='RouterStudio.Desktop.exe' OR Name='node.exe'"){if(($process.ExecutablePath -and $process.ExecutablePath.StartsWith($app+'\',[StringComparison]::OrdinalIgnoreCase)) -or ($process.CommandLine -and $process.CommandLine.Contains((Join-Path $data 'router.mjs')))){throw 'Close Studio and stop its router before uninstalling.'}}
RemoveDesktopPayload $app $data
if($RemoveRecoveryFiles){RemoveDesktopRecoveryFiles $app $data}
$run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startup=Get-ItemProperty -LiteralPath $run -ErrorAction SilentlyContinue
foreach($entry in @(@('RouterStudioDesktop','Desktop'),@('RouterStudioRouter','Router'))){
    $expected='"'+(Join-Path $env:SystemRoot 'System32/wscript.exe')+'" //B "'+(Join-Path $app ('Launch-'+$entry[1]+'.vbs'))+'"'
    $property=if($null -ne $startup){$startup.PSObject.Properties[$entry[0]]}else{$null}
    if($null -ne $property -and $property.Value -ceq $expected){Remove-ItemProperty -LiteralPath $run -Name $entry[0]}
}
Write-Output 'Codex provider settings were preserved. Use Backups > Restore before uninstalling if you want direct settings.'
