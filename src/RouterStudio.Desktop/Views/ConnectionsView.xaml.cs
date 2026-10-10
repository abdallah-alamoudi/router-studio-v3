using System.Windows.Controls;
using System.Windows;
using RouterStudio.Desktop.Presentation;
using RouterStudio.Desktop.Views.Components;
namespace RouterStudio.Desktop.Views;
public partial class ConnectionsView : UserControl {
 public ConnectionsView(){InitializeComponent();}
 private async void SelectOfficial(object sender,RoutedEventArgs e)=>await SelectAsync("official");
 private async void SelectRouter(object sender,RoutedEventArgs e)=>await SelectAsync("router");
 private async Task SelectAsync(string selection) {
  if(DataContext is not ShellViewModel shell || !shell.Connections.CanSelect || shell.IsConfirmationOpen)return;
  shell.IsConfirmationOpen=true;
  try {
   string details=selection=="official" ? "Select official ChatGPT subscription configuration. A configuration backup is created. Restart Codex, use official sign-in to choose your account/workspace, and start a new session. Authentication and quota are not checked." :
    "Select the localhost Responses router at http://127.0.0.1:18761/v1, forwarding to https://8stoken.com. A configuration backup is created. Confirm only after saving your work and closing Codex: the worker may restart the router to load saved files. Reopen Codex and start a new session. No upstream request is sent.";
   var dialog=new ConfirmationDialog("Review connection change",details){Owner=Window.GetWindow(this)};
   bool confirmed=dialog.ShowDialog()==true;
   if(confirmed)await shell.SelectConnectionAsync(selection,true);
  } finally {shell.IsConfirmationOpen=false;}
 }
}
