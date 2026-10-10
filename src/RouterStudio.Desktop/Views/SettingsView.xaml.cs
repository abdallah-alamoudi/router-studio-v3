using System.IO;using System.Windows;using System.Windows.Controls;using Microsoft.Win32;using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop.Views;
public partial class SettingsView:UserControl {
 public SettingsView(){InitializeComponent();}
 private async void InstallRouter(object sender,RoutedEventArgs e){
  var plus=SetupPlus.Password;var pro=SetupPro.Password;var full=SetupFull.Password;SetupPlus.Clear();SetupPro.Clear();SetupFull.Clear();
  if(DataContext is not ShellViewModel shell||!shell.CanMutate||shell.IsConfirmationOpen||string.IsNullOrWhiteSpace(plus))return;
  var bytes=System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(new{PLUS=plus,PRO=pro,FULL=full});plus=pro=full="";
  using var secret=new RouterStudio.Core.Services.SecretInput(bytes);System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes);
  await ManagementInteraction.ConfirmAsync(this,shell,"Install local router?","Save work and close Codex first. Setup encrypts keys for this Windows user, changes the default Codex connection, and starts the local router. Existing installations are refused. Sign out and back in afterward so Codex inherits local authentication.",async()=>{await shell.RunRequestAsync(RouterStudio.Core.Contracts.StudioRequest.Create("install"),secret,true);});
 }
 private async void ClearHistory(object sender,RoutedEventArgs e){if(DataContext is not ShellViewModel shell||!shell.CanMutate)return;await ManagementInteraction.ConfirmAsync(this,shell,"Clear local history?","This removes saved test and action records. Keys, routes and configuration backups stay intact.",()=>{shell.ClearHistory();return Task.CompletedTask;});}
 private void ExportSupport(object sender,RoutedEventArgs e){if(DataContext is not ShellViewModel shell||!shell.CanMutate)return;var dialog=new SaveFileDialog{Title="Save safe support details",FileName="router-studio-support.json",Filter="JSON (*.json)|*.json",AddExtension=true};if(dialog.ShowDialog(Window.GetWindow(this))!=true)return;try{File.WriteAllText(dialog.FileName,shell.ExportDiagnostics());}catch(Exception error) when(error is IOException or UnauthorizedAccessException){MessageBox.Show(Window.GetWindow(this),"Support details could not be saved. Choose another location.","Router Studio",MessageBoxButton.OK,MessageBoxImage.Warning);}}
}
