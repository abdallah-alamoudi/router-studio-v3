param(
    [string]$ProjectRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Node,
    [string]$DotNet,
    [switch]$SkipIntegration,
    [switch]$RequireIntegration,
    [switch]$FixedPortOnly
)
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    $script:checkSkipped=$false
    try{& $Action;$result=if($script:checkSkipped){'SKIP'}else{'PASS'};$results.Add([pscustomobject]@{Check=$Name;Result=$result});Write-Output "$result $Name"}
    catch{$results.Add([pscustomobject]@{Check=$Name;Result='FAIL'});Write-Output ("FAIL "+$Name+": "+$_.Exception.Message)}
}
Check 'Node tests' {
    if(-not $Node){$script:Node=(Get-Command node -ErrorAction Stop).Source}
    if(-not(Test-Path -LiteralPath $Node -PathType Leaf)){throw 'Node executable was not found.'}
    $version=& $Node --version
    if($LASTEXITCODE -ne 0 -or $version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 22){throw 'Node.js 22 or newer is required.'}
    $testFiles=@(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.test.mjs' -File | Sort-Object Name)
    if(-not $testFiles.Count){throw 'No Node test files were found.'}
    Push-Location -LiteralPath $ProjectRoot
    try{
        & $Node --test @($testFiles.FullName)
        if($LASTEXITCODE -ne 0){throw "Node tests exited with code $LASTEXITCODE."}
    }finally{Pop-Location}
}
if(Test-Path -LiteralPath (Join-Path $ProjectRoot 'src/RouterStudio.Core/RouterStudio.Core.csproj')){
    Check '.NET core tests' {
        if(-not $DotNet){
            $localDotNet=Join-Path $ProjectRoot '.tools/dotnet/dotnet.exe'
            $script:DotNet=if(Test-Path -LiteralPath $localDotNet){$localDotNet}else{(Get-Command dotnet -ErrorAction Stop).Source}
        }
        if(-not(Test-Path -LiteralPath $DotNet -PathType Leaf)){throw '.NET SDK executable was not found.'}
        $saved=@{}
        foreach($name in @('DOTNET_CLI_HOME','DOTNET_CLI_TELEMETRY_OPTOUT','DOTNET_SKIP_FIRST_TIME_EXPERIENCE','DOTNET_NOLOGO','TESTINGPLATFORM_TELEMETRY_OPTOUT')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
        Push-Location -LiteralPath $ProjectRoot
        try{
            $env:DOTNET_CLI_HOME=Join-Path $ProjectRoot '.tools/cli-home'
            $env:DOTNET_CLI_TELEMETRY_OPTOUT='1';$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1';$env:DOTNET_NOLOGO='1';$env:TESTINGPLATFORM_TELEMETRY_OPTOUT='1'
            & $DotNet test (Join-Path $ProjectRoot 'RouterStudio.slnx') -c Release '-p:RestoreLockedMode=true' --logger 'trx;LogFileName=core-tests.trx' --results-directory (Join-Path $ProjectRoot 'TestResults/Core')
            if($LASTEXITCODE -ne 0){throw '.NET core tests failed.'}
        }finally{
            Pop-Location
            foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
        }
    }
    if(-not $SkipIntegration -and $IsWindows){
        Check 'Current-user DPAPI envelopes' {
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'tests/dpapi-envelope.ps1') -ProjectRoot $ProjectRoot
            if($LASTEXITCODE -ne 0){throw 'Current-user DPAPI envelope checks failed.'}
        }
        Write-Output 'DPAPI coverage: current Windows user only; different-user acceptance is separate.'
    }
}
$nativePassed=$false
if(Test-Path -LiteralPath (Join-Path $ProjectRoot 'tests/installation-entrypoints.ps1')){Check 'Actual installer entry points with synthetic profile' {
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $ProjectRoot 'tests/installation-entrypoints.ps1') -ProjectRoot $ProjectRoot
    if($LASTEXITCODE -ne 0){throw 'Installer entry-point fixtures failed.'}
}}
if(Test-Path -LiteralPath (Join-Path $ProjectRoot 'tests/second-user-verifier.ps1')){Check 'Second-user acceptance helper rejects false positives' {
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $ProjectRoot 'tests/second-user-verifier.ps1') -ProjectRoot $ProjectRoot
    if($LASTEXITCODE -ne 0){throw 'Second-user verification helper regression failed.'}
}}
if(Test-Path -LiteralPath (Join-Path $ProjectRoot 'tests/migration.ps1')){
    Check 'Desktop migration fixtures' {
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $ProjectRoot 'tests/migration.ps1') -ProjectRoot $ProjectRoot
        if($LASTEXITCODE -ne 0){throw 'Desktop migration fixtures failed.'}
    }
}
if(Test-Path -LiteralPath (Join-Path $ProjectRoot 'src/RouterStudio.Desktop/RouterStudio.Desktop.csproj')){
    Check 'Native desktop acceptance' {
        if($SkipIntegration){$script:checkSkipped=$true;Write-Output 'SKIP native acceptance: requested.';return}
        if(-not $IsWindows){throw 'Native acceptance requires Windows and an interactive desktop.'}
        $native=Join-Path $ProjectRoot 'tests/desktop-acceptance.ps1'
        if(-not(Test-Path -LiteralPath $native)){throw 'Native acceptance script missing.'}
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$native,'-ProjectRoot',$ProjectRoot)
        if($DotNet){$arguments+=@('-DotNet',$DotNet)}
        & (Get-Process -Id $PID).Path @arguments
        if($LASTEXITCODE -ne 0){throw 'Native desktop acceptance failed.'}
        $script:nativePassed=$true
    }
}
Check 'PowerShell syntax' {
    $files=@(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ps1' -File)
    foreach($folder in @('src/worker','tests','tools')){
        $directory=Join-Path $ProjectRoot $folder
        if(Test-Path -LiteralPath $directory){$files+=@(Get-ChildItem -LiteralPath $directory -Filter '*.ps1' -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' })}
    }
    if(-not $files.Count){throw 'No PowerShell files were found.'}
    $errorCount=0
    foreach($file in $files){
        $tokens=$null;$parseErrors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        foreach($parseError in $parseErrors){$errorCount++;Write-Output ($file.Name+':'+$parseError.Extent.StartLineNumber+' '+$parseError.ErrorId)}
    }
    if($errorCount){throw "$errorCount parse error(s)."}
    Write-Output ("Parsed "+$files.Count+" PowerShell files.")
}
Check 'XAML XML and unique control names' {
    $desktopRoot=Join-Path $ProjectRoot 'src/RouterStudio.Desktop'
    $files=@(if(Test-Path -LiteralPath $desktopRoot){Get-ChildItem -LiteralPath $desktopRoot -Filter '*.xaml' -File -Recurse | Where-Object { $_.FullName -notmatch '[\/](bin|obj)[\/]' }})
    if(-not $files.Count){throw 'No WPF XAML files were found.'}
    $settings=[Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver=$null
    $totalNames=0
    foreach($file in $files){
        $reader=[Xml.XmlReader]::Create($file.FullName,$settings)
        $document=[Xml.XmlDocument]::new();$document.XmlResolver=$null
        try{$document.Load($reader)}finally{$reader.Dispose()}
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($element in $document.SelectNodes('//*')){
            foreach($attribute in $element.Attributes){
                if($attribute.LocalName -eq 'Name' -and $attribute.NamespaceURI -in @('','http://schemas.microsoft.com/winfx/2006/xaml')){
                    if($attribute.Value -and -not $names.Add($attribute.Value)){throw ("Duplicate XAML control name in "+$file.Name+": "+$attribute.Value)}
                }
            }
        }
        $totalNames+=$names.Count
    }
    if(-not $totalNames){throw 'No named WPF XAML controls were found.'}
    Write-Output ("Validated "+$files.Count+" WPF XAML files and "+$totalNames+" control names; native rendering is checked separately.")
}
$integrationPassed=$false
if($SkipIntegration){
    $results.Add([pscustomobject]@{Check='Worker integration';Result='SKIP'})
    Write-Output 'SKIP Worker integration: requested.'
}elseif(-not $IsWindows){
    $results.Add([pscustomobject]@{Check='Worker integration';Result='SKIP'})
    Write-Output 'SKIP Worker integration: Windows required for this baseline.'
}else{
    Check 'Worker integration' {
        $worker=Join-Path $ProjectRoot 'tests/worker-integration.ps1'
        if(-not(Test-Path -LiteralPath $worker)){throw 'Worker integration script missing.'}
        $powershell=(Get-Process -Id $PID).Path
        $output=@(& $powershell -NoProfile -ExecutionPolicy Bypass -File $worker -Node $Node 2>&1)
        $code=$LASTEXITCODE
        $output | ForEach-Object {Write-Output $_}
        if($code -ne 0){throw "Worker integration exited with code $code."}
        if(($output -join "\n") -match 'INTEGRATION: SKIP'){
            $results.Add([pscustomobject]@{Check='Fixed-port worker integration';Result='SKIP'})
            if($FixedPortOnly){
                $script:checkSkipped=$true
                # Return a skip without claiming integration success.
                return
            }
            Write-Output 'RUN isolated worker integration on an OS-assigned health port.'
            $output=@(& $powershell -NoProfile -ExecutionPolicy Bypass -File $worker -Node $Node -HealthPort 0 2>&1)
            $code=$LASTEXITCODE
            $output | ForEach-Object {Write-Output $_}
        }
        if($code -ne 0 -or ($output -join "\n") -notmatch 'INTEGRATION: PASS'){
            throw 'Worker integration did not report a completed pass.'
        }
        $script:integrationPassed=$true
    }
}
if($RequireIntegration -and -not $integrationPassed){
    $results.Add([pscustomobject]@{Check='Required worker integration';Result='FAIL'})
    Write-Output 'FAIL Required worker integration: integration was skipped or failed.'
}
Write-Output ''
Write-Output 'Verification summary:'
$results | ForEach-Object {Write-Output ($_.Result+' - '+$_.Check)}
if(@($results|Where-Object Result -eq 'FAIL').Count){exit 1}
if(-not $integrationPassed){Write-Output 'Worker integration not verified.'}
else{Write-Output 'Automated worker baseline verified.'}
if($nativePassed){Write-Output 'Native WPF fixture verified; manual environment acceptance remains separate.'}
else{Write-Output 'Native UI checks were not run.'}
Write-Output 'No upstream generation was run.'
exit 0
