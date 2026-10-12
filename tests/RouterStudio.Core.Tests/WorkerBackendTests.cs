using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class WorkerBackendTests
{
 private string root = null!;
 private WorkerBackend backend = null!;
 private WorkerBackendOptions options = null!;
 [TestInitialize] public void Setup()
 {
  root=Path.Combine(Path.GetTempPath(),"Router bridge Ω space "+Guid.NewGuid().ToString("N"));
  Directory.CreateDirectory(Path.Combine(root,"worker"));
  File.Copy(Path.Combine(AppContext.BaseDirectory,"Fixtures","bridge-worker.ps1"),Path.Combine(root,"worker","bridge-worker.ps1"));
  File.WriteAllText(Path.Combine(root,"mode.txt"),"normal");
  options=new() { PowerShellPath=Environment.GetEnvironmentVariable("ROUTER_TEST_PWSH") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe"), WorkerPath=Path.Combine(root,"worker","bridge-worker.ps1"), ProbeWorkerPath=Path.Combine(root,"worker","bridge-worker.ps1"), JobsRoot=Path.Combine(root,"jobs") };
  backend=new(options);
 }
 [TestCleanup] public void Cleanup()
 {
  foreach(var name in new[]{"child.pid","worker.pid"}) {
   var path=Path.Combine(root,name);
   var started=Path.Combine(root,Path.GetFileNameWithoutExtension(name)+".start.txt");
   if(File.Exists(path) && File.Exists(started) && int.TryParse(File.ReadAllText(path),out int pid) && long.TryParse(File.ReadAllText(started),out long ticks)){
    try {using var p=Process.GetProcessById(pid);if(!p.HasExited && p.StartTime.ToUniversalTime().Ticks==ticks)p.Kill(entireProcessTree:true);}
    catch(ArgumentException){}catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception){}
   }
  }
  if(Directory.Exists(root)) Directory.Delete(root,true);
 }
 private void Mode(string mode)=>File.WriteAllText(Path.Combine(root,"mode.txt"),mode);
 private async Task Ready(string name="ready.txt")
 {
  for(int i=0;i<200;i++){if(File.Exists(Path.Combine(root,name)))return;await Task.Delay(50);}
  Assert.Fail("Fixture did not reach the expected checkpoint.");
 }
 private void Release()=>File.WriteAllText(Path.Combine(root,"release.txt"),"release");
 private static bool Alive(int pid) {try {using var p=Process.GetProcessById(pid);return !p.HasExited;}catch(ArgumentException){return false;}}
 private void JobsEmpty()=>Assert.AreEqual(0,Directory.Exists(options.JobsRoot)?Directory.GetDirectories(options.JobsRoot).Length:0);
 [TestMethod] public async Task WrongSchemaRejected()
 {
  var result=await backend.ExecuteAsync(new(99,"status",JsonSerializer.SerializeToElement(new{})));
  Assert.AreEqual("unsupported_schema",result.Error?.Code); Assert.IsFalse(File.Exists(Path.Combine(root,"args.txt")));
 }
 [TestMethod] public async Task JobPathWithSpacesLaunches()
 { var r=await backend.ExecuteAsync(StudioRequest.Create("status"));Assert.IsTrue(r.Ok);Assert.AreEqual("final",r.Data?.GetProperty("marker").GetString());JobsEmpty(); }
 [TestMethod] public async Task ResultReadOnlyAfterWorkerExit()
 {
  Mode("early");var pending=backend.ExecuteAsync(StudioRequest.Create("status"));await Ready();
  Assert.IsFalse(pending.IsCompleted);Release();var r=await pending;Assert.AreEqual("final",r.Data?.GetProperty("marker").GetString());JobsEmpty();
 }
 [TestMethod] public async Task CorruptResultIsControlledError()
 {Mode("corrupt");var r=await backend.ExecuteAsync(StudioRequest.Create("status"));Assert.AreEqual("invalid_result",r.Error?.Code);JobsEmpty();}
 [TestMethod] public async Task ProbeCancellationKillsOnlyOwnedTree()
 {
  Mode("tree");using var sentinel=Process.Start(new ProcessStartInfo(options.PowerShellPath){ArgumentList={"-NoProfile","-Command","Start-Sleep -Seconds 20"},UseShellExecute=false,CreateNoWindow=true})!;
  try {
   using var cancel=new CancellationTokenSource();var pending=backend.ExecuteAsync(StudioRequest.Create("probe",new {kind="local"}),ct:cancel.Token);await Ready();
   int child=int.Parse(File.ReadAllText(Path.Combine(root,"child.pid")));cancel.Cancel();var r=await pending;
   Assert.AreEqual("cancelled",r.Error?.Code);for(int i=0;i<30 && Alive(child);i++) await Task.Delay(50);
   Assert.IsFalse(Alive(child));Assert.IsFalse(sentinel.HasExited);JobsEmpty();
  }finally{if(!sentinel.HasExited)sentinel.Kill(entireProcessTree:true);}
 }
 [TestMethod] public async Task MutationCancellationDoesNotKillCommit()
 {
  Mode("mutation");using var cancel=new CancellationTokenSource();var pending=backend.ExecuteAsync(StudioRequest.Create("repair"),ct:cancel.Token);await Ready();
  cancel.Cancel();await Task.Delay(100);Assert.IsFalse(pending.IsCompleted);Release();Assert.IsTrue((await pending).Ok);Assert.IsTrue(File.Exists(Path.Combine(root,"committed.txt")));JobsEmpty();
 }
 [TestMethod] public async Task SecretNeverInArguments()
 {
  Mode("secret");var bytes=Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-BRIDGE-canary-key"}""");using var secret=new SecretInput(bytes);Array.Clear(bytes);
  var r=await backend.ExecuteAsync(StudioRequest.Create("save-key",new {label="CHINESE",ids=new[]{"deepseek-v4.1-flash"},ack=true}),secret);
  Assert.IsTrue(r.Ok);Assert.IsTrue(File.Exists(Path.Combine(root,"secret-checked.txt")));
  foreach(var name in new[]{"args.txt","captured-request.json"})Assert.IsFalse(File.ReadAllText(Path.Combine(root,name)).Contains("fake-BRIDGE-canary-key"));
  Assert.IsFalse(JsonSerializer.Serialize(r).Contains("fake-BRIDGE-canary-key"));Assert.AreEqual("[protected input]",secret.ToString());JobsEmpty();
 }
 [TestMethod] public async Task WrongResultVersionRejected()
 {Mode("wrong-schema");Assert.AreEqual("unsupported_schema",(await backend.ExecuteAsync(StudioRequest.Create("status"))).Error?.Code);}
 [TestMethod] public async Task ErrorMessageIsMappedLocally()
 {Mode("bad-error");var r=await backend.ExecuteAsync(StudioRequest.Create("status"));Assert.AreEqual("startup_failed",r.Error?.Code);Assert.IsFalse(r.Error!.Message.Contains("canary"));}
 [TestMethod] public async Task MalformedShapeRejected()
 {Mode("bad-shape");Assert.AreEqual("invalid_result",(await backend.ExecuteAsync(StudioRequest.Create("status"))).Error?.Code);}
 [TestMethod] public async Task NonzeroExitDoesNotAcceptSuccessResult()
 {Mode("exit-error");Assert.AreEqual("worker_failed",(await backend.ExecuteAsync(StudioRequest.Create("status"))).Error?.Code);}
 [TestMethod] public async Task MissingAndOversizedResultsAreControlled()
 {foreach(var mode in new[]{"missing","oversized"}) {Mode(mode);Assert.AreEqual("invalid_result",(await backend.ExecuteAsync(StudioRequest.Create("status"))).Error?.Code);JobsEmpty();}}
 [TestMethod] public async Task ConflictingActionIsBusy()
 {
  Mode("early");var first=backend.ExecuteAsync(StudioRequest.Create("status"));await Ready();
  Assert.AreEqual("busy",(await backend.ExecuteAsync(StudioRequest.Create("repair"))).Error?.Code);Release();Assert.IsTrue((await first).Ok);
 }
 [TestMethod] public async Task InvalidPayloadNeverLaunches()
 {
  foreach(var request in new[]{StudioRequest.Create("bogus"),StudioRequest.Create("status",new{key="fake-BRIDGE-canary-key"}),StudioRequest.Create("restore",new{id="../config.toml",ack=true}),StudioRequest.Create("save-key",new{label="INVALID LABEL",ids=new[]{"x"},ack=true}),StudioRequest.Create("probe",new{kind="local",endpoint="https://bad.example"})}) {
   Assert.AreEqual("invalid_request",(await backend.ExecuteAsync(request)).Error?.Code);Assert.IsFalse(File.Exists(Path.Combine(root,"args.txt")));
  }
 }
 [TestMethod] public async Task CancelledBeforeLaunchLeavesNoJob()
 {using var cancel=new CancellationTokenSource();cancel.Cancel();Assert.AreEqual("cancelled",(await backend.ExecuteAsync(StudioRequest.Create("repair"),ct:cancel.Token)).Error?.Code);JobsEmpty();}
 [TestMethod] public async Task NullManagementCollectionsAreControlledErrors()
 {
  foreach(var mode in new[]{"null-credentials","null-custom-models"}) {
   Mode(mode);
   var error=await Assert.ThrowsExactlyAsync<StudioBackendException>(async()=>{await backend.GetSnapshotAsync();});
   Assert.AreEqual("invalid_result",error.Error.Code);
  }
  Mode("normal");Assert.AreEqual(0,(await backend.GetSnapshotAsync()).Credentials.Count);
 }
 [TestMethod] public async Task TypedSnapshotMatchesWorkerData()
 {var s=await backend.GetSnapshotAsync();Assert.AreEqual(new string('a',64),s.SnapshotDigest);}
 [TestMethod] public async Task PrivateJobRootHasOnlyCurrentUserAndSystem()
 {
  Assert.IsTrue((await backend.ExecuteAsync(StudioRequest.Create("status"))).Ok);
  var acl=new DirectoryInfo(options.JobsRoot).GetAccessControl();
  Assert.IsTrue(acl.AreAccessRulesProtected);
  var allowed=new[]{WindowsIdentity.GetCurrent().User!.Value,new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null).Value};
  foreach(FileSystemAccessRule rule in acl.GetAccessRules(true,true,typeof(SecurityIdentifier))) Assert.IsTrue(allowed.Contains(rule.IdentityReference.Value));
 }
 [TestMethod] public async Task ReadCancellationAlsoKillsWorker()
 {
  Mode("tree");using var cancel=new CancellationTokenSource();var pending=backend.ExecuteAsync(StudioRequest.Create("status"),ct:cancel.Token);await Ready();cancel.Cancel();Assert.AreEqual("cancelled",(await pending).Error?.Code);JobsEmpty();
 }
 [TestMethod] public async Task ReadCancellationDuringRecoveryDoesNotKillCommit()
 {
  Mode("read-commit");using var cancel=new CancellationTokenSource();var pending=backend.ExecuteAsync(StudioRequest.Create("status"),ct:cancel.Token);await Ready();
  cancel.Cancel();await Task.Delay(100);Assert.IsFalse(pending.IsCompleted);Release();Assert.IsTrue((await pending).Ok);Assert.IsTrue(File.Exists(Path.Combine(root,"committed.txt")));JobsEmpty();
 }
 [TestMethod] public async Task MalformedProbeTokenLimitIsControlled()
 {
  var result=await backend.ExecuteAsync(StudioRequest.Create("probe",new {kind="local",outputTokenLimit="256"}));
  Assert.AreEqual("invalid_request",result.Error?.Code);Assert.IsFalse(File.Exists(Path.Combine(root,"args.txt")));
 }
 [TestMethod] public async Task AnotherBackendCannotLaunchOrCleanDuringAnAction()
 {
  Mode("early");var first=backend.ExecuteAsync(StudioRequest.Create("status"));await Ready();var other=new WorkerBackend(options);
  Assert.AreEqual("busy",(await other.ExecuteAsync(StudioRequest.Create("repair"))).Error?.Code);Assert.AreEqual(0,other.CleanAbandonedJobs());Release();Assert.IsTrue((await first).Ok);
 }
 [TestMethod] public async Task MissingProbeRunnerIsControlledWithoutLaunch()
 {
  var other=new WorkerBackend(options with {ProbeWorkerPath=null});
  Assert.AreEqual("unsupported_capability",(await other.ExecuteAsync(StudioRequest.Create("probe",new{kind="local"}))).Error?.Code);
  Assert.IsFalse(File.Exists(Path.Combine(root,"args.txt")));
 }
 [TestMethod] public async Task FailedResultRemovesEncryptedJob()
 {
  Mode("corrupt");using var secret=new SecretInput(Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-BRIDGE-canary-key"}"""));
  Assert.AreEqual("invalid_result",(await backend.ExecuteAsync(StudioRequest.Create("save-key",new{label="CHINESE",ids=new[]{"deepseek-v4.1-flash"},ack=true}),secret)).Error?.Code);JobsEmpty();
 }
 [TestMethod] public async Task TypedProbeRequestsUseWireContractAndDefaultOptionals()
 {
  var production=new WorkerBackend(options with {ProbeWorkerPath=null});
  foreach(var kind in Enum.GetValues<ProbeKind>()){
   var payload=kind switch {
    ProbeKind.Catalog => new ProbeRequest(kind,CredentialLabel:"PLUS",Acknowledgement:true),
    ProbeKind.Responses or ProbeKind.Stream or ProbeKind.Tool => new ProbeRequest(kind,ModelId:"deepseek-v4.1-flash",ExpectedSnapshotDigest:new string('a',64),Acknowledgement:true),
    _ => new ProbeRequest(kind)
   };
   var request=StudioRequest.Create("probe",payload);
   Assert.AreEqual("unsupported_capability",(await production.ExecuteAsync(request)).Error?.Code);
   Assert.IsFalse(File.Exists(Path.Combine(root,"args.txt")));
  }
 }
 [TestMethod] public async Task TypedProbeRequestCanReachInjectedRunner()
 {
  var result=await backend.ExecuteAsync(StudioRequest.Create("probe",new ProbeRequest(ProbeKind.Local)));
  Assert.IsTrue(result.Ok);
  using var captured=JsonDocument.Parse(File.ReadAllText(Path.Combine(root,"captured-request.json")));
  Assert.AreEqual("local",captured.RootElement.GetProperty("payload").GetProperty("kind").GetString());
 }
 [TestMethod] public async Task NullSnapshotDigestIsControlledAndNextRefreshWorks()
 {
  Mode("null-digest");
  var error=await Assert.ThrowsExactlyAsync<StudioBackendException>(async()=>{await backend.GetSnapshotAsync();});
  Assert.AreEqual("invalid_result",error.Error.Code);
  Mode("normal");Assert.AreEqual(new string('a',64),(await backend.GetSnapshotAsync()).SnapshotDigest);
 }
 [TestMethod] public void FixtureCleanupRefusesMismatchedProcessIdentity()
 {
  using var sentinel=Process.Start(new ProcessStartInfo(options.PowerShellPath){ArgumentList={"-NoProfile","-Command","Start-Sleep -Seconds 20"},UseShellExecute=false,CreateNoWindow=true})!;
  try{
   File.WriteAllText(Path.Combine(root,"worker.pid"),sentinel.Id.ToString());
   File.WriteAllText(Path.Combine(root,"worker.start.txt"),"1");
   Cleanup();
   Assert.IsFalse(sentinel.HasExited,"Cleanup must refuse a PID belonging to a different process instance.");
  }finally{if(!sentinel.HasExited)sentinel.Kill(entireProcessTree:true);}
 }
}
