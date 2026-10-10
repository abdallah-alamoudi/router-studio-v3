using System.IO;
using System.Windows;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop;
public partial class App : Application {
 private SingleInstance? instance;private TrayController? tray;
 protected override void OnStartup(StartupEventArgs e) {
  base.OnStartup(e); ThemeManager.Apply(ThemePreference.System);
  var explicitRoot=e.Args.Length==2&&e.Args[0]=="--project-root"?Path.GetFullPath(e.Args[1]):null;
  instance=new(explicitRoot??"RouterStudio");if(!instance.Primary){Shutdown();return;}
  var isolated=explicitRoot is not null&&StudioRuntimeLayout.FindWorkerPath(explicitRoot) is null;
  var userRoot=isolated?Path.Combine(explicitRoot!,"user-state"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"RouterStudio");
  var shell=new ShellViewModel(CreateBackend(e.Args),new HistoryStore(Path.Combine(userRoot,"history")));
  var appScript=Path.Combine(userRoot,"Launch-Desktop.vbs");var routerScript=Path.Combine(userRoot,"Launch-Router.vbs");var wscript=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"wscript.exe");
  shell.ConfigureSettings(new UserSettingsStore(Path.Combine(userRoot,"preferences")),new StartupPreferences(),File.Exists(appScript)?$"\"{wscript}\" //B \"{appScript}\"":null,File.Exists(routerScript)?$"\"{wscript}\" //B \"{routerScript}\"":null);
  var window=new MainWindow(shell);
  MainWindow=window; window.Show();
  tray=new(window,shell);instance.Listen(()=>Dispatcher.BeginInvoke(window.Restore));
 }
 protected override void OnExit(ExitEventArgs e){tray?.Dispose();instance?.Dispose();base.OnExit(e);}
 private static IStudioBackend CreateBackend(string[] args) {
  string? root=null;
  if(args.Length==2 && args[0]=="--project-root" && Path.IsPathFullyQualified(args[1])) root=Path.GetFullPath(args[1]);
  root??=StudioRuntimeLayout.FindRoot(AppContext.BaseDirectory);
  var worker=root is null?null:StudioRuntimeLayout.FindWorkerPath(root);
  var privatePowerShell=root is null?"":Path.Combine(root,"runtime","powershell","pwsh.exe");
  var powershell=File.Exists(privatePowerShell)?privatePowerShell:Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe");
  if(worker is null || !File.Exists(powershell)) return new UnavailableBackend();
  return new WorkerBackend(new(){PowerShellPath=powershell,WorkerPath=worker,ProbeWorkerPath=worker});
 }
 private sealed class UnavailableBackend : IStudioBackend {
  public Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct)=>Task.FromResult(StudioResult.Failure("installation_incomplete"));
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct)=>Task.FromException<StudioSnapshot>(new StudioBackendException(StudioErrors.Get("installation_incomplete")));
 }
}
