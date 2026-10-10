using System.ComponentModel;using RouterStudio.Desktop.Presentation;using Forms=System.Windows.Forms;
namespace RouterStudio.Desktop;
internal sealed class TrayController:IDisposable {
 private readonly Forms.NotifyIcon icon;private readonly ShellViewModel shell;private readonly PropertyChangedEventHandler changed;
 public TrayController(MainWindow window,ShellViewModel shell){this.shell=shell;var menu=new Forms.ContextMenuStrip();menu.Items.Add("Open Router Studio",null,(_,_)=>window.Restore());var status=menu.Items.Add(shell.TrayText);status.Enabled=false;menu.Items.Add("Review router start",null,async(_,_)=>{window.Restore();await window.ReviewStartAsync();});menu.Items.Add("Review router stop",null,async(_,_)=>{window.Restore();await window.ReviewStopAsync();});menu.Items.Add("Exit Studio (keep router running)",null,async(_,_)=>await window.ExitAsync());icon=new(){Icon=System.Drawing.SystemIcons.Application,Text="Router Studio",ContextMenuStrip=menu,Visible=true};icon.DoubleClick+=(_,_)=>window.Restore();changed=(_,e)=>{if(e.PropertyName==nameof(ShellViewModel.TrayText)){status.Text=shell.TrayText;icon.Text=shell.TrayText.Length>63?shell.TrayText[..63]:shell.TrayText;}};shell.PropertyChanged+=changed;}
 public void Dispose(){shell.PropertyChanged-=changed;icon.Visible=false;icon.ContextMenuStrip?.Dispose();icon.Dispose();}
}
