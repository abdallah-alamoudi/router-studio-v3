using System.Security.Cryptography;
namespace RouterStudio.Core.Services;
public static class JobSecretWriter
{
 public static void Write(string jobDirectory, SecretInput secret)
 {
  var plain=secret.Bytes.ToArray();
  byte[]? cipher=null;
  try{
   cipher=ProtectedData.Protect(plain,null,DataProtectionScope.CurrentUser);
   using var file=new FileStream(Path.Combine(jobDirectory,"secret.dpapi"),FileMode.CreateNew,FileAccess.Write,FileShare.None);
   file.Write(cipher);file.Flush(flushToDisk:true);
  }finally{
   CryptographicOperations.ZeroMemory(plain);
   if(cipher is not null)CryptographicOperations.ZeroMemory(cipher);
  }
 }
}
