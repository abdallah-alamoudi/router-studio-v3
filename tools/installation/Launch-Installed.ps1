param([switch]$Router)
$ErrorActionPreference='Stop'
$appRoot=Split-Path $PSScriptRoot -Parent
. (if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Desktop-Package.ps1')){Join-Path $PSScriptRoot 'Desktop-Package.ps1'}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'packaging/Desktop-Package.ps1'})
$dataRoot=Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter'
DesktopOwner $appRoot $dataRoot
if(Test-Path -LiteralPath (Join-Path $appRoot 'upgrade.pending.json')){throw 'Upgrade recovery is required. Run the installer again before launching.'}
$pointer=Get-Content -LiteralPath (DesktopSafePath $appRoot 'current.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($pointer.version -notmatch '^\d+\.\d+\.\d+(?:-preview\.\d+)?$'){throw 'Invalid release pointer.'}
$release=DesktopSafePath $appRoot ('releases/'+$pointer.version)
[void](TestDesktopManifest $release)
if($Router){
    Start-Process -FilePath (Join-Path $release 'runtime/powershell/pwsh.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $dataRoot 'run-router.ps1')+'"')) -WindowStyle Hidden
}else{Start-Process -FilePath (Join-Path $release 'RouterStudio.Desktop.exe') -WindowStyle Hidden}
