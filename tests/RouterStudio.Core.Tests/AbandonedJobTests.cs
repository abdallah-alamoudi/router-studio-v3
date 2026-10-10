using System.Diagnostics;
using System.Text.Json;
using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class AbandonedJobTests
{
 private string root=null!;
 private WorkerBackend backend=null!;
 [TestInitialize] public void Setup()
 {
  root=Path.Combine(Path.GetTempPath(),"Router cleanup "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  backend=new(new() {JobsRoot=root,WorkerPath=Path.Combine(AppContext.BaseDirectory,"Fixtures","bridge-worker.ps1"),PowerShellPath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe")});
 }
 [TestCleanup] public void Cleanup()=>Directory.Delete(root,true);
 private string Job(DateTimeOffset created,int ownerId=2147483647,long ownerStart=1,int? workerId=null,long? workerStart=null)
 {
  var job=Path.Combine(root,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(job);
  File.WriteAllText(Path.Combine(job,"owner.json"),JsonSerializer.Serialize(new {schemaVersion=1,createdAtUtc=created,ownerPid=ownerId,ownerStartUtcTicks=ownerStart,workerPid=workerId,workerStartUtcTicks=workerStart}));
  File.WriteAllBytes(Path.Combine(job,"secret.dpapi"),[1,2,3]);return job;
 }
 [TestMethod] public void OldAbsentOwnerJobIsRemoved()
 {var job=Job(DateTimeOffset.UtcNow.AddHours(-25));Assert.AreEqual(1,backend.CleanAbandonedJobs());Assert.IsFalse(Directory.Exists(job));}
 [TestMethod] public void RecentOrLiveOwnerOrLiveWorkerIsPreserved()
 {
  using var p=Process.GetCurrentProcess();long start=p.StartTime.ToUniversalTime().Ticks;
  var jobs=new[]{Job(DateTimeOffset.UtcNow.AddHours(-1)),Job(DateTimeOffset.UtcNow.AddHours(-25),p.Id,start),Job(DateTimeOffset.UtcNow.AddHours(-25),workerId:p.Id,workerStart:start)};
  Assert.AreEqual(0,backend.CleanAbandonedJobs());foreach(var job in jobs)Assert.IsTrue(Directory.Exists(job));
 }
 [TestMethod] public void ReusedPidDoesNotKeepAbandonedJobForever()
 {using var p=Process.GetCurrentProcess();var job=Job(DateTimeOffset.UtcNow.AddHours(-25),p.Id,1);Assert.AreEqual(1,backend.CleanAbandonedJobs());Assert.IsFalse(Directory.Exists(job));}
 [TestMethod] public void UnknownDirectoryAndCorruptMetadataArePreserved()
 {
  Directory.CreateDirectory(Path.Combine(root,"user-files"));var job=Job(DateTimeOffset.UtcNow.AddHours(-25));File.WriteAllText(Path.Combine(job,"owner.json"),"{bad");
  Assert.AreEqual(0,backend.CleanAbandonedJobs());Assert.IsTrue(Directory.Exists(job));
 }
 [TestMethod] public void ActiveWorkerLeasePreservesAbandonedOwnerJob()
 {
  var job=Job(DateTimeOffset.UtcNow.AddHours(-25));
  using(var active=new FileStream(Path.Combine(job,"active.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){
   Assert.AreEqual(0,backend.CleanAbandonedJobs());Assert.IsTrue(Directory.Exists(job));
  }
  Assert.AreEqual(1,backend.CleanAbandonedJobs());
 }
}
