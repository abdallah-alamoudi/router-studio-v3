param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Desktop-Package.ps1')){Join-Path $PSScriptRoot 'Desktop-Package.ps1'}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'packaging/Desktop-Package.ps1'})
$PackageRoot=[IO.Path]::GetFullPath($PackageRoot);[void](TestDesktopManifest $PackageRoot)
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if([IO.Path]::GetExtension($OutputPath) -ine '.wsb'){throw 'Choose a .wsb output file.'}
if(Test-Path -LiteralPath $OutputPath){throw 'Existing configuration will not be overwritten.'}
if($OutputPath.StartsWith($PackageRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Keep the configuration outside the immutable package.'}
$escaped=[Security.SecurityElement]::Escape($PackageRoot)
# Map only a manifest-verified release, read-only. Installation is manual in the guest.
$xml=@"
<Configuration>
  <Networking>Disable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MappedFolders><MappedFolder>
    <HostFolder>$escaped</HostFolder>
    <SandboxFolder>C:\RouterStudioPackage</SandboxFolder>
    <ReadOnly>true</ReadOnly>
  </MappedFolder></MappedFolders>
</Configuration>
"@
[void][xml]$xml
[IO.File]::WriteAllText($OutputPath,$xml,[Text.UTF8Encoding]::new($false))
Write-Output 'Created offline, read-only Sandbox configuration. No Sandbox was started. Follow RELEASE-ACCEPTANCE.md; Sandbox does not establish standard-user or Windows 10 acceptance.'
