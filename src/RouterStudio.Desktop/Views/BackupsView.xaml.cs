using System.Windows;
using System.Windows.Controls;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop.Views;
public partial class BackupsView : UserControl {
 public BackupsView(){InitializeComponent();}
 private async void PreviewBackup(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await shell.Backups.PreviewAsync();}
 private async void RestoreBackup(object sender,RoutedEventArgs e){
  if(DataContext is not ShellViewModel shell || !shell.Backups.CanRestore)return;
  await ManagementInteraction.ConfirmAsync(this,shell,"Restore configuration backup?","Confirm only after saving your work and closing Codex. The full configuration file will be replaced with the selected backup, including other settings stored there. A copy of current configuration is saved first. Keys and model catalogs are not replaced. Restart Codex and start a new session afterwards.",()=>shell.Backups.RestoreAsync(true));
 }
}
