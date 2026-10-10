import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runProcess} from './helpers/run-process.mjs';

const project=fileURLToPath(new URL('../',import.meta.url));
const pwsh=process.platform==='win32'?'pwsh.exe':'pwsh';
const available=spawnSync(pwsh,['-NoProfile','-Command','$PSVersionTable.PSVersion.Major'],{encoding:'utf8'});
const skipPwsh=available.status!==0||Number(available.stdout.trim())<7;
const skipWindows=skipPwsh||process.platform!=='win32';
function workspace(t){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'studio verification Ω '));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  fs.mkdirSync(path.join(root,'tools','verification'),{recursive:true});fs.mkdirSync(path.join(root,'tests'));fs.mkdirSync(path.join(root,'src','RouterStudio.Desktop'),{recursive:true});
  fs.writeFileSync(path.join(root,'tools','verification','fixture.ps1'),'# valid fixture');
  fs.writeFileSync(path.join(root,'src','RouterStudio.Desktop','MainWindow.xaml'),'<Window xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Button x:Name="Run"/></Window>');
  fs.writeFileSync(path.join(root,'tests','fixture.test.mjs'),`import {test} from 'node:test';import assert from 'node:assert/strict';test('fixture',()=>assert.equal(1,1));`);
  return root;
}
function verify(root,...args){
  const env={...process.env};delete env.NODE_TEST_CONTEXT;
  return runProcess(pwsh,['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(project,'tools','verification','Verify-Desktop.ps1'),'-ProjectRoot',root,'-Node',process.execPath,...args],{env});
}
function output(r){return `${r.stdout||''}\n${r.stderr||''}`;}
test('source preview launcher uses the pinned SDK from cache or PATH',()=>{
  const launcher=fs.readFileSync(path.join(project,'tools','installation','Start-Desktop-Preview.ps1'),'utf8');
  assert.match(launcher,/\.tools\/dotnet\/dotnet\.exe/);
  assert.match(launcher,/Get-Command dotnet/);
  assert.match(launcher,/global\.json/);
  assert.match(launcher,/--version/);
});test('source installer entrypoint explains the release-package requirement',()=>{
  const command=fs.readFileSync(path.join(project,'Install-Desktop.cmd'),'utf8');
  assert.match(command,/set "INSTALLER=%~dp0scripts\\Install-Desktop\.ps1"/i);
  assert.match(command,/if not exist "%INSTALLER%"/i);
  assert.match(command,/docs\\DESKTOP-PREVIEW\.md/i);
  assert.match(command,/exit \/b 2/i);
  const publisher=fs.readFileSync(path.join(project,'tools','packaging','Publish-Desktop.ps1'),'utf8');
  assert.match(publisher,/Install-Desktop\.ps1/);
  assert.match(publisher,/Join-Path \$output 'scripts'/);
});test('GitHub start guide describes source-only setup without ignored local artifacts',()=>{
  const guide=fs.readFileSync(path.join(project,'START-HERE.txt'),'utf8');
  assert.match(guide,/source-only|source project/i);
  assert.match(guide,/README\.md/i);
  assert.match(guide,/no downloadable binary release|no public binary release/i);
  assert.doesNotMatch(guide,/artifacts[\\/]desktop|preview\.8\.zip/i);
});const cases=[
 ['tools PowerShell syntax failure returns nonzero',root=>fs.writeFileSync(path.join(root,'tools','verification','broken.ps1'),'function Broken {'),1,/FAIL.*PowerShell/i],
 ['XAML DTDs are prohibited',root=>fs.writeFileSync(path.join(root,'src','RouterStudio.Desktop','MainWindow.xaml'),'<!DOCTYPE Window [<!ENTITY secret SYSTEM "file:///does-not-exist">]><Window Name="Run">&secret;</Window>'),1,/FAIL.*XAML/i],
 ['missing WPF XAML returns nonzero',root=>fs.unlinkSync(path.join(root,'src','RouterStudio.Desktop','MainWindow.xaml')),1,/FAIL.*XAML/i],
 ['control names can repeat across separate WPF files',root=>fs.writeFileSync(path.join(root,'src','RouterStudio.Desktop','Other.xaml'),'<UserControl><Button Name="Run"/></UserControl>'),0,/PASS.*XAML/i],
 ['valid fixture succeeds without integration',()=>{},0,/SKIP.*integration/i],
 ['failed Node test returns nonzero',root=>fs.writeFileSync(path.join(root,'tests','fixture.test.mjs'),`import {test} from 'node:test';test('fails',()=>{throw Error('intentional regression');});`),1,/FAIL.*Node/i],
 ['nested PowerShell syntax failure returns nonzero',root=>{fs.mkdirSync(path.join(root,'tests','nested'));fs.writeFileSync(path.join(root,'tests','nested','broken.ps1'),'function Broken {');},1,/FAIL.*PowerShell/i],
 ['malformed WPF XAML returns nonzero',root=>fs.writeFileSync(path.join(root,'src','RouterStudio.Desktop','MainWindow.xaml'),'<Window><Button></Window>'),1,/FAIL.*XAML/i],
 ['duplicate XAML control names return nonzero',root=>fs.writeFileSync(path.join(root,'src','RouterStudio.Desktop','MainWindow.xaml'),'<Window xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Button x:Name="Run"/><Button x:Name="Run"/></Window>'),1,/FAIL.*XAML/i],
];
for(const [name,prepare,status,pattern] of cases)test(name,{skip:skipPwsh},async t=>{
  const root=workspace(t);prepare(root);const r=await verify(root,'-SkipIntegration');
  assert.equal(r.status,status,output(r));assert.match(output(r),pattern);
  assert.doesNotMatch(output(r),/cannot be loaded|not digitally signed|not recognized/i);
});
test('required integration cannot be silently skipped',{skip:skipPwsh},async t=>{
  const r=await verify(workspace(t),'-SkipIntegration','-RequireIntegration');
  assert.equal(r.status,1,output(r));assert.match(output(r),/FAIL.*integration/i);
});
async function worker(...args){
  const base=fs.mkdtempSync(path.join(os.tmpdir(),'studio worker sandbox Ω '));
  try{
    const env={...process.env,TEMP:base,TMP:base};delete env.NODE_TEST_CONTEXT;
    return await runProcess(pwsh,['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(project,'tests','worker-integration.ps1'),'-Node',process.execPath,...args],{env});
  }finally{fs.rmSync(base,{recursive:true,force:true});}
}

test('occupied integration port is skipped without disturbing listener',{skip:skipWindows},async t=>{
  const sentinel=http.createServer((q,s)=>s.end('unrelated listener'));
  await new Promise((resolve,reject)=>{sentinel.once('error',reject);sentinel.listen(0,'127.0.0.1',resolve);});
  t.after(()=>new Promise(resolve=>sentinel.close(resolve)));
  const port=sentinel.address().port;
  const r=await worker('-HealthPort',String(port));
  assert.equal(r.status,0,output(r));assert.match(output(r),/SKIP.*occupied/i);
  assert.equal(await (await fetch(`http://127.0.0.1:${port}`)).text(),'unrelated listener');
});
test('isolated worker completes all 13 assertions with fake keys',{skip:skipWindows},async()=>{
  const r=await worker('-HealthPort','0');
  assert.equal(r.status,0,output(r));assert.equal((r.stdout.match(/^PASS:/gm)||[]).length,13,output(r));
  assert.match(r.stdout,/INTEGRATION: PASS/);assert.doesNotMatch(output(r),/fake-chinese-private-key|fake-plus-key|fake-local-token/);
});
test('fixed-port skip is never summarized as a worker pass',{skip:skipWindows},async t=>{
  const root=workspace(t);
  fs.writeFileSync(path.join(root,'tests','worker-integration.ps1'),"Write-Output 'INTEGRATION: SKIP - health port 18761 is occupied; no existing listener was stopped.'\nexit 0\n");
  const r=await verify(root,'-FixedPortOnly');
  assert.equal(r.status,0,output(r));
  assert.match(output(r),/SKIP - Worker integration/);
  assert.doesNotMatch(output(r),/PASS - Worker integration/);
});

test('verification runs tests from the selected project directory',{skip:skipPwsh},async t=>{
  const root=workspace(t);
  fs.writeFileSync(path.join(root,'tests','cwd.test.mjs'),`import {test} from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';const canonical=p=>{const value=fs.realpathSync.native(p);return process.platform==='win32'?value.toLowerCase():value};test('project cwd',()=>assert.equal(canonical(process.cwd()),canonical(${JSON.stringify(root)})));`);
  const r=await verify(root,'-SkipIntegration');
  assert.equal(r.status,0,output(r));assert.match(output(r),/PASS - Node tests/);
});

test('timeout terminates the owned fixture process tree',{skip:skipWindows},async t=>{
  const root=workspace(t),ready=path.join(root,'timeout-ready.json');
  const fixture=path.join(project,'tests','health-fixture.mjs');
  const script=path.join(root,'hang.ps1');
  const quote=s=>"'"+s.replaceAll("'","''")+"'";
  fs.writeFileSync(script,`$p=Start-Process -FilePath ${quote(process.execPath)} -WindowStyle Hidden -ArgumentList ('"${fixture}" --port 0 --ready-file "${ready}"') -PassThru\nwhile($true){Start-Sleep -Milliseconds 100}\n`);
  try{
    const result=await runProcess(pwsh,['-NoProfile','-ExecutionPolicy','Bypass','-File',script],{timeoutMs:3000});
    assert.equal(result.timedOut,true,output(result));
    assert.ok(fs.existsSync(ready),'The fixture must actually start before testing cancellation.');
    const fixtureInfo=JSON.parse(fs.readFileSync(ready,'utf8'));
    await assert.rejects(fetch(`http://127.0.0.1:${fixtureInfo.port}/__router/health`,{headers:{authorization:'Bearer fake-local-token'},signal:AbortSignal.timeout(1000)}));
  }finally{
    // Clean the specifically created fixture after a RED run or denied tree termination.
    if(fs.existsSync(ready)){
      const info=JSON.parse(fs.readFileSync(ready,'utf8'));
      try{process.kill(info.pid);}catch(error){if(error.code!=='ESRCH')throw error;}
    }
  }
});

function dotnetWorkspace(t,code){
 const root=workspace(t);
 fs.mkdirSync(path.join(root,'src','RouterStudio.Core'),{recursive:true});
 fs.writeFileSync(path.join(root,'src','RouterStudio.Core','RouterStudio.Core.csproj'),'<Project/>');
 fs.writeFileSync(path.join(root,'RouterStudio.slnx'),'<Solution/>');
 const runner=path.join(root,'tools','verification','dotnet-fixture.ps1');
 fs.writeFileSync(runner,`param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)\n[IO.File]::WriteAllText((Join-Path (Get-Location) 'dotnet-called.txt'),($Arguments -join '|'))\nexit ${code}\n`);
 return {root,runner};
}
test('.NET tests are invoked from selected project and failure fails verification',{skip:skipPwsh},async t=>{
 const {root,runner}=dotnetWorkspace(t,1);
 const r=await verify(root,'-SkipIntegration','-DotNet',runner);
 assert.equal(r.status,1,output(r));assert.match(output(r),/FAIL.*\.NET/i);
 assert.match(fs.readFileSync(path.join(root,'dotnet-called.txt'),'utf8'),/^test\|.*RouterStudio\.slnx/);
});
test('.NET successful runner is reported as passed',{skip:skipPwsh},async t=>{
 const {root,runner}=dotnetWorkspace(t,0);const r=await verify(root,'-SkipIntegration','-DotNet',runner);
 assert.equal(r.status,0,output(r));assert.match(output(r),/PASS - \.NET core tests/);
 assert.ok(fs.existsSync(path.join(root,'dotnet-called.txt')));
});
test('.NET missing tool fails when the Core project exists',{skip:skipPwsh},async t=>{
 const {root}=dotnetWorkspace(t,0);const r=await verify(root,'-SkipIntegration','-DotNet',path.join(root,'missing.exe'));
 assert.equal(r.status,1,output(r));assert.match(output(r),/FAIL.*\.NET/i);
});


for (const status of [0,1]) test(`native acceptance ${status?'failure propagates':'success is reported'}`,{skip:skipWindows},async t=>{
 const root=workspace(t);
 fs.writeFileSync(path.join(root,'tests','worker-integration.ps1'),"Write-Output 'INTEGRATION: PASS'\nexit 0\n");
 fs.mkdirSync(path.join(root,'src','RouterStudio.Desktop'),{recursive:true});
 fs.writeFileSync(path.join(root,'src','RouterStudio.Desktop','RouterStudio.Desktop.csproj'),'<Project/>');
 fs.writeFileSync(path.join(root,'tests','desktop-acceptance.ps1'),`param([string]$ProjectRoot,[string]$DotNet,[switch]$NoBuild)\nif($NoBuild){Write-Output 'Build must not be bypassed';exit 19}\nWrite-Output 'Fixture native acceptance'\nexit ${status}\n`);
 const r=await verify(root);
 assert.equal(r.status,status,output(r));
 assert.match(output(r),status?/FAIL.*Native desktop acceptance/:/PASS.*Native desktop acceptance/);
});
