param([string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('Studio DPAPI gate '+[guid]::NewGuid().ToString('N'))
$scriptPath=Join-Path $ProjectRoot 'tools/verification/Test-SecondUserEncryption.ps1'
$ps=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
try{
 & $ps -NoProfile -File $scriptPath -Action Prepare -FixtureRoot $root
 if($LASTEXITCODE -ne 0){throw 'Prepare failed'}
 $metadataPath=Join-Path $root 'owner.json';$metadata=Get-Content -LiteralPath $metadataPath -Raw|ConvertFrom-Json
 & $ps -NoProfile -File $scriptPath -Action Verify -FixtureRoot $root -ExpectedSha256 $metadata.sha256
 if($LASTEXITCODE -ne 3){throw 'Same user incorrectly counted as cross-account acceptance'}
 Write-Output 'PASS same-account acceptance remains BLOCKED'
 $metadata.ownerSid='S-1-5-21-1-2-3-4';$metadata|ConvertTo-Json|Set-Content -LiteralPath $metadataPath -Encoding UTF8
 & $ps -NoProfile -File $scriptPath -Action Verify -FixtureRoot $root -ExpectedSha256 $metadata.sha256
 if($LASTEXITCODE -ne 1){throw 'Successful decryption incorrectly counted as isolation'}
 Write-Output 'PASS forged account metadata cannot turn successful decryption into PASS'
 [IO.File]::WriteAllBytes((Join-Path $root 'synthetic.dpapi'),[byte[]]@(1,2,3))
 & $ps -NoProfile -File $scriptPath -Action Verify -FixtureRoot $root -ExpectedSha256 $metadata.sha256
 if($LASTEXITCODE -ne 3){throw 'Tampering incorrectly counted as DPAPI refusal'}
 Write-Output 'PASS corrupted ciphertext remains BLOCKED; no second account was tested'
}finally{
 $resolved=[IO.Path]::GetFullPath($root);$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'Studio DPAPI gate *' -and (Test-Path -LiteralPath $resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
