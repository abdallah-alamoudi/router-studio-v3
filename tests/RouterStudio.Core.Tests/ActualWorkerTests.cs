using System.Diagnostics;
using System.Text;
using System.Text.Json;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class ActualWorkerTests
{
 private string root=null!;
 private WorkerBackend backend=null!;
 [TestInitialize] public async Task Setup()
 {
  root=Path.Combine(Path.GetTempPath(),"Actual bridge Ω "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  var project=Directory.GetCurrentDirectory();while(!File.Exists(Path.Combine(project,"src","worker","Studio-Worker.ps1")))project=Directory.GetParent(project)?.FullName??throw new InvalidOperationException("Project not found.");
  var pwsh=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe");
  var launch=new ProcessStartInfo(pwsh){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
  foreach(var arg in new[]{"-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(AppContext.BaseDirectory,"Fixtures","prepare-installation.ps1"),"-Destination",root,"-ProjectRoot",project})launch.ArgumentList.Add(arg);
  using var process=Process.Start(launch)!;var output=process.StandardOutput.ReadToEndAsync();var errors=process.StandardError.ReadToEndAsync();
  using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(20));
  try{await process.WaitForExitAsync(timeout.Token);}catch(OperationCanceledException){process.Kill(true);throw;}
  Assert.AreEqual(0,process.ExitCode,await errors);
  using var doc=JsonDocument.Parse(await output);var p=doc.RootElement;
  backend=new(new(){PowerShellPath=pwsh,WorkerPath=Path.Combine(project,"src","worker","Studio-Worker.ps1"),ProbeWorkerPath=Path.Combine(project,"src","worker","Studio-Worker.ps1"),JobsRoot=Path.Combine(root,"jobs"),FixturePaths=new(p.GetProperty("installRoot").GetString()!,p.GetProperty("configPath").GetString()!,new(p.GetProperty("healthUri").GetString()!))});
 }
 [TestCleanup] public void Cleanup(){if(Directory.Exists(root))Directory.Delete(root,true);}
 [TestMethod] public async Task ActualWorkerReturnsTypedSnapshotThroughBridge()
 {
  var snapshot=await backend.GetSnapshotAsync();
  Assert.AreEqual(64,snapshot.SnapshotDigest.Length);Assert.AreEqual("official",snapshot.Connection.Selected);
  Assert.AreEqual("deepseek-v4.1-flash",snapshot.Models.Single().Id);CollectionAssert.AreEqual(new[]{"medium"},snapshot.Models.Single().SupportedReasoningLevels);
  Assert.IsFalse(snapshot.Healthy);Assert.IsFalse(JsonSerializer.Serialize(snapshot).Contains("fake-plus-BRIDGE-key"));
 }
 [TestMethod] public async Task ActualWorkerKeyCommitSurvivesStartupFailureAndCiphertextIsRemoved()
 {
  using var secret=new SecretInput(Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-BRIDGE-canary-key"}"""));
  var result=await backend.ExecuteAsync(StudioRequest.Create("save-key",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"},ack=true}),secret);
  Assert.AreEqual("startup_failed",result.Error?.Code);var snapshot=await backend.GetSnapshotAsync();
  Assert.IsTrue(snapshot.RestartRequired);Assert.AreEqual("CHINESE",snapshot.Models.Single().Credential);
  Assert.IsFalse(JsonSerializer.Serialize(result).Contains("fake-BRIDGE-canary-key"));Assert.AreEqual(0,Directory.GetDirectories(Path.Combine(root,"jobs")).Length);
 }
 [TestMethod] public async Task ActualWorkerDistinguishesExplicitRouteFromDefaultFallback() {
  Assert.IsFalse((await backend.GetSnapshotAsync()).Models.Single().HasExplicitRoute);
  await File.WriteAllTextAsync(Path.Combine(root,"installation","router-config.json"),"""{"defaultKeyEnv":"SAFE_8STOKEN_PLUS","aliases":{},"modelRoutes":{"deepseek-v4.1-flash":"SAFE_8STOKEN_PLUS"}}""");
  var snapshot=await backend.GetSnapshotAsync();
  Assert.IsTrue(snapshot.Models.Single().HasExplicitRoute);
  Assert.AreEqual(1,DashboardComposer.Compose(snapshot).RouteCount);
 }
 [TestMethod] public async Task PreviewDoesNotWriteAndStaleConfigRefusesKeyApply() {
  var configPath=Path.Combine(root,"config.toml");var before=await File.ReadAllTextAsync(configPath);
  var preview=await backend.ExecuteAsync(StudioRequest.Create("preview-routes",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"}}));
  Assert.IsTrue(preview.Ok,preview.Error?.Code);Assert.AreEqual(before,await File.ReadAllTextAsync(configPath));
  string digest=preview.Data!.Value.GetProperty("previewDigest").GetString()!;
  await File.AppendAllTextAsync(configPath,"\n# external user edit\n");
  using var secret=new SecretInput(Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-PREVIEW-canary"}"""));
  var result=await backend.ExecuteAsync(StudioRequest.Create("save-key",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"},ack=true,expectedPreviewDigest=digest}),secret);
  Assert.AreEqual("config_changed",result.Error?.Code);Assert.AreEqual(before+"\n# external user edit\n",await File.ReadAllTextAsync(configPath));
  Assert.AreEqual("PLUS",(await backend.GetSnapshotAsync()).Models.Single().Credential);
 }
 [TestMethod] public async Task PreviewApplyRequiresAcknowledgementAndRestoreKeepsKeysAndCatalog() {
  var preview=await backend.ExecuteAsync(StudioRequest.Create("preview-routes",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"}}));Assert.IsTrue(preview.Ok);
  var digest=preview.Data!.Value.GetProperty("previewDigest").GetString();
  using var secret=new SecretInput(Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-ROUNDTRIP-canary"}"""));
  var denied=await backend.ExecuteAsync(StudioRequest.Create("save-key",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"},ack=false,expectedPreviewDigest=digest}),secret);
  Assert.AreEqual("acknowledgement_required",denied.Error?.Code);
  var saved=await backend.ExecuteAsync(StudioRequest.Create("save-key",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"},ack=true,expectedPreviewDigest=digest}),secret);
  Assert.AreEqual("startup_failed",saved.Error?.Code); // Fixture deliberately has no running router; committed save survives.
  var snapshot=await backend.GetSnapshotAsync();Assert.AreEqual("CHINESE",snapshot.Models.Single().Credential);
  var keyFile=Path.Combine(root,"installation","secrets.xml");var catalogFile=Path.Combine(root,"installation","codex-router-catalog.json");
  var keyBytes=await File.ReadAllBytesAsync(keyFile);var catalogBytes=await File.ReadAllBytesAsync(catalogFile);
  var backup=await backend.ExecuteAsync(StudioRequest.Create("preview-backup",new{id=snapshot.Backups.First().Id}));Assert.IsTrue(backup.Ok,backup.Error?.Code);
  var restored=await backend.ExecuteAsync(StudioRequest.Create("restore",new{id=snapshot.Backups.First().Id,ack=true,expectedPreviewDigest=backup.Data!.Value.GetProperty("previewDigest").GetString()}));
  Assert.IsTrue(restored.Ok,restored.Error?.Code);CollectionAssert.AreEqual(keyBytes,await File.ReadAllBytesAsync(keyFile));CollectionAssert.AreEqual(catalogBytes,await File.ReadAllBytesAsync(catalogFile));
  Assert.AreEqual("CHINESE",(await backend.GetSnapshotAsync()).Models.Single().Credential);Assert.IsFalse(JsonSerializer.Serialize(restored).Contains("fake-ROUNDTRIP-canary"));
 }
 [TestMethod] public async Task GenerationPreviewShowsResolvedRouteAndRunSanitizesResult() {
  await File.WriteAllTextAsync(Path.Combine(root,"installation","probe-cli.mjs"),"""
import {planProbe} from './route-policy.mjs';let text='';for await(const chunk of process.stdin)text+=chunk;const value=JSON.parse(text);
if(process.argv.includes('--plan')||process.argv.includes('--preview'))process.stdout.write(JSON.stringify({schemaVersion:1,ok:true,data:planProbe(value.config,value.catalog,value.request,value.snapshotDigest,{preview:process.argv.includes('--preview')})}));
else process.stdout.write(JSON.stringify({schemaVersion:1,ok:true,data:{outcome:'passed',httpStatus:200,firstEventMs:1,body:'fake-canary-body',credentialLabel:'WRONG'}}));
""");
  var snapshot=await backend.GetSnapshotAsync();var request=new ProbeRequest(ProbeKind.Stream,"deepseek-v4.1-flash",ExpectedSnapshotDigest:snapshot.SnapshotDigest);
  var preview=await backend.ExecuteAsync(StudioRequest.Create("preview-probe",request));Assert.IsTrue(preview.Ok,preview.Error?.Code);
  Assert.AreEqual("deepseek-v4.1-flash",preview.Data!.Value.GetProperty("resolvedModel").GetString());Assert.AreEqual("PLUS",preview.Data.Value.GetProperty("credentialLabel").GetString());Assert.IsFalse(preview.Data.Value.TryGetProperty("keyEnv",out _));
  var result=await backend.ExecuteAsync(StudioRequest.Create("probe",request with {Acknowledgement=true}));Assert.IsTrue(result.Ok,result.Error?.Code);
  Assert.AreEqual("passed",result.Data!.Value.GetProperty("outcome").GetString());Assert.AreEqual("PLUS",result.Data.Value.GetProperty("credentialLabel").GetString());Assert.AreEqual(1,result.Data.Value.GetProperty("firstEventMs").GetDouble());Assert.IsFalse(result.Data.Value.TryGetProperty("body",out _));
 }
 [TestMethod] public async Task LocalAndOfficialChecksAreTruthfulAndDoNotWriteState() {
  var paths=new[]{Path.Combine(root,"config.toml"),Path.Combine(root,"installation","provider-state.json"),Path.Combine(root,"installation","router-config.json"),Path.Combine(root,"installation","codex-router-catalog.json"),Path.Combine(root,"installation","secrets.xml")};
  var before=paths.Select(File.ReadAllBytes).ToArray();
  var local=await backend.ExecuteAsync(StudioRequest.Create("probe",new ProbeRequest(ProbeKind.Local)));Assert.IsTrue(local.Ok,local.Error?.Code);
  Assert.AreEqual("failed",local.Data!.Value.GetProperty("outcome").GetString()); // Isolated fixture has no health listener.
  var official=await backend.ExecuteAsync(StudioRequest.Create("probe",new{kind="official_config"}));Assert.IsTrue(official.Ok,official.Error?.Code);
  Assert.AreEqual("not_verified",official.Data!.Value.GetProperty("outcome").GetString());
  for(int i=0;i<paths.Length;i++)CollectionAssert.AreEqual(before[i],File.ReadAllBytes(paths[i]));
 }
 [TestMethod] public async Task ProbeRefusesPendingRecoveryWithoutChangingFiles() {
  var pending=Path.Combine(root,"installation","studio-key.pending.json");await File.WriteAllTextAsync(pending,"{\"version\":1}");
  var before=File.ReadAllBytes(Path.Combine(root,"installation","router-config.json"));
  var result=await backend.ExecuteAsync(StudioRequest.Create("probe",new{kind="local"}));
  Assert.AreEqual("recovery_required",result.Error?.Code);Assert.IsTrue(File.Exists(pending));CollectionAssert.AreEqual(before,File.ReadAllBytes(Path.Combine(root,"installation","router-config.json")));
 }
 [TestMethod] public async Task CatalogProbeSelectsOnlyRequestedKeyAndDropsChildErrorText() {
  var cli=Path.Combine(root,"installation","probe-cli.mjs");
  await File.WriteAllTextAsync(cli,"""
import fs from 'node:fs';import {planProbe} from './route-policy.mjs';
let input='';for await(const chunk of process.stdin)input+=chunk;const value=JSON.parse(input);
if(process.argv.includes('--plan'))process.stdout.write(JSON.stringify({schemaVersion:1,ok:true,data:planProbe(value.config,value.catalog,value.request,value.snapshotDigest)}));
else{
 const flags={selected:process.env.ROUTER_STUDIO_PROBE_KEY==='fake-plus-BRIDGE-key',onlySelected:Object.keys(process.env).filter(k=>k.startsWith('SAFE_8STOKEN_')).length===0,inputSafe:!input.includes('fake-plus-BRIDGE-key')};
 fs.writeFileSync(new URL('./probe-env-flags.json',import.meta.url),JSON.stringify(flags));console.error('fake-plus-BRIDGE-key');
 process.stdout.write(JSON.stringify({schemaVersion:1,ok:true,data:{kind:'catalog',credentialLabel:value.credentialLabel,endpointName:'8stoken',outcome:'passed',httpStatus:200,elapsedMs:1,completedAtUtc:new Date().toISOString(),snapshotDigest:value.snapshotDigest,unsafe:'fake-plus-BRIDGE-key'}}));
}
""");
  var before=(await backend.GetSnapshotAsync()).SnapshotDigest;
  var denied=await backend.ExecuteAsync(StudioRequest.Create("probe",new{kind="catalog",credentialLabel="PLUS",acknowledgement=false}));Assert.AreEqual("acknowledgement_required",denied.Error?.Code);
  var previous=Environment.GetEnvironmentVariable("SAFE_8STOKEN_PRO");Environment.SetEnvironmentVariable("SAFE_8STOKEN_PRO","fake-other-PARENT-key");
  StudioResult result;try{result=await backend.ExecuteAsync(StudioRequest.Create("probe",new{kind="catalog",credentialLabel="PLUS",acknowledgement=true,expectedSnapshotDigest=before}));}finally{Environment.SetEnvironmentVariable("SAFE_8STOKEN_PRO",previous);}
  Assert.IsTrue(result.Ok,result.Error?.Code);Assert.AreEqual("passed",result.Data!.Value.GetProperty("outcome").GetString());
  Assert.IsFalse(JsonSerializer.Serialize(result).Contains("fake-plus-BRIDGE-key"));Assert.IsFalse(result.Data.Value.TryGetProperty("unsafe",out _));
  using var flags=JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(root,"installation","probe-env-flags.json")));
  foreach(var property in flags.RootElement.EnumerateObject())Assert.IsTrue(property.Value.GetBoolean(),property.Name);
  Assert.AreEqual(before,(await backend.GetSnapshotAsync()).SnapshotDigest);
 }
}
