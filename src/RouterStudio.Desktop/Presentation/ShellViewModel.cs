using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using System.Text.Json;
namespace RouterStudio.Desktop.Presentation;
public enum StudioPage { Dashboard, Connections, ModelsRoutes, Keys, TestLab, Backups, Settings }
public enum ThemePreference { System, Light, Dark }
public sealed record NavigationItem(StudioPage Page,string Label,string Symbol);
public sealed class ShellViewModel : ObservableObject {
 public DashboardViewModel Dashboard {get;}=new();
 public ConnectionsViewModel Connections {get;}=new();
 public ModelsRoutesViewModel ModelsRoutes {get;}=new();
 public KeysViewModel Keys {get;}
 public BackupsViewModel Backups {get;}
 public TestLabViewModel TestLab {get;}
 public SettingsViewModel Settings{get;private set;}
 public void ConfigureSettings(UserSettingsStore store,StartupPreferences startup,string? appCommand,string? routerCommand)=>Settings=new(this,store,startup,appCommand,routerCommand);
 private readonly HistoryStore? history;
 public string ActivityText=>history is null?"No local history store configured.":string.Join("\n",history.Read().Take(10).Select(row=>$"{row.AtUtc.LocalDateTime:g} · {row.Action} · {(row.Probe?.Outcome.ToString()??(row.Ok?"Finished":"Needs attention"))}{(snapshot is null||row.SnapshotDigest!=snapshot.SnapshotDigest?" · Stale":"")}"));
 public string? HistoryNotice=>history?.Notice;
 public void ClearHistory(){if(IsBusy)return;history?.Clear();NotifyHistory();}
 public string ExportDiagnostics()=>history?.Export(snapshot)??"{\"schemaVersion\":1,\"activities\":[],\"scope\":\"No local history configured\"}";
 private void NotifyHistory(){Notify(nameof(ActivityText));Notify(nameof(HistoryNotice));}
 public bool StatusAvailable=>snapshot is not null && !statusOutdated && !IsBusy && !IsExiting;
 public bool IsExiting{get;private set;}
 public string TrayText=>$"{Dashboard.State.ConfiguredProvider} · {Dashboard.State.RouterState}";
 public void BeginExit(){IsExiting=true;TestLab.Cancel();Notify(nameof(IsExiting));Notify(nameof(CanMutate));RefreshCommand.NotifyCanExecuteChanged();UpdateState();}
 public Task WaitForIdleAsync(){if(!IsBusy)return Task.CompletedTask;var ready=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);System.ComponentModel.PropertyChangedEventHandler? listener=null;listener=(_,e)=>{if(e.PropertyName==nameof(IsBusy)&&!IsBusy){PropertyChanged-=listener;ready.TrySetResult();}};PropertyChanged+=listener;if(!IsBusy){PropertyChanged-=listener;ready.TrySetResult();}return ready.Task;}
 public string SnapshotDigest=>snapshot?.SnapshotDigest??"";
 public bool CanStartRouter=>StatusAvailable;
 public bool CanRepair=>StatusAvailable && snapshot!.Connection.CanAdopt;
 public bool IsWindowVisible {get;set;}
 public bool IsConfirmationOpen {get;set;}
 private StudioSnapshot? snapshot;
 private ProbeResult? lastProbe;
 private bool statusOutdated,codexRestartRequired;
 public bool CodexRestartRequired {get=>codexRestartRequired;private set=>Set(ref codexRestartRequired,value);}
 public Task TimerTickAsync()=>IsWindowVisible && !IsBusy && !IsConfirmationOpen && CurrentPage is StudioPage.Dashboard or StudioPage.Connections ? RefreshAsync() : Task.CompletedTask;
 public Task SelectConnectionAsync(string selection,bool confirmed) {
  if(!confirmed || !Connections.CanSelect || selection is not ("official" or "router")) return Task.CompletedTask;
  return ExecuteMutationAsync(StudioRequest.Create(selection,selection=="router" ? new {ack=true} : (object?)null));
 }
 public void RecordProbeResult(ProbeResult result) {lastProbe=result;history?.AppendProbe(result);NotifyHistory();UpdateState();}
 private void UpdateState() {
  Dashboard.Update(DashboardComposer.Compose(snapshot,lastProbe,statusOutdated));
  Connections.Update(snapshot,snapshot is not null && !statusOutdated && !snapshot.Connection.ReviewNeeded && !IsBusy&&!IsExiting);
  ModelsRoutes.Update(snapshot?.Models??[]);
  Keys.Update(snapshot,StatusAvailable && !snapshot!.Connection.ReviewNeeded);
  Backups.Update(snapshot,StatusAvailable);
  TestLab.Update(snapshot,StatusAvailable);
  NotifyHistory();
  Notify(nameof(TrayText));
  Notify(nameof(StatusAvailable));Notify(nameof(CanStartRouter));Notify(nameof(CanRepair));
 }
 private readonly IStudioBackend backend;
 private StudioPage currentPage;
 private bool isBusy,diagnosticsOpen;
 private string? errorMessage;
 private string diagnosticCode="none",statusText="○ Local status not checked";
 private ThemePreference theme;
 public ShellViewModel(IStudioBackend backend,HistoryStore? history=null) {
  this.backend=backend;
  this.history=history;
  Keys=new(this);Backups=new(this);TestLab=new(this);Settings=new(this);
  RefreshCommand=new(RefreshAsync,()=>!IsBusy&&!IsExiting);
  NavigateCommand=new(p=>{ if(p is StudioPage page) Navigate(page); });
  DiagnosticsCommand=new(_=>DiagnosticsOpen=!DiagnosticsOpen);
  OpenDiagnosticsCommand=new(_=>DiagnosticsOpen=true);
  CloseDiagnosticsCommand=new(_=>DiagnosticsOpen=false);
 }
 public IReadOnlyList<NavigationItem> Navigation {get;}=[
  new(StudioPage.Dashboard,"Dashboard","◈"),new(StudioPage.Connections,"Connections","⇄"),
  new(StudioPage.ModelsRoutes,"Models & Routes","≡"),new(StudioPage.Keys,"Keys","◇"),
  new(StudioPage.TestLab,"Test Lab","▷"),new(StudioPage.Backups,"Backups","↶"),
  new(StudioPage.Settings,"Settings","⚙")];
 public StudioPage CurrentPage { get=>currentPage; set=>Navigate(value); }
 public string PageTitle => Navigation.First(n=>n.Page==CurrentPage).Label;
 public bool IsBusy {get=>isBusy;private set { if(Set(ref isBusy,value)) {Notify(nameof(CanMutate)); RefreshCommand.NotifyCanExecuteChanged();UpdateState();} }}
 public bool CanMutate=>!IsBusy&&!IsExiting;
 public string? ErrorMessage {get=>errorMessage;private set {if(Set(ref errorMessage,value)) Notify(nameof(HasError));}}
 public bool HasError=>ErrorMessage is not null;
 public string DiagnosticCode {get=>diagnosticCode;private set=>Set(ref diagnosticCode,value);}
 public string StatusText {get=>statusText;private set=>Set(ref statusText,value);}
 public bool DiagnosticsOpen {get=>diagnosticsOpen;set=>Set(ref diagnosticsOpen,value);}
 public ThemePreference Theme {get=>theme;set=>Set(ref theme,value);}
 public IReadOnlyList<ThemePreference> Themes {get;}=Enum.GetValues<ThemePreference>();
 public AsyncCommand RefreshCommand {get;}
 public DelegateCommand NavigateCommand {get;}
 public DelegateCommand DiagnosticsCommand {get;}
 public DelegateCommand OpenDiagnosticsCommand {get;}
 public DelegateCommand CloseDiagnosticsCommand {get;}
 public void Navigate(StudioPage page) {
  if(!Enum.IsDefined(page)) return;
  if(Set(ref currentPage,page,nameof(CurrentPage))) Notify(nameof(PageTitle));
 }
 public async Task RefreshAsync() {
  if(IsBusy||IsExiting) return; IsBusy=true; ErrorMessage=null;
  try { snapshot=await backend.GetSnapshotAsync(CancellationToken.None);statusOutdated=false; DiagnosticCode="none"; StatusText="✓ Local status read · provider access untested"; }
  catch(StudioBackendException ex) { Fail(ex.Error.Code); }
  catch(Exception) { Fail("operation_failed"); }
  finally {IsBusy=false;}
 }
 public async Task ExecuteMutationAsync(StudioRequest request) {await RunRequestAsync(request,null,true);}
 public Task<StudioResult> RunProbeAsync(ProbeRequest request,CancellationToken ct)=>RunRequestAsync(StudioRequest.Create("probe",request),ct:ct);
 public async Task<StudioResult> RunRequestAsync(StudioRequest request,SecretInput? secret=null,bool mutation=false,CancellationToken ct=default) {
  if(IsBusy||IsExiting) return StudioResult.Failure("busy"); IsBusy=true; ErrorMessage=null;
  // A mutation can commit before a later status/startup failure. Do not retain verification during it.
  if(mutation){statusOutdated=true;UpdateState();}
  if(mutation && request.Action is "official" or "router" or "restore" or "save-key" or "start") CodexRestartRequired=true;
  try { var result=await backend.ExecuteAsync(request,secret,ct);
   if(mutation&&ProbeCodec.Digest(SnapshotDigest))history?.AppendAction(request.Action,result.Ok,SnapshotDigest);
   if(!result.Ok) Fail(result.Error?.Code ?? "operation_failed");
   else {
    if(mutation && result.Data is { } data) {
     snapshot=request.Action=="install"?await backend.GetSnapshotAsync(CancellationToken.None):data.Deserialize<StudioSnapshot>(new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web)) ?? throw new InvalidOperationException();
     statusOutdated=false;
    }
    DiagnosticCode="none"; StatusText=mutation?"✓ Action finished · review local status and restart guidance":"✓ Preview ready · no changes applied";
   }
   return result;
  } catch(StudioBackendException ex) {Fail(ex.Error.Code);return StudioResult.Failure(ex.Error.Code);} catch(Exception) {Fail("operation_failed");return StudioResult.Failure("operation_failed");}
  finally {IsBusy=false;}
 }
 public void ReportInvalidPreview()=>Fail("invalid_result");
 private void Fail(string code) {
  statusOutdated=true;UpdateState();
  var safe=StudioErrors.Get(code); ErrorMessage=safe.Message; DiagnosticCode=safe.Code;
  StatusText="! Local action needs attention"; DiagnosticsOpen=true;
 }
}
