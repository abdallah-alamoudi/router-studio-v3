using RouterStudio.Core.Services;
namespace RouterStudio.Desktop.Presentation;
public sealed class SettingsViewModel:ObservableObject {
 private readonly StartupPreferences? startup;private readonly UserSettingsStore? store;private readonly ShellViewModel shell;private readonly string? appCommand,routerCommand;private bool closeToTray;
 public SettingsViewModel(ShellViewModel shell,UserSettingsStore? store=null,StartupPreferences? startup=null,string? appCommand=null,string? routerCommand=null){this.shell=shell;this.store=store;this.startup=startup;this.appCommand=appCommand;this.routerCommand=routerCommand;var saved=store?.Read()??new();Enum.TryParse<ThemePreference>(saved.Theme,out var theme);shell.Theme=theme;closeToTray=saved.CloseToTray;shell.PropertyChanged+=(_,e)=>{if(e.PropertyName==nameof(ShellViewModel.Theme))Save();};}
 public bool CloseToTray{get=>closeToTray;set{if(Set(ref closeToTray,value))Save();}}
 public bool StartApp{get=>startup?.AppEnabled??false;set{startup?.SetApp(value,appCommand);Notify();Notify(nameof(Notice));}}
 public bool StartRouter{get=>startup?.RouterEnabled??false;set{startup?.SetRouter(value,routerCommand);Notify();Notify(nameof(Notice));}}
 public string? Notice=>startup?.Notice??store?.Notice;
 private void Save(){store?.Save(new(shell.Theme.ToString(),CloseToTray));Notify(nameof(Notice));}
}
