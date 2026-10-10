param(
 [Parameter(Mandatory=$true)][ValidateSet('Prepare','Verify')][string]$Action,
 [Parameter(Mandatory=$true)][string]$FixtureRoot,
 [string]$ExpectedSha256
)
# Synthetic DPAPI fixture only. Never open the application's encrypted key store.
$ErrorActionPreference='Stop'
try{
 Add-Type -AssemblyName System.Security
 $FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
 $cipherPath=Join-Path $FixtureRoot 'synthetic.dpapi';$metadataPath=Join-Path $FixtureRoot 'owner.json'
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($Action -eq 'Prepare'){
  if(Test-Path -LiteralPath $FixtureRoot){throw 'Choose a new fixture folder; existing files will not be overwritten.'}
  New-Item -ItemType Directory -Path $FixtureRoot|Out-Null
  $plain=New-Object byte[] 32;$random=[Security.Cryptography.RandomNumberGenerator]::Create()
  try{$random.GetBytes($plain)}finally{$random.Dispose()}
  $cipher=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $roundTrip=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  if([Convert]::ToBase64String($roundTrip) -cne [Convert]::ToBase64String($plain)){throw 'Owner round-trip failed.'}
  [Array]::Clear($plain,0,$plain.Length);[Array]::Clear($roundTrip,0,$roundTrip.Length)
  [IO.File]::WriteAllBytes($cipherPath,$cipher)
  $hash=(Get-FileHash -LiteralPath $cipherPath -Algorithm SHA256).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText($metadataPath,(@{schemaVersion=1;ownerSid=$sid;sha256=$hash}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  Write-Output ('PREPARED: synthetic fixture; owner round-trip passed. ExpectedSha256='+$hash)
  exit 0
 }
 if($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Provide the SHA256 printed during Prepare, kept separately from the copied fixture.'}
 $metadata=Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($metadata.schemaVersion -ne 1 -or $metadata.ownerSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'Invalid synthetic fixture metadata.'}
 if((Get-FileHash -LiteralPath $cipherPath -Algorithm SHA256).Hash -ine $ExpectedSha256 -or $metadata.sha256 -ine $ExpectedSha256){throw 'Synthetic fixture integrity check failed.'}
 if($sid -ceq $metadata.ownerSid){Write-Output 'BLOCKED: Verify must run under a different Windows account.';exit 3}
 # Read/permission/format errors are setup failures, not proof of DPAPI isolation.
 $cipher=[IO.File]::ReadAllBytes($cipherPath)
 try{
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  [Array]::Clear($plain,0,$plain.Length)
  Write-Output 'FAIL: another account decrypted the synthetic fixture.';exit 1
 }catch{
  $exception=$_.Exception
  while($null -ne $exception.InnerException){$exception=$exception.InnerException}
  if($exception -is [Security.Cryptography.CryptographicException]){Write-Output 'PASS: different Windows account could read but could not decrypt the intact synthetic fixture.';exit 0}
  throw
 }
}catch{Write-Output ('BLOCKED: synthetic verification setup failed: '+$_.Exception.Message);exit 3}
