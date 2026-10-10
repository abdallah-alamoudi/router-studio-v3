using System.Diagnostics;
using System.Text;
using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class DpapiWorkerTests
{
 [TestMethod] public async Task CSharpEnvelopeIsConsumedByActualWorker()
 {
  var root=Path.Combine(Path.GetTempPath(),"CSharp DPAPI Ω "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  try{
   var raw=Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-BRIDGE-canary-key"}""");using var secret=new SecretInput(raw);Array.Clear(raw);JobSecretWriter.Write(root,secret);
   var project=Directory.GetCurrentDirectory();while(!File.Exists(Path.Combine(project,"src","worker","Studio-Worker.ps1")))project=Directory.GetParent(project)?.FullName ?? throw new InvalidOperationException("Project root not found");
   var launch=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe")){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   foreach(var arg in new[]{"-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(project,"tests","dpapi-envelope.ps1"),"-ProjectRoot",project,"-CipherFile",Path.Combine(root,"secret.dpapi"),"-Case","SaveKey"})launch.ArgumentList.Add(arg);
   using var process=Process.Start(launch)!;var output=process.StandardOutput.ReadToEndAsync();var errors=process.StandardError.ReadToEndAsync();
   using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(30));
   try{await process.WaitForExitAsync(timeout.Token);}catch(OperationCanceledException){process.Kill(true);throw;}
   Assert.AreEqual(0,process.ExitCode,await errors);StringAssert.Contains(await output,"DPAPI: PASS");
   Assert.IsFalse((await output+await errors).Contains("fake-BRIDGE-canary-key"));
  }finally{Directory.Delete(root,true);}
 }
}
