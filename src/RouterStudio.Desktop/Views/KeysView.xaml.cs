using System.Windows;
using System.Windows.Controls;
using System.Text.Json;
using System.Security.Cryptography;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop.Views;
public partial class KeysView : UserControl {
 public KeysView(){InitializeComponent();}
 private void SelectionChanged(object sender,SelectionChangedEventArgs e){if(DataContext is ShellViewModel shell)shell.Keys.ClearPreview();}
 private async void PreviewRoutes(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await shell.Keys.PreviewAsync(RawModels.SelectedItems.Cast<StudioModel>().Select(m=>m.Id));}
 private async void ApplyKey(object sender,RoutedEventArgs e){
  var password=KeyPassword.Password;KeyPassword.Clear();
  if(DataContext is not ShellViewModel shell || !shell.Keys.CanApply || shell.IsConfirmationOpen || string.IsNullOrWhiteSpace(password))return;
  byte[] bytes=JsonSerializer.SerializeToUtf8Bytes(new{label=shell.Keys.PreviewLabel,key=password});password="";
  using var secret=new SecretInput(bytes);CryptographicOperations.ZeroMemory(bytes);
  await ManagementInteraction.ConfirmAsync(this,shell,"Apply encrypted key?","Confirm only after saving work and closing Codex. The selected key and routes will be saved, and the router will restart. Unselected routes remain unchanged. If restart fails, the new key stays saved; read Diagnostics and refresh before retrying.",()=>shell.Keys.ApplyAsync(secret,true));
 }
}
