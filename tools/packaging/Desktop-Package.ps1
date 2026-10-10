# Shared by the offline installer, launcher, and isolated migration fixtures.
Set-StrictMode -Version 3
$ErrorActionPreference='Stop'
function DesktopSid { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function DesktopScope($DataRoot,[switch]$Fixture){if(-not $Fixture){return $env:USERNAME};$sha=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($DataRoot))).Replace('-','')}finally{$sha.Dispose()}}
function DesktopHash($path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function DesktopReplace($temporary,$target){if(Test-Path -LiteralPath $target){[IO.File]::Replace($temporary,$target,[NullString]::Value)}else{[IO.File]::Move($temporary,$target)}}
function DesktopCopy($source,$target){$temporary=$target+'.tmp-'+[guid]::NewGuid().ToString('N');try{Copy-Item -LiteralPath $source -Destination $temporary;DesktopReplace $temporary $target}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}}
function DesktopText($target,$text,$encoding){$temporary=$target+'.tmp-'+[guid]::NewGuid().ToString('N');try{[IO.File]::WriteAllText($temporary,$text,$encoding);DesktopReplace $temporary $target}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}}
function DesktopWrite($path,$value) {
    $temporary=$path+'.tmp-'+[guid]::NewGuid().ToString('N')
    try { [IO.File]::WriteAllText($temporary,($value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false)); DesktopReplace $temporary $path }
    finally { if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force} }
}
function DesktopSafePath($root,$relative) {
    if(-not $relative -or $relative -match '[:\\]' -or [IO.Path]::IsPathRooted($relative) -or $relative.Split('/') -contains '..' -or $relative.Split('/') -contains '.' ){throw 'Unsafe package path.'}
    $base=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\';$path=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Package path escaped its root.'}
    $cursor=$path
    while($cursor -and $cursor.Length -ge $base.TrimEnd('\').Length){
        if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse paths are refused.'}}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $path
}
function WriteDesktopManifest($PackageRoot,$Version) {
    if($Version -notmatch '^\d+\.\d+\.\d+(?:-preview\.\d+)?$'){throw 'Invalid package version.'}
    $root=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\');$files=@()
    foreach($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object FullName){
        $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
        if($relative -eq 'package-manifest.json'){continue}
        [void](DesktopSafePath $root $relative)
        $files+=@{path=$relative;length=$file.Length;sha256=(DesktopHash $file.FullName)}
    }
    DesktopWrite (Join-Path $root 'package-manifest.json') @{schemaVersion=1;version=$Version;platform='win-x64';channel='unsigned-preview';files=$files}
}
function TestDesktopManifest($PackageRoot,[switch]$Fixture) {
    $manifestPath=DesktopSafePath $PackageRoot 'package-manifest.json'
    if((Get-Item -LiteralPath $manifestPath).Length -gt 1048576){throw 'Oversized package manifest.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or $manifest.platform -ne 'win-x64' -or $manifest.channel -ne 'unsigned-preview' -or $manifest.version -notmatch '^\d+\.\d+\.\d+(?:-preview\.\d+)?$'){throw 'Unsupported package manifest.'}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($directory in Get-ChildItem -LiteralPath $PackageRoot -Directory -Recurse -Force){[void](DesktopSafePath $PackageRoot ($directory.FullName.Substring([IO.Path]::GetFullPath($PackageRoot).TrimEnd('\').Length+1).Replace('\','/')))}
    foreach($file in $manifest.files){
        if(-not $names.Add([string]$file.path) -or $file.path -eq 'package-manifest.json' -or $file.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid package entry.'}
        $path=DesktopSafePath $PackageRoot $file.path
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne $file.length -or (DesktopHash $path) -cne $file.sha256){throw 'Package integrity verification failed.'}
    }
    foreach($file in Get-ChildItem -LiteralPath $PackageRoot -File -Recurse -Force){$relative=$file.FullName.Substring([IO.Path]::GetFullPath($PackageRoot).TrimEnd('\').Length+1).Replace('\','/');if($relative -ne 'package-manifest.json' -and -not $names.Contains($relative)){throw 'Unlisted package file.'}}
    $required=@('RouterStudio.Desktop.exe','router.mjs')
    if(-not $Fixture){$required+=@('runtime/node/node.exe','runtime/node/LICENSE','runtime/powershell/pwsh.exe','runtime/powershell/LICENSE.txt','runtime-manifest.json','Studio-Worker.ps1','Setup.ps1')}
    foreach($name in $required){if(-not $names.Contains($name)){throw 'Required package file is missing.'}}
    return $manifest
}
function DesktopOwner($AppRoot,$DataRoot,[switch]$Fixture) {
    foreach($root in @($AppRoot,$DataRoot)){
        if(-not [IO.Path]::IsPathRooted($root) -or [IO.Path]::GetFullPath($root).TrimEnd('\') -eq [IO.Path]::GetPathRoot($root).TrimEnd('\')){throw 'Invalid installation root.'}
        [void](DesktopSafePath $root 'owner.json')
    }
    if(-not $Fixture){
        if([IO.Path]::GetFullPath($AppRoot).TrimEnd('\') -cne (Join-Path $env:LOCALAPPDATA 'RouterStudio') -or [IO.Path]::GetFullPath($DataRoot).TrimEnd('\') -cne (Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter')){throw 'Only the current-user installation roots are supported.'}
        $store=Join-Path $DataRoot 'secrets.xml'
        if(Test-Path -LiteralPath $store){try{$keys=Import-Clixml -LiteralPath $store;if($keys.SAFE_8STOKEN_LOCAL_TOKEN.Length -lt 1){throw 'Invalid store'}}catch{throw 'The encrypted store cannot be opened by this Windows user.'}}
    }
    $owner=Join-Path $AppRoot 'owner.json'
    if(Test-Path -LiteralPath $owner){if((Get-Content -LiteralPath $owner -Raw -Encoding UTF8|ConvertFrom-Json).sid -cne (DesktopSid)){throw 'Installation belongs to another Windows user.'}}
}
function DesktopPrivateDirectory($path) {
    New-Item -ItemType Directory -Path $path -Force|Out-Null
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @((DesktopSid),'S-1-5-18')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
    if($PSVersionTable.PSVersion.Major -ge 7){[IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($path),$acl)}else{[IO.DirectoryInfo]::new($path).SetAccessControl($acl)}
}
function RepairDesktopUpgrade($AppRoot,$DataRoot) {
    $journalPath=DesktopSafePath $AppRoot 'upgrade.pending.json'
    if(-not(Test-Path -LiteralPath $journalPath)){return}
    $journal=Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($item in $journal.controls){
        $target=DesktopSafePath $DataRoot $item.name;$backup=DesktopSafePath $AppRoot $item.backup
        $current=if(Test-Path -LiteralPath $target){DesktopHash $target}else{''}
        if($current -ceq $item.beforeHash){continue}
        if($current -cne $item.installedHash){throw 'Interrupted upgrade has external edits; recovery stopped.'}
        if($item.existed){if((DesktopHash $backup) -cne $item.beforeHash){throw 'Recovery backup integrity failed.'};DesktopCopy $backup $target}else{Remove-Item -LiteralPath $target -Force}
    }
    foreach($metadata in @('current.json','install-record.json')){
        $target=DesktopSafePath $AppRoot $metadata
        $previous=if($metadata -eq 'current.json'){$journal.pointerBefore}else{$journal.recordBefore}
        if(Test-Path -LiteralPath $target){
            $current=Get-Content -LiteralPath $target -Raw -Encoding UTF8
            if($current -ceq $previous){continue}
            $parsed=$current|ConvertFrom-Json
            if($metadata -eq 'current.json' -and $parsed.version -cne $journal.version){throw 'Recovery found an externally edited release pointer.'}
            if($metadata -eq 'install-record.json' -and $parsed.version -cne $journal.version){throw 'Recovery found externally edited ownership records.'}
        }
        if($previous){DesktopText $target $previous ([Text.UTF8Encoding]::new($false))}elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force}
    }
    Remove-Item -LiteralPath $journalPath -Force
}
function InstallDesktopPayload($PackageRoot,$AppRoot,$DataRoot,[switch]$Acknowledge,[switch]$Fixture,[switch]$FailAfterControls,[switch]$FailAfterPointer) {
    if(-not $Acknowledge){throw 'Installation requires saved-work acknowledgement.'}
    $manifest=TestDesktopManifest $PackageRoot -Fixture:$Fixture
    DesktopOwner $AppRoot $DataRoot -Fixture:$Fixture
    $scope=DesktopScope $DataRoot -Fixture:$Fixture
    $mutex=[Threading.Mutex]::new($false,('Local\RouterStudioManagement-'+$scope));$held=$false
    try {
        try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'Router management is busy; retry after it finishes.'}
        DesktopPrivateDirectory $AppRoot;DesktopPrivateDirectory $DataRoot
        RepairDesktopUpgrade $AppRoot $DataRoot
        $release=DesktopSafePath $AppRoot ('releases/'+$manifest.version)
        if(Test-Path -LiteralPath $release){$old=TestDesktopManifest $release -Fixture:$Fixture;if((DesktopHash (Join-Path $release 'package-manifest.json')) -cne (DesktopHash (Join-Path $PackageRoot 'package-manifest.json'))){throw 'An immutable release version already exists with different contents.'}}
        else {
            $staging=DesktopSafePath $AppRoot ('releases/.stage-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $staging -Force|Out-Null
            foreach($file in $manifest.files){$destination=DesktopSafePath $staging $file.path;New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $PackageRoot $file.path) -Destination $destination}
            Copy-Item -LiteralPath (Join-Path $PackageRoot 'package-manifest.json') -Destination $staging
            [void](TestDesktopManifest $staging -Fixture:$Fixture)
            Move-Item -LiteralPath $staging -Destination $release
        }
        $controlNames=@('router.mjs','codex-config.mjs','provider-switch.mjs','model-manager.mjs','route-policy.mjs','probe-engine.mjs','probe-cli.mjs','probe-sse.mjs','run-router.ps1','Studio-Worker.ps1','Studio-Protocol.ps1','Setup.ps1')
        $transaction='upgrade/'+[guid]::NewGuid().ToString('N');New-Item -ItemType Directory -Path (Join-Path $AppRoot $transaction) -Force|Out-Null
        $recordPath=DesktopSafePath $AppRoot 'install-record.json';$original=@{}
        if(Test-Path -LiteralPath $recordPath){foreach($item in (Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json).controls){$original[$item.name]=$item}}
        $controls=@()
        foreach($name in $controlNames+@('node-path.txt')){
            $source=Join-Path $release $name;if($name -ne 'node-path.txt' -and -not(Test-Path -LiteralPath $source)){continue}
            $target=DesktopSafePath $DataRoot $name;$existed=Test-Path -LiteralPath $target;$beforeHash=if($existed){DesktopHash $target}else{''};$backup=$transaction+'/'+$name
            if($original.ContainsKey($name) -and $beforeHash -cne $original[$name].installedHash){throw 'An installed control file has external edits; upgrade refused.'}
            if($existed){Copy-Item -LiteralPath $target -Destination (Join-Path $AppRoot $backup)}
            if($name -eq 'node-path.txt'){$source=Join-Path $AppRoot ($transaction+'/new-node-path.txt');[IO.File]::WriteAllText($source,(Join-Path $release 'runtime/node/node.exe'),[Text.UTF8Encoding]::new($false))}
            $installedHash=DesktopHash $source
            $controls+=@{name=$name;existed=$existed;beforeHash=$beforeHash;backup=$backup;installedHash=$installedHash;source=$source}
            if(-not $original.ContainsKey($name)){$original[$name]=@{name=$name;existed=$existed;beforeHash=$beforeHash;backup=$backup;installedHash=$installedHash}}
            else {$original[$name].installedHash=$installedHash}
        }
        DesktopWrite (Join-Path $AppRoot 'owner.json') @{sid=(DesktopSid);schemaVersion=1}
        $pointerPath=Join-Path $AppRoot 'current.json'
        # PS5 Get-Content attaches provider metadata to strings, which its JSON writer recursively serializes.
        $pointerBefore=if(Test-Path -LiteralPath $pointerPath){[IO.File]::ReadAllText($pointerPath,[Text.Encoding]::UTF8)}else{''}
        $recordBefore=if(Test-Path -LiteralPath $recordPath){[IO.File]::ReadAllText($recordPath,[Text.Encoding]::UTF8)}else{''}
        DesktopWrite (Join-Path $AppRoot 'upgrade.pending.json') @{schemaVersion=1;version=$manifest.version;controls=$controls;pointerBefore=$pointerBefore;recordBefore=$recordBefore}
        try {
            foreach($item in $controls){DesktopCopy $item.source (Join-Path $DataRoot $item.name)}
            if($FailAfterControls){throw 'Injected upgrade interruption'}
            DesktopWrite $recordPath @{schemaVersion=1;version=$manifest.version;controls=@($original.Values)}
            DesktopWrite (Join-Path $AppRoot 'current.json') @{schemaVersion=1;version=$manifest.version;dataRoot=$DataRoot}
            if($FailAfterPointer){throw 'Injected pointer interruption'}
            Remove-Item -LiteralPath (Join-Path $AppRoot 'upgrade.pending.json') -Force
        } catch {RepairDesktopUpgrade $AppRoot $DataRoot;throw}
    } finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function RemoveDesktopPayload($AppRoot,$DataRoot,[switch]$Fixture) {
    DesktopOwner $AppRoot $DataRoot -Fixture:$Fixture
    $scope=DesktopScope $DataRoot -Fixture:$Fixture
    $mutex=[Threading.Mutex]::new($false,('Local\RouterStudioManagement-'+$scope));$held=$false
    try{try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true};if(-not $held){throw 'Router management is busy; uninstall refused.'};RemoveDesktopPayloadCore $AppRoot $DataRoot -Fixture:$Fixture}finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function RemoveDesktopPayloadCore($AppRoot,$DataRoot,[switch]$Fixture) {
    DesktopOwner $AppRoot $DataRoot -Fixture:$Fixture
    RepairDesktopUpgrade $AppRoot $DataRoot
    $recordPath=DesktopSafePath $AppRoot 'install-record.json'
    if(Test-Path -LiteralPath $recordPath){
        $record=Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($item in $record.controls){
            $target=DesktopSafePath $DataRoot $item.name
            $current=if(Test-Path -LiteralPath $target){DesktopHash $target}else{''}
            if($current -ceq $item.beforeHash){
                # Already restored (including an interrupted/repeated uninstall).
                $item.installedHash=$item.beforeHash;DesktopWrite $recordPath $record;continue
            }
            if($current -cne $item.installedHash){continue}
            if($item.existed){$backup=DesktopSafePath $AppRoot $item.backup;if((DesktopHash $backup) -cne $item.beforeHash){throw 'Uninstall backup integrity failed.'};DesktopCopy $backup $target}else{Remove-Item -LiteralPath $target -Force}
            # Retain the original recovery preimage, but recognize the restored bytes on reinstall.
            $item.installedHash=$item.beforeHash;DesktopWrite $recordPath $record
        }
    }
    $pointer=DesktopSafePath $AppRoot 'current.json';if(Test-Path -LiteralPath $pointer){Remove-Item -LiteralPath $pointer -Force}
    Write-Output 'Desktop deactivated. Encrypted keys, router settings, history, and release recovery files were retained.'
}
function RemoveDesktopRecoveryFiles($AppRoot,$DataRoot,[switch]$Fixture){
    DesktopOwner $AppRoot $DataRoot -Fixture:$Fixture
    $mutex=[Threading.Mutex]::new($false,('Local\RouterStudioManagement-'+(DesktopScope $DataRoot -Fixture:$Fixture)));$held=$false
    try{
        try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'Router management is busy; file removal refused.'}
        if(Test-Path -LiteralPath (DesktopSafePath $AppRoot 'current.json')){throw 'Deactivate Desktop before removing recovery files.'}
        $releases=DesktopSafePath $AppRoot 'releases'
        if(-not(Test-Path -LiteralPath $releases)){return}
        foreach($directory in Get-ChildItem -LiteralPath $releases -Directory){
            if($directory.Name -notmatch '^\d+\.\d+\.\d+(?:-preview\.\d+)?$'){continue}
            $release=DesktopSafePath $AppRoot ('releases/'+$directory.Name)
            try{$manifest=TestDesktopManifest $release -Fixture:$Fixture}catch{Write-Output 'An edited or incomplete release was retained for manual review.';continue}
            foreach($file in $manifest.files){Remove-Item -LiteralPath (DesktopSafePath $release $file.path) -Force}
            Remove-Item -LiteralPath (DesktopSafePath $release 'package-manifest.json') -Force
            foreach($folder in Get-ChildItem -LiteralPath $release -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending){if(-not @(Get-ChildItem -LiteralPath $folder.FullName -Force).Count){Remove-Item -LiteralPath $folder.FullName}}
            if(-not @(Get-ChildItem -LiteralPath $release -Force).Count){Remove-Item -LiteralPath $release}
        }
        Write-Output 'Verified release application/runtime files removed. User data, external edits and control-file preimages retained.'
    }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
