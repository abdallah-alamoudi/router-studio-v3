param([ValidateSet('Install','Upgrade','Status','Stop','Restore')][string]$Action = 'Install',[string]$CredentialFile,
    [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Safe8stokenRouter'),
    [string]$ConfigPath=(Join-Path $env:USERPROFILE '.codex\config.toml'),
    [uri]$HealthUri='http://127.0.0.1:18761/__router/health')
$ErrorActionPreference = 'Stop'
$installRoot=[IO.Path]::GetFullPath($InstallRoot)
$codexConfig=[IO.Path]::GetFullPath($ConfigPath)
. (Join-Path $PSScriptRoot 'Studio-Protocol.ps1')
$routerSourceRoot=if(Test-Path (Join-Path $PSScriptRoot 'router.mjs')){$PSScriptRoot}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'router'}
$workerSourceRoot=$PSScriptRoot
$testMode=$PSBoundParameters.ContainsKey('InstallRoot') -or $PSBoundParameters.ContainsKey('ConfigPath') -or $PSBoundParameters.ContainsKey('HealthUri')
$installCommitted = $false
$localChangesMade = $false
$startupBackup = $null
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Safe8stokenRouter.vbs'
function Utf8File($path, $text) { [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false))) }
function LocalToken {
    $stored = Import-Clixml (Join-Path $installRoot 'secrets.xml')
    return (New-Object System.Net.NetworkCredential('', $stored['SAFE_8STOKEN_LOCAL_TOKEN'])).Password
}
function StopRouter {
    $pidFile = Join-Path $installRoot 'router.pid'
    if (Test-Path $pidFile) {
        $routerPid = [int](Get-Content $pidFile -Raw -Encoding UTF8)
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $routerPid" -ErrorAction SilentlyContinue
        $expected = Join-Path $installRoot 'router.mjs'
        if ($process -and $process.Name -eq 'node.exe' -and $process.CommandLine.Contains($expected)) {
            Stop-Process -Id $routerPid -Force
        }
    }
}
try {
    if($HealthUri.Scheme -ne 'http' -or $HealthUri.Host -ne '127.0.0.1' -or $HealthUri.AbsolutePath -ne '/__router/health' -or $HealthUri.UserInfo -or $HealthUri.Query -or $HealthUri.Fragment){StopStudioAction 'invalid_request'}
    if($testMode -and $Action -notin @('Status','Upgrade')){StopStudioAction 'invalid_request'}
    if ($Action -eq 'Upgrade') {
        $node = (Get-Content (Join-Path $installRoot 'node-path.txt') -Raw -Encoding UTF8).Trim()
        if (-not (Test-Path (Join-Path $installRoot 'rollback.json'))) { throw 'No existing installation found. Use Install-Desktop.cmd.' }
        foreach ($file in @('provider-switch.mjs','model-manager.mjs','route-policy.mjs','custom-models.mjs','management.mjs','probe-engine.mjs','probe-cli.mjs','probe-sse.mjs')) { Copy-Item (Join-Path $routerSourceRoot $file) (Join-Path $installRoot $file) -Force }
        foreach ($file in @('run-router.ps1','Studio-Worker.ps1','Studio-Protocol.ps1','Setup.ps1')) { Copy-Item (Join-Path $workerSourceRoot $file) (Join-Path $installRoot $file) -Force }
        $nodeOutput=@(& $node (Join-Path $installRoot 'provider-switch.mjs') init $codexConfig $installRoot 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'Switcher initialization refused the current configuration. No Codex settings changed.' }
        Write-Host 'Provider menu added. Existing keys and proxy were retained. Use Router Studio Desktop to manage the installation.'
        exit 0
    }
    if ($Action -eq 'Stop') { StopRouter; Write-Host 'Router stopped. Codex must use direct settings until restarted.'; exit 0 }
    if ($Action -eq 'Status') {
        $token = LocalToken
        $health = Invoke-RestMethod -MaximumRedirection 0 -Uri $HealthUri -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 3
        Write-Host ('Router reachable: '+[bool]($health.ok -eq $true))
        Write-Host 'No upstream request was sent. Live model tests are still required.'
        exit 0
    }
    if ($Action -eq 'Restore') {
        $node = (Get-Content (Join-Path $installRoot 'node-path.txt') -Raw -Encoding UTF8).Trim()
        $nodeOutput=@(& $node (Join-Path $installRoot 'codex-config.mjs') restore $codexConfig $installRoot 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'Restore stopped: configuration has newer edits. Router remains running; see the backup file.' }
        StopRouter
        if (Test-Path $startupLink) { Remove-Item $startupLink }
        $state = Get-Content (Join-Path $installRoot 'windows-state.json') -Raw | ConvertFrom-Json
        [Environment]::SetEnvironmentVariable('SAFE_8STOKEN_LOCAL_TOKEN', $state.previousLocalToken, 'User')
        Remove-Item (Join-Path $installRoot 'rollback.json') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $installRoot 'rollback.json.tmp') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $installRoot 'provider-state.json') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $installRoot 'provider-state.json.pending') -ErrorAction SilentlyContinue
        Write-Host 'Direct connection restored. Close and reopen Codex yourself.'
        exit 0
    }
    if ($env:CODEX_HOME -and ([IO.Path]::GetFullPath($env:CODEX_HOME).TrimEnd('\') -ne (Join-Path $env:USERPROFILE '.codex').TrimEnd('\'))) { throw 'A different CODEX_HOME is set. This installer only manages the default .codex folder.' }
    if (Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue | Where-Object { try { $_.HasExited -ne $true -and $_.MainWindowHandle -ne 0 } catch { $false } }) { throw 'Save your work and close visible ChatGPT/Codex windows before installing. No app process was terminated.' }
    $privateNode=Join-Path $PSScriptRoot 'runtime/node/node.exe'
    $node = if(Test-Path -LiteralPath $privateNode){$privateNode}else{(Get-Command node.exe -ErrorAction Stop).Source}
    $version = & $node --version
    if ([int]($version.TrimStart('v').Split('.')[0]) -lt 22) { throw 'Node.js 22 or newer is required.' }
    if (-not (Test-Path $codexConfig)) { throw 'Codex config.toml was not found.' }
    if ((Test-Path (Join-Path $installRoot 'rollback.json')) -or (Test-Path (Join-Path $installRoot 'rollback.json.tmp'))) { throw 'Existing or incomplete installation. Use the desktop Backup/Restore action first.' }
    if (Get-NetTCPConnection -LocalPort 18761 -State Listen -ErrorAction SilentlyContinue) { throw 'Port 18761 is occupied. No settings were changed.' }
    Write-Host 'Router Studio v3 - one-time setup' -ForegroundColor Cyan
    Write-Host 'Enter group-specific keys from your 8stoken account. Keys are encrypted for this Windows user.'
    Write-Host 'Plus: Balanced and raw models. Pro: Heavy and Extreme. Full: Critical.'
    Write-Host 'Blank Pro/Full skips those presets. Group membership is determined by 8stoken, not by this script.'
    $provided=if($CredentialFile){Import-Clixml $CredentialFile}else{$null}
    $plus = if($provided){$provided.PLUS}else{Read-Host 'Plus/default API key (required)' -AsSecureString}
    if ($plus.Length -eq 0) { throw 'A default key is required.' }
    $pro = if($provided){$provided.PRO}else{Read-Host 'Pro API key (optional)' -AsSecureString}
    $full = if($provided){$provided.FULL}else{Read-Host 'Full-price API key (optional)' -AsSecureString}
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes); $rng.Dispose()
    $token = [Convert]::ToBase64String($bytes)
    $secrets = @{ SAFE_8STOKEN_LOCAL_TOKEN = (ConvertTo-SecureString $token -AsPlainText -Force); SAFE_8STOKEN_PLUS = $plus }
    $aliases = [ordered]@{
        '8s-balanced' = @{ model='gpt-6.1-sol'; effort='medium'; keyEnv='SAFE_8STOKEN_PLUS'; display='6.1 Sol - Balanced (Plus)' }
    }
    if ($pro.Length -gt 0) {
        $secrets['SAFE_8STOKEN_PRO'] = $pro
        $aliases['8s-heavy'] = @{ model='gpt-6.1-sol'; effort='xhigh'; keyEnv='SAFE_8STOKEN_PRO'; display='6.1 Sol - Heavy (Pro)' }
        # Extreme is added only if Astra is already present in your catalog with xhigh support.
    }
    if ($full.Length -gt 0) {
        $secrets['SAFE_8STOKEN_FULL'] = $full
        $aliases['8s-critical'] = @{ model='gpt-6.1-sol'; effort='xhigh'; keyEnv='SAFE_8STOKEN_FULL'; display='6.1 Sol - Critical (Full)' }
    }
    New-Item $installRoot -ItemType Directory -Force | Out-Null
    # Restrict this directory before writing encrypted keys and backups.
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($principal in @($sid, 'S-1-5-18')) {
        $identity = New-Object System.Security.Principal.SecurityIdentifier($principal)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $installRoot -AclObject $acl
    foreach ($file in @('router.mjs','codex-config.mjs','provider-switch.mjs','model-manager.mjs','route-policy.mjs','custom-models.mjs','management.mjs','probe-engine.mjs','probe-cli.mjs','probe-sse.mjs')) { Copy-Item (Join-Path $routerSourceRoot $file) (Join-Path $installRoot $file) -Force }
    foreach ($file in @('run-router.ps1','Studio-Worker.ps1','Studio-Protocol.ps1','Setup.ps1')) { Copy-Item (Join-Path $workerSourceRoot $file) (Join-Path $installRoot $file) -Force }
    Utf8File (Join-Path $installRoot 'node-path.txt') $node
    $secrets | Export-Clixml (Join-Path $installRoot 'secrets.xml')
    $configuration = @{ upstream='https://8stoken.com'; port=18761; localTokenEnv='SAFE_8STOKEN_LOCAL_TOKEN'; defaultKeyEnv='SAFE_8STOKEN_PLUS'; aliases=$aliases; maxRequestBytes=67108864; idleTimeoutMs=300000 }
    Utf8File (Join-Path $installRoot 'router-config.json') ($configuration | ConvertTo-Json -Depth 20)
    # Conservatively inspect the catalog before adding the optional Astra alias.
    $nodeOutput=@(& $node (Join-Path $installRoot 'codex-config.mjs') enable-extreme $codexConfig $installRoot 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not validate the existing model catalog. Codex config was left unchanged.' }
    $powershell = (Get-Process -Id $PID).Path
    Start-Process $powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installRoot 'run-router.ps1') + '"') | Out-Null
    $healthy = $false
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try { $h = Invoke-RestMethod -MaximumRedirection 0 -Uri $HealthUri -Headers @{ Authorization="Bearer $token" } -TimeoutSec 1; if ($h.ok) { $healthy=$true; break } } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $healthy) { StopRouter; throw 'Router did not start. Codex config was left unchanged. See router-error.log.' }
    $previous = [Environment]::GetEnvironmentVariable('SAFE_8STOKEN_LOCAL_TOKEN','User')
    Utf8File (Join-Path $installRoot 'windows-state.json') (@{previousLocalToken=$previous} | ConvertTo-Json)
    # Prepare local auth and startup before switching Codex; undo these on failure.
    if (Test-Path $startupLink) { $startupBackup = [IO.File]::ReadAllBytes($startupLink) }
    $localChangesMade = $true
    [Environment]::SetEnvironmentVariable('SAFE_8STOKEN_LOCAL_TOKEN',$token,'User')
    $runCommand = '"' + $powershell + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installRoot 'run-router.ps1') + '"'
    $vbs = 'CreateObject("WScript.Shell").Run "' + $runCommand.Replace('"','""') + '", 0, False'
    [IO.File]::WriteAllText($startupLink, $vbs, [Text.Encoding]::Unicode)
    $nodeOutput=@(& $node (Join-Path $installRoot 'codex-config.mjs') install $codexConfig $installRoot 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Catalog/config adaptation failed. Direct settings were left unchanged.' }
    $installCommitted = $true
    $nodeOutput=@(& $node (Join-Path $installRoot 'provider-switch.mjs') init $codexConfig $installRoot 2>&1)
    if ($LASTEXITCODE -ne 0) { Write-Host 'Router installed, but provider menu needs manual configuration. Use the desktop Backup/Restore action to roll back.' -ForegroundColor Yellow }
    Write-Host 'Use the desktop app to switch between official subscription access and 8stoken.'
    Write-Host 'Installed. Sign out of Windows and back in once so Codex inherits the local token.' -ForegroundColor Green
    Write-Host 'Then choose Balanced, Heavy, Critical or Extreme in the model menu. Available presets depend on the keys/catalog.'
    Write-Host 'For other raw models, the default key must have access to that model family.'
    Write-Host 'No Codex processes were terminated. No paid upstream tests were run.'
} catch {
    if ($Action -eq 'Install' -and -not $installCommitted -and $localChangesMade) {
        try {
            [Environment]::SetEnvironmentVariable('SAFE_8STOKEN_LOCAL_TOKEN',$previous,'User')
            if ($null -ne $startupBackup) { [IO.File]::WriteAllBytes($startupLink,$startupBackup) }
            elseif (Test-Path $startupLink) { Remove-Item $startupLink }
            StopRouter
        } catch { Write-Host 'Could not fully undo local startup settings. Use the desktop Backup/Restore action or inspect the backup.' -ForegroundColor Red }
    }
    $safe=GetStudioError $(if($_.Exception.Data['StudioCode']){$_.Exception.Data['StudioCode']}else{'installation_failed'})
    Write-Host ('Setup stopped: '+$safe.message) -ForegroundColor Red
    exit 1
}
