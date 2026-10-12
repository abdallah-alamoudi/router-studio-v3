using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;
using RouterStudio.Core.Contracts;
namespace RouterStudio.Core.Services;
public sealed partial class WorkerBackend : IStudioBackend
{
 private readonly WorkerBackendOptions options;
 private int outstanding;
 private const int MaximumResultBytes=4*1024*1024;
 public WorkerBackend(WorkerBackendOptions options)
 {
  this.options=options with {
   PowerShellPath=Absolute(options.PowerShellPath),WorkerPath=Absolute(options.WorkerPath),
   ProbeWorkerPath=options.ProbeWorkerPath is null ? null : Absolute(options.ProbeWorkerPath),JobsRoot=Absolute(options.JobsRoot)
  };
  if(options.FixturePaths is { } fixture) {
   var uri=fixture.HealthUri;
   if(uri.Scheme!="http" || uri.Host!="127.0.0.1" || uri.AbsolutePath!="/__router/health" || uri.UserInfo.Length!=0 || uri.Query.Length!=0 || uri.Fragment.Length!=0)throw new ArgumentException("Invalid fixture health URI.");
   this.options=this.options with {FixturePaths=new(Absolute(fixture.InstallRoot),Absolute(fixture.ConfigPath),uri)};
  }
 }
 private static string Absolute(string path)
 {
  if(!Path.IsPathFullyQualified(path))throw new ArgumentException("An absolute local path is required.");
  var full=Path.GetFullPath(path);
  if(full.StartsWith(@"\\",StringComparison.Ordinal))throw new ArgumentException("A local path is required.");
  return full;
 }
 public async Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret=null,CancellationToken ct=default)
 {
  var invalid=RequestPolicy.Validate(request,secret);
  if(invalid is not null)return StudioResult.Failure(invalid);
  if(ct.IsCancellationRequested)return StudioResult.Failure("cancelled");
  if(request.Action=="probe" && options.ProbeWorkerPath is null)return StudioResult.Failure("unsupported_capability");
  if(Interlocked.CompareExchange(ref outstanding,1,0)!=0)return StudioResult.Failure("busy");
  string? job=null;
  bool finished=false;
  FileStream? bridgeLease=null;
  Process? process=null;
  using var drainCancel=new CancellationTokenSource();
  Task stdout=Task.CompletedTask,stderr=Task.CompletedTask;
  try{
   SecureRoot();
   bridgeLease=TryLease(Path.Combine(options.JobsRoot,"bridge.lock"));
   if(bridgeLease is null)return StudioResult.Failure("busy");
   if(ct.IsCancellationRequested)return StudioResult.Failure("cancelled");
   job=Path.Combine(options.JobsRoot,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(job);
   using var owner=Process.GetCurrentProcess();
   var metadata=new JobOwner(1,DateTimeOffset.UtcNow,owner.Id,owner.StartTime.ToUniversalTime().Ticks,null,null);
   WriteOwner(job,metadata);
   File.WriteAllBytes(Path.Combine(job,"request.json"),JsonSerializer.SerializeToUtf8Bytes(request,StudioJson.Options));
   if(secret is not null)JobSecretWriter.Write(job,secret);
   if(ct.IsCancellationRequested)return StudioResult.Failure("cancelled");
   var launch=new ProcessStartInfo(options.PowerShellPath) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   foreach(var arg in new[]{"-NoProfile","-ExecutionPolicy","Bypass","-File",request.Action=="probe"?options.ProbeWorkerPath!:options.WorkerPath,"-Job",job})launch.ArgumentList.Add(arg);
   if(options.FixturePaths is { } fixture) {
    foreach(var arg in new[]{"-InstallRoot",fixture.InstallRoot,"-ConfigPath",fixture.ConfigPath,"-HealthUri",fixture.HealthUri.AbsoluteUri})launch.ArgumentList.Add(arg);
   }
   process=Process.Start(launch) ?? throw new InvalidOperationException("Worker did not start.");
   stdout=Drain(process.StandardOutput.BaseStream,drainCancel.Token);
   stderr=Drain(process.StandardError.BaseStream,drainCancel.Token);
   try{WriteOwner(job,metadata with {WorkerPid=process.Id,WorkerStartUtcTicks=process.StartTime.ToUniversalTime().Ticks});}
   catch(IOException){/* Worker still finishes; its active lease protects recovery if the parent exits. */}
   catch(UnauthorizedAccessException){/* Never terminate a mutation because metadata could not be refreshed. */}
   bool cancelled=false;
   if(RequestPolicy.IsMutation(request.Action))await process.WaitForExitAsync(CancellationToken.None);
   else{
    try{await process.WaitForExitAsync(ct);}
    catch(OperationCanceledException){
     // A read may have entered recovery. Only kill while holding the same commit lock that guards worker writes.
     using var commit=TryLease(Path.Combine(job,"commit.lock"));
     if(commit is not null){
      try{if(!process.HasExited)process.Kill(entireProcessTree:true);}catch(InvalidOperationException){}
      cancelled=true;
     }
     await process.WaitForExitAsync(CancellationToken.None);
    }
   }
   finished=true;
   drainCancel.Cancel();await Task.WhenAll(stdout,stderr);
   if(cancelled)return StudioResult.Failure("cancelled");
   if(process.ExitCode!=0)return StudioResult.Failure("worker_failed");
   return ReadResult(job);
  }catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or InvalidOperationException or System.Security.Cryptography.CryptographicException){
   // An already-started mutation must outlive launch/result bookkeeping failures.
   if(process is not null && !process.HasExited){
    if(RequestPolicy.IsMutation(request.Action))await process.WaitForExitAsync(CancellationToken.None);
    else{
     using var commit=job is null?null:TryLease(Path.Combine(job,"commit.lock"));
     if(commit is not null)process.Kill(entireProcessTree:true);
     await process.WaitForExitAsync(CancellationToken.None);
    }
   }
   finished=process is null || process.HasExited;
   return StudioResult.Failure(RequestPolicy.IsMutation(request.Action)&&process is not null?"recovery_required":"worker_failed");
  }finally{
   drainCancel.Cancel();
   await Task.WhenAll(stdout,stderr);
   process?.Dispose();
   if(job is not null && (process is null || finished))TryDeleteJob(job);
   bridgeLease?.Dispose();Volatile.Write(ref outstanding,0);
  }
 }
 public async Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct=default)
 {
  var result=await ExecuteAsync(StudioRequest.Create("status"),ct:ct);
  if(!result.Ok || result.Data is null)throw new StudioBackendException(result.Error ?? StudioErrors.Get("invalid_result"));
  try{
   var snapshot=result.Data.Value.Deserialize<StudioSnapshot>(StudioJson.Options);
   if(snapshot is null || snapshot.SnapshotDigest is null || !Regex.IsMatch(snapshot.SnapshotDigest,"^[a-f0-9]{64}$") || snapshot.CheckedAtUtc==default || snapshot.Models is null || snapshot.Credentials is null || snapshot.CustomModels is null || snapshot.Keys is null || snapshot.Backups is null || snapshot.RouterHealth is null || snapshot.Connection is null || snapshot.RuntimeVersions is null)throw new JsonException();
   return snapshot;
  }catch(JsonException){throw new StudioBackendException(StudioErrors.Get("invalid_result"));}
 }
 private static async Task Drain(Stream stream,CancellationToken ct)
 {
  try{await stream.CopyToAsync(Stream.Null,ct);}catch(OperationCanceledException){}catch(IOException){}catch(ObjectDisposedException){}
 }
 private static StudioResult ReadResult(string job)
 {
  try{
   var path=Path.Combine(job,"result.json");
   if(!File.Exists(path) || new FileInfo(path).Length>MaximumResultBytes || (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)return StudioResult.Failure("invalid_result");
   using var doc=JsonDocument.Parse(File.ReadAllBytes(path),new JsonDocumentOptions{MaxDepth=32});
   var envelope=doc.RootElement;
   if(envelope.ValueKind!=JsonValueKind.Object || !envelope.TryGetProperty("schemaVersion",out var schema) || !schema.TryGetInt32(out int version))return StudioResult.Failure("invalid_result");
   if(version!=1)return StudioResult.Failure("unsupported_schema");
   if(!envelope.TryGetProperty("ok",out var ok) || ok.ValueKind is not (JsonValueKind.True or JsonValueKind.False))return StudioResult.Failure("invalid_result");
   if(ok.GetBoolean()){
    if(!envelope.TryGetProperty("data",out var data) || data.ValueKind!=JsonValueKind.Object || envelope.TryGetProperty("error",out _))return StudioResult.Failure("invalid_result");
    return new(1,true,data.Clone(),null);
   }
   if(!envelope.TryGetProperty("error",out var error) || error.ValueKind!=JsonValueKind.Object || !error.TryGetProperty("code",out var code) || code.ValueKind!=JsonValueKind.String)return StudioResult.Failure("invalid_result");
   return StudioResult.Failure(code.GetString()!);
  }catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException){return StudioResult.Failure("invalid_result");}
 }
 private void SecureRoot()
 {
  Directory.CreateDirectory(options.JobsRoot);
  if((File.GetAttributes(options.JobsRoot)&FileAttributes.ReparsePoint)!=0)throw new IOException("Job root cannot be a link.");
  var acl=new DirectorySecurity();acl.SetAccessRuleProtection(true,false);
  foreach(var sid in new[]{WindowsIdentity.GetCurrent().User!,new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null)})
   acl.AddAccessRule(new FileSystemAccessRule(sid,FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
  new DirectoryInfo(options.JobsRoot).SetAccessControl(acl);
 }
 private static FileStream? TryLease(string path)
 {
  try{
   if(File.Exists(path) && (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)return null;
   return new(path,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
  }catch(IOException){return null;}catch(UnauthorizedAccessException){return null;}
 }
 private static void WriteOwner(string job,JobOwner owner)
 {
  var path=Path.Combine(job,"owner.json");
  File.WriteAllBytes(path+".tmp",JsonSerializer.SerializeToUtf8Bytes(owner,StudioJson.Options));
  File.Move(path+".tmp",path,true);
 }
 private sealed record JobOwner(int SchemaVersion,DateTimeOffset CreatedAtUtc,int OwnerPid,long OwnerStartUtcTicks,int? WorkerPid,long? WorkerStartUtcTicks);
}
public sealed class StudioBackendException(StudioError error) : Exception(error.Message)
{
 public StudioError Error {get;}=error;
}
