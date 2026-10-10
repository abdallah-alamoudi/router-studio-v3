using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public class StudioRuntimeLayoutTests
{
 private string root=null!;
 [TestInitialize] public void Setup()=>root=Path.Combine(Path.GetTempPath(),"Studio layout "+Guid.NewGuid().ToString("N"));
 [TestCleanup] public void Cleanup(){if(Directory.Exists(root))Directory.Delete(root,true);}
 private string Worker(string relative){var file=Path.Combine(root,relative);Directory.CreateDirectory(Path.GetDirectoryName(file)!);File.WriteAllText(file,"# fixture");return file;}
 [TestMethod] public void SourceTreeFindsRetainedWorker(){var worker=Worker(Path.Combine("src","worker","Studio-Worker.ps1"));Assert.AreEqual(worker,StudioRuntimeLayout.FindWorkerPath(root));}
 [TestMethod] public void FlatReleaseFindsRetainedWorker(){var worker=Worker("Studio-Worker.ps1");Assert.AreEqual(worker,StudioRuntimeLayout.FindWorkerPath(root));}
 [TestMethod] public void EmptyFixtureHasNoBackend(){Directory.CreateDirectory(root);Assert.IsNull(StudioRuntimeLayout.FindWorkerPath(root));Assert.IsNull(StudioRuntimeLayout.FindRoot(root));}
 [TestMethod] public void NestedBuildOutputFindsSourceRoot(){Worker(Path.Combine("src","worker","Studio-Worker.ps1"));var output=Path.Combine(root,"src","RouterStudio.Desktop","bin","Release");Directory.CreateDirectory(output);Assert.AreEqual(root,StudioRuntimeLayout.FindRoot(output));}
 [TestMethod] public void FlatReleaseFindsItsOwnRoot(){Worker("Studio-Worker.ps1");Assert.AreEqual(root,StudioRuntimeLayout.FindRoot(root));}
}
