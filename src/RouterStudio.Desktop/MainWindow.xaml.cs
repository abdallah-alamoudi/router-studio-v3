using System.ComponentModel;
using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using RouterStudio.Desktop.Presentation;
using RouterStudio.Desktop.Views;
namespace RouterStudio.Desktop;
public partial class MainWindow : Window {
 private readonly ShellViewModel shell;
 private readonly Dictionary<StudioPage,UserControl> pages=[];
 private readonly DispatcherTimer refreshTimer=new(){Interval=TimeSpan.FromSeconds(15)};
 private bool allowClose;
 private Task? exitTask;
 public MainWindow(ShellViewModel shell) {
  InitializeComponent(); this.shell=shell; DataContext=shell;
  shell.PropertyChanged+=Changed; SystemParameters.StaticPropertyChanged+=SystemChanged; SystemEvents.UserPreferenceChanged+=PreferenceChanged;
  refreshTimer.Tick+=RefreshTick;
  IsVisibleChanged+=(_,_)=>UpdateRefreshTimer();StateChanged+=(_,_)=>UpdateRefreshTimer();
  Closing+=ClosingWindow;
  Closed+=(_,_)=>{refreshTimer.Stop();refreshTimer.Tick-=RefreshTick;shell.IsWindowVisible=false;shell.PropertyChanged-=Changed;SystemParameters.StaticPropertyChanged-=SystemChanged;SystemEvents.UserPreferenceChanged-=PreferenceChanged;};
  ShowPage();
 }
 private async void RefreshTick(object? sender,EventArgs e)=>await shell.TimerTickAsync();
 private async void StartRouter(object sender,RoutedEventArgs e) {
  await ReviewStartAsync();
 }
 public void Restore(){Show();if(WindowState==WindowState.Minimized)WindowState=WindowState.Normal;Activate();}
 private async void ClosingWindow(object? sender,CancelEventArgs e){if(allowClose)return;e.Cancel=true;await Dispatcher.Yield(DispatcherPriority.Background);if(shell.Settings.CloseToTray&&!shell.IsExiting){Hide();return;}await ExitAsync();}
 public Task ExitAsync()=>exitTask??=ExitCoreAsync();
 private async Task ExitCoreAsync(){if(allowClose)return;shell.BeginExit();await shell.WaitForIdleAsync();await Dispatcher.Yield(DispatcherPriority.Background);allowClose=true;Close();}
 public async Task ReviewStopAsync(){if(!shell.StatusAvailable)return;await ManagementInteraction.ConfirmAsync(this,shell,"Stop the owned local router?","Active requests may be interrupted. Save your work and close Codex before confirming. This stops only the verified owned router, not other listeners.",()=>shell.ExecuteMutationAsync(RouterStudio.Core.Contracts.StudioRequest.Create("stop",new{ack=true})));}
 public async Task ReviewStartAsync() {
  if(!shell.CanStartRouter)return;
  await ManagementInteraction.ConfirmAsync(this,shell,"Start or refresh local router?","Save your work and close Codex before confirming. If saved files require it, the worker restarts only the owned local router. Reachability does not verify upstream access.",()=>shell.ExecuteMutationAsync(RouterStudio.Core.Contracts.StudioRequest.Create("start",new{ack=true})));
 }
 private async void RepairConnection(object sender,RoutedEventArgs e) {
  if(!shell.CanRepair)return;
  await ManagementInteraction.ConfirmAsync(this,shell,"Adopt verified local connection?","The worker verifies the known localhost endpoint and credential variable, then updates the switcher's saved state. Your current Codex settings are kept. Unexpected endpoints or extra headers are refused.",()=>shell.ExecuteMutationAsync(RouterStudio.Core.Contracts.StudioRequest.Create("repair")));
 }
 private void UpdateRefreshTimer() {
  shell.IsWindowVisible=IsVisible && WindowState!=WindowState.Minimized;
  if(shell.IsWindowVisible && shell.CurrentPage is StudioPage.Dashboard or StudioPage.Connections) refreshTimer.Start();else refreshTimer.Stop();
 }
 private void Changed(object? sender,PropertyChangedEventArgs e) {
  if(e.PropertyName==nameof(ShellViewModel.CurrentPage)) {ShowPage();UpdateRefreshTimer();}
  if(e.PropertyName==nameof(ShellViewModel.Theme)) ThemeManager.Apply(shell.Theme);
  if(e.PropertyName==nameof(ShellViewModel.DiagnosticsOpen) && shell.DiagnosticsOpen) Dispatcher.BeginInvoke(()=>CloseDiagnosticsButton.Focus());
  if(e.PropertyName==nameof(ShellViewModel.DiagnosticsOpen) && !shell.DiagnosticsOpen) RefreshButton.Focus();
 }
 private void SystemChanged(object? sender,PropertyChangedEventArgs e) => Dispatcher.Invoke(()=>ThemeManager.Apply(shell.Theme));
 private void PreferenceChanged(object sender,UserPreferenceChangedEventArgs e) => Dispatcher.Invoke(()=>ThemeManager.Apply(shell.Theme));
 private void ShowPage() {
  if(!pages.TryGetValue(shell.CurrentPage,out var page)) {page=shell.CurrentPage switch {
   StudioPage.Dashboard=>new DashboardView(),StudioPage.Connections=>new ConnectionsView(),
   StudioPage.ModelsRoutes=>new ModelsRoutesView(),StudioPage.Keys=>new KeysView(),StudioPage.TestLab=>new TestLabView(),
   StudioPage.Backups=>new BackupsView(),StudioPage.Settings=>new SettingsView(),_=>new DashboardView()}; pages.Add(shell.CurrentPage,page);}
  PageHost.Content=page; PageScroll.ScrollToTop();
 }
}
