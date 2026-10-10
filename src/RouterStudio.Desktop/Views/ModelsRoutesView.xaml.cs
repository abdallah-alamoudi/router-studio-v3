using System.Windows;
using System.Windows.Controls;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop.Views;
public partial class ModelsRoutesView : UserControl {
 public ModelsRoutesView(){InitializeComponent();}
 private void OpenKeys(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)shell.Navigate(StudioPage.Keys);}
}
