using System.Windows;using System.Windows.Controls;using System.Windows.Threading;using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop.Views;
public partial class TestLabView:UserControl {
 private readonly DispatcherTimer timer=new(){Interval=TimeSpan.FromSeconds(1)};
 public TestLabView(){InitializeComponent();timer.Tick+=(_,_)=>{if(DataContext is ShellViewModel shell)shell.TestLab.NotifyElapsed();};Loaded+=(_,_)=>timer.Start();Unloaded+=(_,_)=>timer.Stop();}
 private bool InvalidCap=>DataContext is ShellViewModel shell&&shell.TestLab.NeedsModel&&Validation.GetHasError(OutputLimit);
 private async void Preview(object sender,RoutedEventArgs e){ProbeAcknowledgement.IsChecked=false;if(InvalidCap)return;if(DataContext is ShellViewModel shell)await shell.TestLab.PreviewAsync();}
 private async void Run(object sender,RoutedEventArgs e){if(DataContext is not ShellViewModel shell)return;var acknowledged=ProbeAcknowledgement.IsChecked==true;ProbeAcknowledgement.IsChecked=false;if(InvalidCap)return;await shell.TestLab.RunAsync(acknowledged);}
 private void Cancel(object sender,RoutedEventArgs e){if(DataContext is ShellViewModel shell)shell.TestLab.Cancel();}
}
