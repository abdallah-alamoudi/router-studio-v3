param([string]$ProjectRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$manifest=Get-Content -LiteralPath (Join-Path $ProjectRoot 'src/router/runtime-manifest.json') -Raw|ConvertFrom-Json
$cache=Join-Path $ProjectRoot '.tools/desktop-runtimes';New-Item -ItemType Directory -Path $cache -Force|Out-Null
foreach($name in @('node','powershell')){
    $runtime=$manifest.$name;$uri=[uri]$runtime.url
    if($uri.Scheme -ne 'https' -or $uri.Host -notin @('nodejs.org','github.com') -or $runtime.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Runtime provenance is invalid.'}
    $archive=Join-Path $cache ($name+'-'+$runtime.version+'.zip')
    if(-not(Test-Path -LiteralPath $archive)){Invoke-WebRequest -Uri $uri -OutFile ($archive+'.download');Move-Item -LiteralPath ($archive+'.download') -Destination $archive}
    if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $runtime.sha256){throw "Runtime archive integrity failed: $name"}
    $destination=Join-Path $cache ($name+'-'+$runtime.version)
    if(-not(Test-Path -LiteralPath $destination)){Expand-Archive -LiteralPath $archive -DestinationPath $destination}
    $binary=if($name -eq 'node'){Join-Path $destination ($runtime.archiveDirectory+'/node.exe')}else{Join-Path $destination 'pwsh.exe'}
    $signature=Get-AuthenticodeSignature -LiteralPath $binary
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike ('*'+$runtime.signer+'*')){throw "Runtime signature is invalid: $name"}
    Write-Output "Verified $name $($runtime.version) archive and executable signature."
}
