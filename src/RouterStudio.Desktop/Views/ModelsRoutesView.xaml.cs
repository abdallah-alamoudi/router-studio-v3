using System.Windows;
using System.Windows.Controls;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop.Views;
public partial class ModelsRoutesView : UserControl {
 public ModelsRoutesView(){InitializeComponent();}
 private void OpenKeys(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)shell.Navigate(StudioPage.Keys);}

 private void NewCustomModel(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)shell.CustomModels.New();}
 private async void SaveCustomModel(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await ManagementInteraction.ConfirmAsync(this,shell,"Save custom model?","Save your work and close Codex. This stable custom ID will route only to the selected original model and credential. No effort is forced and no fallback is used. The owned router stops; restart it explicitly from Connections.",()=>shell.CustomModels.SaveAsync(true));}
 private async void DeleteCustomModel(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)await ManagementInteraction.ConfirmAsync(this,shell,"Delete custom model?","Save your work and close Codex. This custom ID is retired and will not silently fall back to another credential. The original model and saved key remain. The owned router stops; restart it explicitly from Connections.",()=>shell.CustomModels.DeleteAsync(true));}
}
