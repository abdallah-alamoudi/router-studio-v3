using System.Diagnostics;
using RouterStudio.Core.Contracts;
using System.Text.Json;
namespace RouterStudio.Core.Services;
public sealed partial class WorkerBackend
{
 public int CleanAbandonedJobs()
 {
  if(Volatile.Read(ref outstanding)!=0)return 0;
  SecureRoot();
  using var bridge=TryLease(Path.Combine(options.JobsRoot,"bridge.lock"));
  if(bridge is null)return 0;
  int removed=0;
  foreach(var job in Directory.EnumerateDirectories(options.JobsRoot)){
   if(!Guid.TryParseExact(Path.GetFileName(job),"N",out _) || HasReparsePoint(job))continue;
   var ownerPath=Path.Combine(job,"owner.json");
   if(!File.Exists(ownerPath) || new FileInfo(ownerPath).Length>8192)continue;
   try{
    var owner=JsonSerializer.Deserialize<JobOwner>(File.ReadAllBytes(ownerPath),StudioJson.Options);
    if(owner is null || owner.SchemaVersion!=1 || owner.OwnerPid<=0 || owner.OwnerStartUtcTicks<=0 || owner.CreatedAtUtc==default || DateTimeOffset.UtcNow-owner.CreatedAtUtc<TimeSpan.FromHours(24))continue;
    if(IsAlive(owner.OwnerPid,owner.OwnerStartUtcTicks))continue;
    if(owner.WorkerPid.HasValue){
     if(!owner.WorkerStartUtcTicks.HasValue || owner.WorkerStartUtcTicks<=0 || IsAlive(owner.WorkerPid.Value,owner.WorkerStartUtcTicks.Value))continue;
    }
    using(var active=TryLease(Path.Combine(job,"active.lock"))){if(active is null)continue;}
    using(var commit=TryLease(Path.Combine(job,"commit.lock"))){if(commit is null)continue;}
    if(TryDeleteJob(job))removed++;
   }catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or JsonException){/* Unknown state is retained. */}
  }
  return removed;
 }
 private static bool IsAlive(int pid,long start)
 {
  try{using var process=Process.GetProcessById(pid);return !process.HasExited && process.StartTime.ToUniversalTime().Ticks==start;}
  catch(ArgumentException){return false;}catch(InvalidOperationException){return false;}
  catch(System.ComponentModel.Win32Exception){return true;}
 }
 private static bool HasReparsePoint(string directory)
 {
  var pending=new Stack<string>();pending.Push(directory);
  while(pending.TryPop(out var current)){
   if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)return true;
   foreach(var item in Directory.EnumerateFileSystemEntries(current)){
    var attributes=File.GetAttributes(item);
    if((attributes&FileAttributes.ReparsePoint)!=0)return true;
    if((attributes&FileAttributes.Directory)!=0)pending.Push(item);
   }
  }
  return false;
 }
 private bool TryDeleteJob(string job)
 {
  var full=Path.GetFullPath(job);
  var parent=Path.GetDirectoryName(full);
  if(!string.Equals(parent,options.JobsRoot.TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase) || !Guid.TryParseExact(Path.GetFileName(full),"N",out _))return false;
  try{
   if(!Directory.Exists(full))return true;
   if(HasReparsePoint(full))return false;
   Directory.Delete(full,recursive:true);return true;
  }catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}
 }
}
