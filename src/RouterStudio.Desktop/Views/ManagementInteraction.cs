using System.Windows;
using RouterStudio.Desktop.Presentation;
using RouterStudio.Desktop.Views.Components;
namespace RouterStudio.Desktop.Views;
internal static class ManagementInteraction {
 public static async Task ConfirmAsync(FrameworkElement owner,ShellViewModel shell,string title,string details,Func<Task> apply){
  if(shell.IsBusy || shell.IsConfirmationOpen)return;shell.IsConfirmationOpen=true;
  try{var dialog=new ConfirmationDialog(title,details){Owner=Window.GetWindow(owner)};if(dialog.ShowDialog()==true)await apply();}
  finally{shell.IsConfirmationOpen=false;}
 }
}
