using System.Security.Cryptography;
using System.Text;
using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class JobSecretWriterTests
{
 [TestMethod] public void CiphertextRoundTripsForCurrentUser()
 {
  var root=Path.Combine(Path.GetTempPath(),"DPAPI bridge "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  var raw=Encoding.UTF8.GetBytes("""{"PLUS":"fake-BRIDGE-canary-key","PRO":"","FULL":""}""");
  try {
   using var secret=new SecretInput(raw);JobSecretWriter.Write(root,secret);
   var cipher=File.ReadAllBytes(Path.Combine(root,"secret.dpapi"));
   Assert.IsFalse(Encoding.UTF8.GetString(cipher).Contains("fake-BRIDGE-canary-key"));
   var plain=ProtectedData.Unprotect(cipher,null,DataProtectionScope.CurrentUser);
   try{CollectionAssert.AreEqual(raw,plain);}finally{CryptographicOperations.ZeroMemory(plain);}
  }finally{CryptographicOperations.ZeroMemory(raw);Directory.Delete(root,true);}
 }
 [TestMethod] public void DisposedInputCannotBeWritten()
 {
  var root=Path.Combine(Path.GetTempPath(),"DPAPI disposed "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  var secret=new SecretInput(Encoding.UTF8.GetBytes("{}"));secret.Dispose();
  try{Assert.ThrowsExactly<ObjectDisposedException>(()=>JobSecretWriter.Write(root,secret));Assert.IsFalse(File.Exists(Path.Combine(root,"secret.dpapi")));}finally{Directory.Delete(root,true);}
 }
}
