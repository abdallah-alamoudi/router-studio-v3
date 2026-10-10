using Microsoft.Win32;
namespace RouterStudio.Core.Services;
public sealed class StartupPreferences {
 private readonly Func<string,string?> read;private readonly Action<string,string?> write;private readonly Func<bool> legacy;
 public string? Notice{get;private set;}
 public StartupPreferences(Func<string,string?>? read=null,Action<string,string?>? write=null,Func<bool>? legacy=null){this.read=read??(name=>{using var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");return key?.GetValue(name) as string;});this.write=write??((name,value)=>{using var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");if(value is null)key.DeleteValue(name,false);else key.SetValue(name,value);});this.legacy=legacy??(()=>File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"Safe8stokenRouter.vbs")));}
 public bool AppEnabled=>read("RouterStudioDesktop") is not null;
 public bool RouterEnabled=>legacy()||read("RouterStudioRouter") is not null;
 private void Set(string name,bool enabled,string? command){try{if(string.IsNullOrEmpty(command)){Notice="Install the packaged preview before changing startup preferences.";return;}var current=read(name);if(current is not null&&current!=command){Notice="This startup entry was changed externally. It was kept.";return;}write(name,enabled?command:null);Notice=null;}catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or System.Security.SecurityException){Notice="Startup could not be updated. Existing entries were kept.";}}
 public void SetApp(bool enabled,string? command)=>Set("RouterStudioDesktop",enabled,command);
 public void SetRouter(bool enabled,string? command){if(legacy()){Notice="The legacy router launcher already owns startup. Migrate that entry during packaged installation before changing this preference.";return;}Set("RouterStudioRouter",enabled,command);}
}
