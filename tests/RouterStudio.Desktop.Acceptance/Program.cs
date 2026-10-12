using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop;
using RouterStudio.Desktop.Presentation;
using RouterStudio.Desktop.Views.Components;
namespace RouterStudio.Desktop.Acceptance;
internal static class Program {
 private static readonly List<string> checks=[];
 private static string output="";
 [STAThread] private static int Main(string[] args) {
  output=Path.GetFullPath(args.Single()); Directory.CreateDirectory(output);
  var app=new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};
  foreach(var name in new[]{"Colors","Typography","Controls"}) app.Resources.MergedDictionaries.Add(new(){Source=new Uri($"pack://application:,,,/RouterStudio.Desktop;component/Resources/{name}.xaml")});
  app.Resources.Add("BoolVisibility",new BooleanToVisibilityConverter());
  var bindingErrors=new BindingErrors(); PresentationTraceSources.DataBindingSource.Listeners.Add(bindingErrors);
  MainWindow? window=null;
  try {
   ThemeManager.Apply(ThemePreference.Light); var backend=new FixtureBackend(); var vm=new ShellViewModel(backend);
   window=new MainWindow(vm){Width=960,Height=640}; window.Show(); Pump();
   Check(window.IsVisible && window.ActualWidth>=960 && window.ActualHeight>=640,"Native window opens at minimum size");
   var nav=(ListBox)window.FindName("NavigationList"); var host=(ContentControl)window.FindName("PageHost");
   Check(nav.Items.Count==7,"Seven destinations");
   for(int i=0;i<7;i++) {nav.SelectedIndex=i; Pump(); Check(host.Content is UserControl page && page.IsVisible && page.ActualWidth>300,$"Rendered destination {i+1}");}
   var last=(ListBoxItem)nav.ItemContainerGenerator.ContainerFromIndex(6);
   Check(last.TransformToAncestor(nav).TransformBounds(new Rect(last.RenderSize)).Bottom<=nav.ActualHeight,"All navigation destinations fit minimum height");
   Check(backend.Reads==0 && backend.Actions==0,"Navigation has no backend or provider calls");
   var refresh=(Button)window.FindName("RefreshButton");
   window.Activate(); refresh.Focus(); Pump();
   Check(Keyboard.FocusedElement==refresh,"Refresh accepts native keyboard focus");
   Check(refresh.MoveFocus(new TraversalRequest(FocusNavigationDirection.Next)),"Tab traversal reaches another control");
   Check(window.InputBindings.Count==10 && window.InputBindings.OfType<KeyBinding>().Any(k=>k.Key==Key.Escape),"Navigation, refresh and diagnostics shortcuts registered");
   backend.NextSnapshot=DashboardFixture();vm.RefreshAsync().GetAwaiter().GetResult();Pump();
   vm.Navigate(StudioPage.Dashboard);Pump();
   var dashboard=(UserControl)host.Content;
   Check(dashboard.FindName("ConfiguredModel") is TextBlock model && model.Text=="deepseek-v4.1-flash","Dashboard displays configured model from worker snapshot");
   Check(dashboard.FindName("AuthenticationState") is TextBlock auth && auth.Text=="Not verified","Configured provider does not imply authentication");
   Capture(window,"dashboard-light-100.png",96);
   vm.Navigate(StudioPage.Connections);Pump();var connections=(UserControl)host.Content;
   Check(connections.FindName("RouterButton") is Button routerButton && routerButton.IsEnabled,"Connection selection enabled after local read");
   TestConnectionDialog(window,(Button)connections.FindName("RouterButton"),false);Check(backend.Actions==0,"Cancelled selection makes no mutation");
   TestConnectionDialog(window,(Button)connections.FindName("RouterButton"),true);PumpUntil(()=>!vm.IsBusy);
   Check(backend.Actions==1 && vm.CodexRestartRequired && vm.Dashboard.State.ConfiguredProvider=="8stoken router","Confirmed switch updates configured state and restart reminder");
   Capture(window,"connections-light-200.png",192);
   var pageScroll=(ScrollViewer)window.FindName("PageScroll");pageScroll.ScrollToBottom();Pump();
   Check(pageScroll.VerticalOffset>0 && ((Button)connections.FindName("RouterButton")).ActualWidth>0,"Connection actions reachable by scrolling");
   Capture(window,"connections-bottom-200.png",192);
   vm.Navigate(StudioPage.Dashboard);Pump();Capture(window,"dashboard-light-200.png",192);
   pageScroll.ScrollToBottom();Pump();Capture(window,"dashboard-bottom-200.png",192);
   backend.NextSnapshot=DashboardFixture() with {Connection=new(){Selected="router",ReviewNeeded=true},Models=[],RestartRequired=true};
   vm.RefreshAsync().GetAwaiter().GetResult();Pump();Capture(window,"dashboard-review-200.png",192);
   Check(vm.Dashboard.State.ReviewState=="Review needed" && vm.Dashboard.State.CatalogState=="Missing" && !vm.Connections.CanSelect,"Review and missing catalog shown; unsafe switch disabled");
   backend.NextSnapshot=DashboardFixture();vm.RefreshAsync().GetAwaiter().GetResult();Pump();
   Check(vm.CodexRestartRequired,"Restart reminder survives later local refresh");
   var readsBeforeTick=backend.Reads;PumpUntil(()=>backend.Reads>readsBeforeTick,20);
   Check(!vm.IsBusy,"Visible dashboard timer completes local refresh");
   window.WindowState=WindowState.Minimized;Pump();Check(!vm.IsWindowVisible,"Minimized window suspends local timer eligibility");
   window.WindowState=WindowState.Normal;Pump();
   backend.NextSnapshot=DashboardFixture() with {Credentials=[new(){Id="cred-fixture",Label="مفتاح تجريبي",Saved=true,CatalogModels=[new(){Id="original-fixture"}]}]};
   vm.RefreshAsync().GetAwaiter().GetResult();Pump();var beforeManagement=backend.Actions;
   vm.Navigate(StudioPage.Keys);Pump();var keysPage=(UserControl)host.Content;
   var savedCredentials=(ListBox)keysPage.FindName("SavedCredentialList");savedCredentials.SelectedIndex=0;Pump();
   Check(vm.SavedCredentials.Selected?.Id=="cred-fixture","Native credential selection uses stable identity");
   TestConnectionDialog(window,VisualDescendants<Button>(keysPage).Single(b=>Equals(b.Content,"Fetch selected key catalog…")),false);
   Check(backend.Actions==beforeManagement,"Cancelled credential fetch makes no backend or provider call");
   vm.Navigate(StudioPage.ModelsRoutes);Pump();var customPage=(UserControl)host.Content;
   var credentialSelector=VisualDescendants<ComboBox>(customPage).Single(c=>System.Windows.Automation.AutomationProperties.GetName(c)=="Custom model credential");credentialSelector.SelectedIndex=0;Pump();
   var originalSelector=VisualDescendants<ComboBox>(customPage).Single(c=>System.Windows.Automation.AutomationProperties.GetName(c)=="Original provider model");originalSelector.SelectedIndex=0;
   vm.CustomModels.DisplayLabel="Custom fixture";Pump();
   Check(vm.CustomModels.CanSave && vm.CustomModels.SelectedOriginal?.Id=="original-fixture","Native custom-model selection uses selected credential catalog");
   TestConnectionDialog(window,VisualDescendants<Button>(customPage).Single(b=>Equals(b.Content,"Save custom model…")),false);
   Check(backend.Actions==beforeManagement,"Cancelled custom-model save makes no backend call");
   Capture(window,"custom-models-200.png",192);
   backend.NextSnapshot=DashboardFixture();vm.RefreshAsync().GetAwaiter().GetResult();Pump();
   vm.Navigate(StudioPage.TestLab);Pump();var lab=(UserControl)host.Content;
   var beforeLab=backend.Actions;vm.TestLab.Kind=ProbeKind.Stream;vm.TestLab.SelectedModel="deepseek-v4.1-flash";
   ((Button)lab.FindName("PreviewProbeButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));PumpUntil(()=>!vm.IsBusy);
   Check(vm.TestLab.CanRun&&vm.TestLab.PreviewText.Contains("PLUS"),"Native test preview displays assigned key");
   Check(bindingErrors.Errors.Count==0,"No binding errors before deliberate invalid input");
   PresentationTraceSources.DataBindingSource.Listeners.Remove(bindingErrors);
   var outputLimit=(TextBox)lab.FindName("OutputLimit");outputLimit.Text="invalid";Pump();
   Check(Validation.GetHasError(outputLimit),"Invalid output cap produces a binding validation error");
   Check(!((Button)lab.FindName("PreviewProbeButton")).IsEnabled&&!((Button)lab.FindName("RunProbeButton")).IsEnabled,"Invalid visible cap disables preview and run");
   ((CheckBox)lab.FindName("ProbeAcknowledgement")).IsChecked=true;
   ((Button)lab.FindName("RunProbeButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));Pump();
   Check(backend.Actions==beforeLab+1,"Invalid visible cap cannot run using previous numeric value");
   outputLimit.Text="256";Pump();((CheckBox)lab.FindName("ProbeAcknowledgement")).IsChecked=false;
   PresentationTraceSources.DataBindingSource.Listeners.Add(bindingErrors);
   Check(((Button)lab.FindName("RunProbeButton")).IsEnabled,"Corrected numeric cap restores controls");
   ((Button)lab.FindName("RunProbeButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));Pump();Check(backend.Actions==beforeLab+1,"Run without acknowledgement sends no probe");
   ((CheckBox)lab.FindName("ProbeAcknowledgement")).IsChecked=true;((Button)lab.FindName("RunProbeButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));PumpUntil(()=>!vm.IsBusy);
   Check(vm.TestLab.ResultText.Contains("Passed")&&vm.Dashboard.State.LastProbeState=="Passed","Native acknowledged probe result reaches dashboard");
   outputLimit.Text="0";Pump();Check(!((Button)lab.FindName("PreviewProbeButton")).IsEnabled,"Out-of-range model cap disables preview");
   vm.TestLab.Kind=ProbeKind.Local;Pump();Check(!outputLimit.IsEnabled&&((Button)lab.FindName("PreviewProbeButton")).IsEnabled,"Local checks remain available after invalid model cap");
   vm.TestLab.Kind=ProbeKind.OfficialConfig;Pump();Check(((Button)lab.FindName("PreviewProbeButton")).IsEnabled,"Official configuration check ignores model-only cap");
   vm.TestLab.Kind=ProbeKind.Stream;outputLimit.Text="256";Pump();
   Capture(window,"test-lab-light-200.png",192);pageScroll.ScrollToBottom();Pump();Capture(window,"test-lab-bottom-200.png",192);
   vm.Navigate(StudioPage.ModelsRoutes);Pump();var modelPage=(UserControl)host.Content;
   Check(modelPage.FindName("ModelsList") is ListBox modelList && modelList.Items.Count==1,"Native model list consumes snapshot");
   ((TextBox)modelPage.FindName("ModelSearch")).Text="missing-model";Pump();Check(vm.ModelsRoutes.FilteredModels.Count==0,"Native search filters model list");
   ((TextBox)modelPage.FindName("ModelSearch")).Text="";Pump();
   Capture(window,"models-light-200.png",192);
   pageScroll.ScrollToBottom();Pump();Capture(window,"models-bottom-200.png",192);
   vm.Navigate(StudioPage.Keys);Pump();var keyPage=(UserControl)host.Content;
   ((TextBox)keyPage.FindName("CredentialLabel")).Text="CHINESE";
   ((ListBox)keyPage.FindName("RawModels")).SelectedIndex=0;Pump();
   ((Button)keyPage.FindName("PreviewRoutesButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));PumpUntil(()=>!vm.IsBusy);
   Check(vm.Keys.CanApply && vm.Keys.PreviewText.Contains("CHINESE"),"Native route preview shows mapping before applying");
   var password=(PasswordBox)keyPage.FindName("KeyPassword");password.Password="fake-native-key";
   var actionsBeforeCancel=backend.Actions;TestConnectionDialog(window,(Button)keyPage.FindName("ApplyKeyButton"),false);
   Check(password.Password.Length==0 && backend.Actions==actionsBeforeCancel,"Cancelled key submission clears password and makes no mutation");
   password.Password="fake-native-key";TestConnectionDialog(window,(Button)keyPage.FindName("ApplyKeyButton"),true);PumpUntil(()=>!vm.IsBusy);
   Check(password.Password.Length==0 && backend.SawSecret,"Confirmed key submission clears password and uses secret channel");
   Capture(window,"keys-light-200.png",192);
   pageScroll.ScrollToBottom();Pump();Capture(window,"keys-bottom-200.png",192);
   vm.Navigate(StudioPage.Backups);Pump();var backupPage=(UserControl)host.Content;
   ((ListBox)backupPage.FindName("BackupsList")).SelectedIndex=0;Pump();
   ((Button)backupPage.FindName("PreviewBackupButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));PumpUntil(()=>!vm.IsBusy);
   Check(vm.Backups.CanRestore && vm.Backups.PreviewText.Contains("model"),"Native backup preview enables guarded restore");
   TestConnectionDialog(window,(Button)backupPage.FindName("RestoreBackupButton"),true);PumpUntil(()=>!vm.IsBusy);
   Check(backend.LastAction=="restore","Confirmed native restore uses worker contract");Capture(window,"backups-light-200.png",192);
   pageScroll.ScrollToBottom();Pump();Capture(window,"backups-bottom-200.png",192);
   vm.DiagnosticsOpen=true;Pump();var start=(Button)window.FindName("StartRouterButton");
   var beforeStart=backend.Actions;TestConnectionDialog(window,start,false);Check(backend.Actions==beforeStart,"Cancelled diagnostic start makes no mutation");
   TestConnectionDialog(window,start,true);PumpUntil(()=>!vm.IsBusy);Check(backend.LastAction=="start","Confirmed diagnostic start invokes guarded worker action");
   backend.NextSnapshot=DashboardFixture() with {Connection=new(){Selected="router",CanAdopt=true}};vm.RefreshAsync().GetAwaiter().GetResult();Pump();
   TestConnectionDialog(window,(Button)window.FindName("RepairConnectionButton"),true);PumpUntil(()=>!vm.IsBusy);Check(backend.LastAction=="repair","Verified repair control invokes adoption action");
   vm.DiagnosticsOpen=false;vm.Theme=ThemePreference.Dark;vm.Navigate(StudioPage.Keys);Pump();pageScroll.ScrollToBottom();Pump();Capture(window,"keys-dark-bottom-200.png",192);
   vm.Navigate(StudioPage.Dashboard);Pump(); Capture(window,"dashboard-dark-150.png",144);
   Check(window.Background is SolidColorBrush canvas && canvas.Color==Color.FromRgb(16,23,36),"Dark window backdrop follows theme");
   Check(((SolidColorBrush)app.FindResource("CanvasBrush")).Color==Color.FromRgb(16,23,36),"Dark theme updates resources");
   vm.Navigate(StudioPage.Settings); Pump(); Capture(window,"settings-dark-200.png",192);
   var settings=(UserControl)host.Content;
   var setupPlus=(PasswordBox)settings.FindName("SetupPlus");var setupPro=(PasswordBox)settings.FindName("SetupPro");
   setupPlus.Password="fake-native-initial-plus";setupPro.Password="fake-native-initial-pro";
   var beforeSetup=backend.Actions;TestConnectionDialog(window,(Button)settings.FindName("InstallRouterButton"),false);
   Check(setupPlus.Password.Length==0&&setupPro.Password.Length==0&&backend.Actions==beforeSetup,"Cancelled first setup clears keys and leaves configuration alone");
   setupPlus.Password="fake-native-initial-plus";TestConnectionDialog(window,(Button)settings.FindName("InstallRouterButton"),true);PumpUntil(()=>!vm.IsBusy);
   Check(backend.LastAction=="install"&&backend.SawSecret&&!vm.HasError,"First setup uses encrypted channel and refreshes returned local status");
   var darkPicker=(ComboBox)settings.FindName("ThemePicker");
   Check(Contrast(((SolidColorBrush)darkPicker.Foreground).Color,Pixel(darkPicker,3,20))>=4.5,"Dark selector text contrast meets 4.5:1");
   var picker=(ComboBox)settings.FindName("ThemePicker"); picker.SelectedItem=ThemePreference.Light; Pump();
   Check(vm.Theme==ThemePreference.Light,"Settings theme selection updates shell");
   var scroll=(ScrollViewer)window.FindName("PageScroll");
   Check(scroll.ScrollableHeight>0,"Long settings page scrolls at minimum size");
   scroll.ScrollToBottom(); Pump(); Check(scroll.VerticalOffset>0,"Bottom settings content reachable");
   app.Resources.MergedDictionaries.Add(new(){Source=new Uri("pack://application:,,,/RouterStudio.Desktop;component/Resources/Themes/HighContrast.xaml")});
   Pump(); Capture(window,"high-contrast-palette.png",96);
   Check(((SolidColorBrush)app.FindResource("TextBrush")).Color==SystemColors.WindowTextColor,"High contrast palette uses Windows text color");
   ThemeManager.Apply(ThemePreference.Light);
   backend.NextSnapshot=null;
   ((IInvokeProvider)new ButtonAutomationPeer(refresh).GetPattern(PatternInterface.Invoke)).Invoke(); Pump();
   Check(vm.IsBusy && !refresh.IsEnabled,"Busy state disables local refresh");
   nav.SelectedIndex=3; Pump(); Check(vm.CurrentPage==StudioPage.Keys,"Navigation stays usable while busy");
   Capture(window,"loading-state.png",96);
   backend.Pending.SetException(new IOException("fake-private-key")); PumpUntil(()=>!vm.IsBusy);
   Check(vm.HasError && vm.DiagnosticsOpen && !vm.ErrorMessage!.Contains("fake-private-key"),"Failure shows safe error and diagnostics");
   var errorPanel=VisualDescendants<ErrorState>(window).Single();
   var details=VisualDescendants<Button>(errorPanel).Single();
   Check(ReferenceEquals(details.Command,vm.OpenDiagnosticsCommand),"Error panel binds its open-only diagnostics command");
   var detailsInvoke=(IInvokeProvider)new ButtonAutomationPeer(details).GetPattern(PatternInterface.Invoke);
   detailsInvoke.Invoke();Pump();Check(vm.DiagnosticsOpen,"Actual error details button leaves automatically opened diagnostics open");
   vm.CloseDiagnosticsCommand.Execute(null);Pump();Check(!vm.DiagnosticsOpen,"Error drawer can still close");
   detailsInvoke.Invoke();Pump();Check(vm.DiagnosticsOpen,"Actual error details button opens closed diagnostics");
   for(var repeat=0;repeat<3;repeat++){detailsInvoke.Invoke();Pump();Check(vm.DiagnosticsOpen,"Repeated error details activation keeps diagnostics open");}
   var f8=window.InputBindings.OfType<KeyBinding>().Single(binding=>binding.Key==Key.F8);
   Check(ReferenceEquals(f8.Command,vm.DiagnosticsCommand),"F8 retains the general diagnostics toggle command");
   f8.Command.Execute(null);Pump();Check(!vm.DiagnosticsOpen,"F8 command closes an open drawer");
   f8.Command.Execute(null);Pump();Check(vm.DiagnosticsOpen,"F8 command opens a closed drawer");
   var drawer=((Grid)window.Content).Children.OfType<Border>().Last();
   refresh.Focus(); Pump();
   var refreshBounds=refresh.TransformToAncestor(window).TransformBounds(new Rect(refresh.RenderSize));
   var drawerBounds=drawer.TransformToAncestor(window).TransformBounds(new Rect(drawer.RenderSize));
   Check(Keyboard.FocusedElement==refresh && !refreshBounds.IntersectsWith(drawerBounds),"Open diagnostics leaves keyboard focus visible");
   Check(refresh.IsEnabled,"Refresh recovers after failure"); Capture(window,"error-diagnostics.png",96);
   Check(vm.Dashboard.State.StatusOutdated && !vm.Connections.CanSelect,"Failed local read invalidates dashboard and switching");
   vm.CloseDiagnosticsCommand.Execute(null); Pump(); Check(!vm.DiagnosticsOpen,"Diagnostics close command works");
   TestDialog(window,false); TestDialog(window,true);
   var beforeHide=backend.Actions;vm.Settings.CloseToTray=true;window.Close();Pump();
   Check(!window.IsVisible&&!vm.IsExiting&&backend.Actions==beforeHide,"Close to tray hides without stopping router or exiting");
   window.Restore();Pump();Check(window.IsVisible,"Tray restore returns the same window");vm.Settings.CloseToTray=false;
   Check(bindingErrors.Errors.Count==0,"No runtime binding errors");
   File.WriteAllText(Path.Combine(output,"acceptance.json"),JsonSerializer.Serialize(new {result="PASS",checks,scope="Current-user native WPF fixture; rendered 96/144/192 DPI images; programmatic native focus and UI Automation invokes; OS DPI/theme and human keyboard checks pending."},new JsonSerializerOptions{WriteIndented=true}));
   Console.WriteLine($"PASS native acceptance: {checks.Count} checks"); return 0;
  } catch(Exception ex) {
   File.WriteAllText(Path.Combine(output,"failure.txt"),ex.ToString()+"\n"+string.Join("\n",bindingErrors.Errors));
   Console.Error.WriteLine("FAIL native acceptance: "+ex.Message); return 1;
  } finally {window?.Close(); app.Shutdown();}
 }
 private static void Check(bool ok,string name) {if(!ok)throw new InvalidOperationException(name); checks.Add(name);}
 private static IEnumerable<T> VisualDescendants<T>(DependencyObject parent) where T:DependencyObject {
  for(var index=0;index<VisualTreeHelper.GetChildrenCount(parent);index++){
   var child=VisualTreeHelper.GetChild(parent,index);if(child is T match)yield return match;
   foreach(var descendant in VisualDescendants<T>(child))yield return descendant;
  }
 }
 private static void Pump(){Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);}
 private static void PumpUntil(Func<bool> done,int timeoutSeconds=10) {
  var watch=Stopwatch.StartNew(); while(!done() && watch.Elapsed<TimeSpan.FromSeconds(timeoutSeconds)) {Pump();Thread.Sleep(5);}
  Pump(); Check(done(),"Action completes within acceptance timeout");
 }
 private static void TestDialog(Window owner,bool confirm) {
  var dialog=new ConfirmationDialog("Review this change","This fixture changes no configuration. Cancel is the safe default."){Owner=owner};
  dialog.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,()=> {
   Check(((Button)dialog.FindName("CancelButton")).IsDefault && ((Button)dialog.FindName("CancelButton")).IsCancel,"Confirmation defaults to Cancel");
   Check(Keyboard.FocusedElement==((Button)dialog.FindName("CancelButton")),"Confirmation focuses Cancel");
   Capture(dialog,confirm?"confirm-dialog.png":"cancel-dialog.png",192);
   var target=confirm?((Button)dialog.FindName("ConfirmButton")):((Button)dialog.FindName("CancelButton"));
   ((IInvokeProvider)new ButtonAutomationPeer(target).GetPattern(PatternInterface.Invoke)).Invoke();
  });
  Check(dialog.ShowDialog()==confirm,confirm?"Explicit confirmation accepted":"Cancel leaves action unconfirmed");
 }
 private static StudioSnapshot DashboardFixture()=>new(){
  Connection=new(){Selected="official",Provider="openai",Model="deepseek-v4.1-flash",Endpoint="Official ChatGPT sign-in"},
  SnapshotDigest=new string('a',64),CheckedAtUtc=DateTimeOffset.UtcNow,
  Models=[new(){Id="deepseek-v4.1-flash",Kind="Raw model",Credential="PLUS",HasExplicitRoute=true,Saved=false}],Keys=["PLUS"],Backups=[new(){Id="123456-abcdef.toml",Date=DateTimeOffset.UtcNow}],
  RuntimeVersions=new(){Node="v24.21.0",PowerShell="7.6.6"}
 };
 private static void TestConnectionDialog(Window owner,Button button,bool confirm) {
  owner.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,()=>{
   var dialog=Application.Current.Windows.OfType<ConfirmationDialog>().Single();
   var target=(Button)dialog.FindName(confirm?"ConfirmButton":"CancelButton");
   Check(((Button)dialog.FindName("CancelButton")).IsDefault,"Connection preview defaults to Cancel");
   ((IInvokeProvider)new ButtonAutomationPeer(target).GetPattern(PatternInterface.Invoke)).Invoke();
  });
  button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));Pump();
 }
 private static void Capture(Window window,string filename,double dpi) {
  window.UpdateLayout(); var visual=(FrameworkElement)window.Content;
  var margin=visual.Margin; var width=visual.ActualWidth+margin.Left+margin.Right; var height=visual.ActualHeight+margin.Top+margin.Bottom;
  var bitmap=new RenderTargetBitmap((int)Math.Ceiling(width*dpi/96),(int)Math.Ceiling(height*dpi/96),dpi,dpi,PixelFormats.Pbgra32);
  var drawing=new DrawingVisual(); using(var context=drawing.RenderOpen()) { context.DrawRectangle(window.Background,null,new Rect(0,0,width,height)); context.DrawRectangle(new VisualBrush(visual),null,new Rect(margin.Left,margin.Top,visual.ActualWidth,visual.ActualHeight)); } bitmap.Render(drawing); var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
  using var file=File.Create(Path.Combine(output,filename)); encoder.Save(file);
 }
 private static Color Pixel(FrameworkElement element,int x,int y) {
  var visual=new DrawingVisual();using(var context=visual.RenderOpen())context.DrawRectangle(new VisualBrush(element),null,new Rect(element.RenderSize));
  var bitmap=new RenderTargetBitmap((int)element.ActualWidth,(int)element.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);
  byte[] pixel=new byte[4];bitmap.CopyPixels(new Int32Rect(x,y,1,1),pixel,4,0);return Color.FromRgb(pixel[2],pixel[1],pixel[0]);
 }
 private static double Contrast(Color a,Color b) {
  static double Channel(byte c){double v=c/255.0;return v<=0.04045?v/12.92:Math.Pow((v+0.055)/1.055,2.4);}
  static double Luminance(Color c)=>0.2126*Channel(c.R)+0.7152*Channel(c.G)+0.0722*Channel(c.B);
  var x=Luminance(a);var y=Luminance(b);return (Math.Max(x,y)+0.05)/(Math.Min(x,y)+0.05);
 }
 private sealed class FixtureBackend:IStudioBackend {
  public StudioSnapshot? NextSnapshot;
  public bool SawSecret;public string LastAction="";
  public int Reads,Actions;public TaskCompletionSource<StudioSnapshot> Pending {get;}=new();
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct){Reads++;return NextSnapshot is null?Pending.Task:Task.FromResult(NextSnapshot);}
  public Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct){
   Actions++;LastAction=request.Action;SawSecret|=secret is not null;
   object data=request.Action switch {
    "preview-probe"=>new{kind="stream",modelId="deepseek-v4.1-flash",resolvedModel="deepseek-v4.1-flash",credentialLabel="PLUS",outputTokenLimit=256,endpointName="8stoken",snapshotDigest=new string('a',64)},
    "probe"=>new{kind="stream",modelId="deepseek-v4.1-flash",credentialLabel="PLUS",endpointName="8stoken",outcome="passed",elapsedMs=2,firstEventMs=1,completedAtUtc=DateTimeOffset.UtcNow,snapshotDigest=new string('a',64)},
    "preview-routes"=>new{previewDigest=new string('b',64),snapshotDigest=new string('a',64),changes=new[]{new{modelId="deepseek-v4.1-flash",kind="Raw model",beforeCredential="PLUS",afterCredential="CHINESE"}}},
    "preview-backup"=>new{previewDigest=new string('b',64),snapshotDigest=new string('a',64),changes=new[]{new{field="model",before="Absent",after="Configured"}}},
    "install"=>new{message="Fixture setup finished"},
    _=>DashboardFixture() with {Connection=new(){Selected=request.Action is "official" or "router"?request.Action:"router",Model="deepseek-v4.1-flash",Responses=true,Endpoint="http://127.0.0.1:18761/v1"}}
   };
   return Task.FromResult(new StudioResult(1,true,JsonSerializer.SerializeToElement(data,new JsonSerializerOptions(JsonSerializerDefaults.Web)),null));
  }
 }
 private sealed class BindingErrors:TraceListener {
  public List<string> Errors {get;}=[];
  public override void Write(string? message){if(message?.Contains("Error",StringComparison.Ordinal)==true)Errors.Add(message);}
  public override void WriteLine(string? message)=>Write(message);
 }
}
