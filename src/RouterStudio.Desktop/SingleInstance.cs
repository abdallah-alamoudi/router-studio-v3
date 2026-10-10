using System.Security.Principal;using System.Security.Cryptography;using System.Text;
namespace RouterStudio.Desktop;
internal sealed class SingleInstance:IDisposable {
 private readonly Mutex mutex;private readonly EventWaitHandle signal;private readonly bool held;private RegisteredWaitHandle? listener;
 public bool Primary=>held;
 public SingleInstance(string scope){var identity=WindowsIdentity.GetCurrent().User!.Value;var hash=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(scope)))[..16];var name=@"Local\RouterStudio-"+identity+"-"+hash;mutex=new(false,name);try{held=mutex.WaitOne(0);}catch(AbandonedMutexException){held=true;}signal=new(false,EventResetMode.AutoReset,name+"-activate");if(!held)signal.Set();}
 public void Listen(Action activate)=>listener=ThreadPool.RegisterWaitForSingleObject(signal,(_,_)=>activate(),null,Timeout.Infinite,false);
 public void Dispose(){listener?.Unregister(null);signal.Dispose();if(held)mutex.ReleaseMutex();mutex.Dispose();}
}
