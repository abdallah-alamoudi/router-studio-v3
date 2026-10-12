param([switch]$Acknowledge,[switch]$AllowUnsignedPreview,[switch]$RequireSignature)
$ErrorActionPreference='Stop'
if($RequireSignature -or -not $AllowUnsignedPreview){throw 'This unsigned preview requires -AllowUnsignedPreview. Signed public installation is unavailable.'}
if(-not $Acknowledge){if((Read-Host 'Save work and close Router Studio and Codex. Install the unsigned preview for this Windows user? Type INSTALL') -cne 'INSTALL'){throw 'Installation cancelled.'}}
$package=if((Split-Path $PSScriptRoot -Leaf) -eq 'scripts'){Split-Path $PSScriptRoot -Parent}else{Split-Path (Split-Path $PSScriptRoot -Parent) -Parent}
$appRoot=Join-Path $env:LOCALAPPDATA 'RouterStudio';$dataRoot=Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter'
$packageHelper=if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Desktop-Package.ps1')){Join-Path $PSScriptRoot 'Desktop-Package.ps1'}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'packaging/Desktop-Package.ps1'}
. $packageHelper
[void](TestDesktopManifest $package)
$mutex=[Threading.Mutex]::new($false,('Local\RouterStudioManagement-'+(DesktopScope $dataRoot)));$held=$false
$bootstrapChanges=@()
try{
try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
if(-not $held){throw 'Router management is busy; retry after it finishes.'}
DesktopOwner $appRoot $dataRoot
# Refuse a live installed UI or router rather than replacing files beneath it.
foreach($process in Get-CimInstance Win32_Process -Filter "Name='RouterStudio.Desktop.exe' OR Name='node.exe'"){
    if(($process.ExecutablePath -and $process.ExecutablePath.StartsWith($appRoot+'\',[StringComparison]::OrdinalIgnoreCase)) -or ($process.CommandLine -and $process.CommandLine.Contains((Join-Path $dataRoot 'router.mjs')))){throw 'Close Studio and stop its local router before installing. No process was terminated.'}
}
$scripts=Join-Path $appRoot 'scripts'
$launchers=@{}
foreach($name in @('Desktop','Router')){
    $command='"'+(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe')+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $scripts 'Launch-Installed.ps1')+'"'
    if($name -eq 'Router'){$command+=' -Router'}
    $text='CreateObject("WScript.Shell").Run "'+$command.Replace('"','""')+'", 0, False'
    $path=DesktopSafePath $appRoot ('Launch-'+$name+'.vbs')
    if(Test-Path -LiteralPath $path){if([IO.File]::ReadAllText($path) -cne $text){throw 'An existing launcher has external edits; installation refused.'}}
    $launchers[$path]=$text
}
$installedManifest=$null;$installedRelease=$null
foreach($name in @('Desktop-Package.ps1','Launch-Installed.ps1')){
    $destination=DesktopSafePath $appRoot ('scripts/'+$name)
    if(Test-Path -LiteralPath $destination){if((DesktopHash $destination) -cne (DesktopHash (Join-Path $PSScriptRoot $name))){
        if(-not $installedManifest){
            # Only bytes owned by a fully verified active release may be replaced.
            $pointer=Get-Content -LiteralPath (DesktopSafePath $appRoot 'current.json') -Raw -Encoding UTF8|ConvertFrom-Json
            if($pointer.version -notmatch '^\d+\.\d+\.\d+(?:-preview\.\d+)?$'){throw 'Invalid installed release pointer.'}
            $installedRelease=DesktopSafePath $appRoot ('releases/'+$pointer.version)
            $installedManifest=TestDesktopManifest $installedRelease
            if($installedManifest.version -cne $pointer.version){throw 'Installed release version mismatch.'}
        }
        $entry=@($installedManifest.files|Where-Object path -CEQ ('scripts/'+$name))
        if($entry.Count -ne 1 -or (DesktopHash $destination) -cne $entry[0].sha256){throw 'An existing stable launcher has external edits; installation refused.'}
    }}
}
DesktopPrivateDirectory $appRoot;New-Item -ItemType Directory -Path $scripts -Force|Out-Null
foreach($name in @('Desktop-Package.ps1','Launch-Installed.ps1')){
    $destination=DesktopSafePath $appRoot ('scripts/'+$name);$source=Join-Path $PSScriptRoot $name
    if(-not(Test-Path -LiteralPath $destination) -or (DesktopHash $destination) -cne (DesktopHash $source)){
        $previous=if(Test-Path -LiteralPath $destination){[IO.File]::ReadAllBytes($destination)}else{$null}
        $bootstrapChanges+=@{path=$destination;previous=$previous;installedHash=(DesktopHash $source)}
        DesktopCopy $source $destination
    }
}
foreach($path in $launchers.Keys){if(-not(Test-Path -LiteralPath $path)){DesktopText $path $launchers[$path] ([Text.Encoding]::Unicode)}}
InstallDesktopPayload $package $appRoot $dataRoot -Acknowledge
foreach($name in @('Desktop','Router')){
    [void](DesktopSafePath $appRoot ('Launch-'+$name+'.vbs'))
}
Write-Output 'Installed for the current user. Open Launch-Desktop.vbs. Startup is opt-in in Settings; legacy startup is retained.'
}catch{
    # Ordinary installation failures restore bootstrap preimages as well as payload controls.
    foreach($change in $bootstrapChanges){
        if((Test-Path -LiteralPath $change.path) -and (DesktopHash $change.path) -ceq $change.installedHash){
            if($null -eq $change.previous){Remove-Item -LiteralPath $change.path -Force}else{
                $temporary=$change.path+'.tmp-'+[guid]::NewGuid().ToString('N')
                try{[IO.File]::WriteAllBytes($temporary,$change.previous);DesktopReplace $temporary $change.path}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
            }
        }
    }
    throw
}finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
