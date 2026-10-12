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

 private void NewCredential(object sender,RoutedEventArgs e){IndependentKeyPassword.Clear();if(DataContext is ShellViewModel shell)shell.SavedCredentials.New();}
 private async Task SubmitCredential(bool rotate){
  var password=IndependentKeyPassword.Password;IndependentKeyPassword.Clear();
  if(DataContext is not ShellViewModel shell||shell.IsConfirmationOpen||!shell.SavedCredentials.CanManage||string.IsNullOrWhiteSpace(password))return;
  if(rotate&&!shell.SavedCredentials.CanEdit)return;
  var credentialId=rotate?shell.SavedCredentials.Selected!.Id:shell.SavedCredentials.NewCredentialId;
  var bytes=JsonSerializer.SerializeToUtf8Bytes(new{credentialId,key=password});password="";
  using var secret=new SecretInput(bytes);CryptographicOperations.ZeroMemory(bytes);
  await ManagementInteraction.ConfirmAsync(this,shell,rotate?"Rotate credential?":"Save new credential?","Save your work and close Codex. The key will be saved encrypted for this Windows user, and the owned router will stop. Restart it explicitly from Connections. Rotation invalidates the stored catalog and dependent custom-model availability.",()=>rotate?shell.SavedCredentials.RotateAsync(secret,true):shell.SavedCredentials.SaveAsync(secret,true));
 }
 private async void SaveCredential(object sender,RoutedEventArgs e)=>await SubmitCredential(false);
 private async void RotateCredential(object sender,RoutedEventArgs e)=>await SubmitCredential(true);
 private async void RenameCredential(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await ManagementInteraction.ConfirmAsync(this,shell,"Rename credential?","Save your work and close Codex. The display name changes without changing identity or secret. The owned router stops; restart it explicitly from Connections.",()=>shell.SavedCredentials.RenameAsync(true));}
 private async void DeleteCredential(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await ManagementInteraction.ConfirmAsync(this,shell,"Delete credential?","Save your work and close Codex. Remove this saved credential and its encrypted key. Deletion is refused while a custom model or legacy route uses it. The owned router stops; restart it explicitly from Connections.",()=>shell.SavedCredentials.DeleteAsync(true));}
 private async void FetchCredentialCatalog(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await ManagementInteraction.ConfirmAsync(this,shell,"Contact 8stoken for this key?","Send an authenticated GET /v1/models using only the selected saved key. No generation request is sent. Provider access, billing rules and declared reasoning metadata are not independently verified. Save your work and close Codex: saving the catalog stops the owned router; restart it explicitly.",()=>shell.SavedCredentials.FetchAsync(true));}
}
