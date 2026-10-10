param()
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$localDotnet=Join-Path $root '.tools/dotnet/dotnet.exe'
if(Test-Path -LiteralPath $localDotnet){
    $dotnet=$localDotnet
}else{
    $dotnetCommand=Get-Command dotnet -ErrorAction SilentlyContinue
    if(-not $dotnetCommand){throw 'The pinned .NET SDK is unavailable. Install the SDK version in global.json or place it at .tools/dotnet/dotnet.exe. See docs/DESKTOP-PREVIEW.md.'}
    $dotnet=$dotnetCommand.Source
}
$sdkConfig=Get-Content -LiteralPath (Join-Path $root 'global.json') -Raw | ConvertFrom-Json
$requiredSdkVersion=[string]$sdkConfig.sdk.version
Push-Location $root
try{
    $resolvedSdkVersion=((& $dotnet --version 2>&1) | Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw "The selected .NET SDK could not resolve global.json: $resolvedSdkVersion"}
}finally{
    Pop-Location
}
if($resolvedSdkVersion -ne $requiredSdkVersion){throw "The preview requires .NET SDK $requiredSdkVersion from global.json; dotnet resolved $resolvedSdkVersion."}
$assembly=Join-Path $root 'src/RouterStudio.Desktop/bin/Release/net10.0-windows/RouterStudio.Desktop.dll'
if(-not(Test-Path -LiteralPath $assembly)){throw 'Build the desktop project with the pinned .NET SDK first. See docs/DESKTOP-PREVIEW.md.'}
$launch=[Diagnostics.ProcessStartInfo]::new($dotnet)
$launch.UseShellExecute=$false
$launch.CreateNoWindow=$true
$launch.WorkingDirectory=$root
foreach($argument in @($assembly,'--project-root',$root)){$launch.ArgumentList.Add($argument)}
$null=[Diagnostics.Process]::Start($launch)
