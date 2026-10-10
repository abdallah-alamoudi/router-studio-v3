namespace RouterStudio.Core.Services;

public static class StudioRuntimeLayout
{
 public static string? FindWorkerPath(string root)
 {
  foreach(var relative in new[]{Path.Combine("src","worker","Studio-Worker.ps1"),"Studio-Worker.ps1"})
  {
   var candidate=Path.Combine(root,relative);
   if(File.Exists(candidate))return candidate;
  }
  return null;
 }
 public static string? FindRoot(string startDirectory)
 {
  for(var directory=new DirectoryInfo(startDirectory);directory is not null;directory=directory.Parent)
   if(FindWorkerPath(directory.FullName) is not null)return directory.FullName;
  return null;
 }
}
