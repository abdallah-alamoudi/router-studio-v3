param([Parameter(Mandatory)][string]$Destination,[Parameter(Mandatory)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$root=Join-Path $Destination 'installation';$cp=Join-Path $Destination 'config.toml'
New-Item $root -ItemType Directory -Force|Out-Null
foreach($name in @('provider-switch.mjs','model-manager.mjs','route-policy.mjs','probe-engine.mjs','probe-cli.mjs','probe-sse.mjs')){Copy-Item (Join-Path $ProjectRoot ('src/router/'+$name)) $root}
$node=(Get-Command node).Source
$node|Set-Content (Join-Path $root 'node-path.txt')
@('model_provider = "safe_8stoken"','model = "deepseek-v4.1-flash"','','[model_providers.safe_8stoken]','base_url = "http://127.0.0.1:18761/v1"','env_key = "SAFE_8STOKEN_LOCAL_TOKEN"','wire_api = "responses"')|Set-Content $cp
& $node (Join-Path $root 'provider-switch.mjs') init $cp $root|Out-Null
if($LASTEXITCODE -ne 0){throw 'Fixture initialization failed.'}
& $node (Join-Path $root 'provider-switch.mjs') official $cp $root|Out-Null
if($LASTEXITCODE -ne 0){throw 'Fixture official switch failed.'}
@{defaultKeyEnv='SAFE_8STOKEN_PLUS';aliases=@{}}|ConvertTo-Json|Set-Content (Join-Path $root 'router-config.json')
@{models=@(@{slug='deepseek-v4.1-flash';supported_reasoning_levels=@(@{effort='medium'})})}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'codex-router-catalog.json')
@{SAFE_8STOKEN_LOCAL_TOKEN=(ConvertTo-SecureString 'fake-local-BRIDGE-token' -AsPlainText -Force);SAFE_8STOKEN_PLUS=(ConvertTo-SecureString 'fake-plus-BRIDGE-key' -AsPlainText -Force)}|Export-Clixml (Join-Path $root 'secrets.xml')
'exit 0'|Set-Content (Join-Path $root 'run-router.ps1')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
@{installRoot=$root;configPath=$cp;healthUri="http://127.0.0.1:$port/__router/health"}|ConvertTo-Json
