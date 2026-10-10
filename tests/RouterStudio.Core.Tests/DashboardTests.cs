using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class DashboardTests {
 private static StudioSnapshot Snapshot(string digest="abc", string selected="official") => new() {
  SnapshotDigest=digest, CheckedAtUtc=new(2026,10,6,9,0,0,TimeSpan.Zero),
  Connection=new(){Selected=selected,Provider=selected=="official"?"openai":"safe_8stoken",Model="example-model",Endpoint="Official ChatGPT sign-in"},
  Models=[new(){Id="preset",HasExplicitRoute=true,Saved=true},new(){Id="raw",Saved=false}],Keys=["PLUS"],
  RuntimeVersions=new(){Node="v24.21.0",PowerShell="7.6.6"}
 };
 [TestMethod] public void ConfiguredIsNotAuthenticated() {
  var state=DashboardComposer.Compose(Snapshot());
  Assert.AreEqual("Official ChatGPT",state.ConfiguredProvider); Assert.AreEqual("example-model",state.ConfiguredModel);
  Assert.AreEqual("Not verified",state.AuthenticationState); Assert.AreEqual("Not tested",state.LastProbeState);
 }
 [TestMethod] public void RouterDownDoesNotMeanSubscriptionDown() {
  var state=DashboardComposer.Compose(Snapshot());
  Assert.AreEqual("Unreachable",state.RouterState);Assert.AreEqual("Not verified",state.AuthenticationState);
  Assert.AreEqual("Official ChatGPT",state.ConfiguredProvider);
 }
 [TestMethod] public void ChangedSnapshotMarksResultStale() {
  var probe=new ProbeResult(ProbeKind.Responses,"example-model","PLUS","8stoken",ProbeOutcome.Passed,null,200,10,null,DateTimeOffset.UtcNow,"abc");
  Assert.AreEqual("Passed",DashboardComposer.Compose(Snapshot(),probe).LastProbeState);
  Assert.AreEqual("Stale",DashboardComposer.Compose(Snapshot("changed"),probe).LastProbeState);
  Assert.AreEqual("Stale",DashboardComposer.Compose(Snapshot(),probe,true).LastProbeState);
  Assert.AreEqual("Stale",DashboardComposer.Compose(Snapshot(""),probe).LastProbeState);
 }
 [TestMethod] public void ReviewMissingKeyAndCatalogAreDistinct() {
  var state=DashboardComposer.Compose(Snapshot() with {Connection=new(){Selected="router",ReviewNeeded=true},Models=[]});
  Assert.AreEqual("Review needed",state.ReviewState);Assert.AreEqual("Missing",state.CatalogState);
  Assert.AreEqual(1,DashboardComposer.Compose(Snapshot()).MissingCredentialCount);
  Assert.AreEqual(1,DashboardComposer.Compose(Snapshot()).RouteCount);
  Assert.AreEqual(2,DashboardComposer.Compose(Snapshot()).ModelCount);
  Assert.AreEqual(1,DashboardComposer.Compose(Snapshot()).CredentialCount);
  Assert.AreEqual("Unknown",DashboardComposer.Compose(null).RouterState);
  Assert.IsFalse(DashboardComposer.Compose(null).CountsAvailable);
  Assert.IsTrue(DashboardComposer.Compose(Snapshot()).CountsAvailable);
 }
 [TestMethod] public void ReachabilityDoesNotProveLoadedConfiguration() {
  Assert.AreEqual("Loaded configuration unknown",DashboardComposer.Compose(Snapshot() with {RouterHealth=new(){Reachable=true}}).RouterConfigurationState);
  Assert.AreEqual("Restart required",DashboardComposer.Compose(Snapshot() with {RestartRequired=true}).RouterConfigurationState);
 }
 [TestMethod] public async Task RefreshDoesNotProbe() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();
  Assert.AreEqual("example-model",shell.Dashboard.State.ConfiguredModel);Assert.AreEqual(0,backend.Actions.Count);
  Assert.IsTrue(shell.Connections.CanSelect);Assert.AreEqual("Not tested",shell.Dashboard.State.LastProbeState);
 }
 [TestMethod] public async Task NoOverlappingRefresh() {
  var backend=new Backend {Pending=new()};var shell=new ShellViewModel(backend){IsWindowVisible=true};
  var first=shell.RefreshAsync();await shell.TimerTickAsync();await shell.RefreshAsync();
  Assert.AreEqual(1,backend.Reads);Assert.IsFalse(shell.Connections.CanSelect);
  backend.Pending.SetResult(Snapshot());await first;Assert.IsTrue(shell.Connections.CanSelect);
 }
 [TestMethod] public async Task HiddenWindowSuspendsTimer() {
  var backend=new Backend();var shell=new ShellViewModel(backend);
  await shell.TimerTickAsync();Assert.AreEqual(0,backend.Reads);
  shell.IsWindowVisible=true;await shell.TimerTickAsync();Assert.AreEqual(1,backend.Reads);
  shell.Navigate(StudioPage.Keys);await shell.TimerTickAsync();Assert.AreEqual(1,backend.Reads);
  shell.Navigate(StudioPage.Connections);await shell.TimerTickAsync();Assert.AreEqual(2,backend.Reads);
  shell.IsWindowVisible=false;await shell.TimerTickAsync();Assert.AreEqual(2,backend.Reads);
  shell.IsWindowVisible=true;shell.IsConfirmationOpen=true;await shell.TimerTickAsync();Assert.AreEqual(2,backend.Reads);
 }
 [TestMethod] public async Task FailedRefreshInvalidatesPreviousStatusAndDisablesSwitching() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();
  backend.Fail=true;await shell.RefreshAsync();Assert.IsTrue(shell.Dashboard.State.StatusOutdated);
  Assert.IsFalse(shell.Connections.CanSelect);Assert.AreEqual("Not verified",shell.Dashboard.State.AuthenticationState);
 }
 [TestMethod] public async Task SwitchRequiresConfirmationAndKeepsRestartReminder() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();
  await shell.SelectConnectionAsync("router",false);Assert.AreEqual(0,backend.Actions.Count);
  await shell.SelectConnectionAsync("router",true);Assert.AreEqual("router",backend.Actions.Single().Action);
  Assert.IsTrue(backend.Actions.Single().Payload.GetProperty("ack").GetBoolean());
  Assert.IsTrue(shell.CodexRestartRequired);Assert.AreEqual("8stoken router",shell.Dashboard.State.ConfiguredProvider);
  await shell.RefreshAsync();Assert.IsTrue(shell.CodexRestartRequired);
 }
 [TestMethod] public async Task ReviewStateBlocksSwitchAndMutationFailureRequiresFreshRead() {
  var backend=new Backend {Next=Snapshot() with {Connection=new(){ReviewNeeded=true}}};var shell=new ShellViewModel(backend);
  await shell.RefreshAsync();await shell.SelectConnectionAsync("official",true);Assert.AreEqual(0,backend.Actions.Count);
  backend.Next=Snapshot();await shell.RefreshAsync();backend.MutationFailure=true;
  await shell.SelectConnectionAsync("router",true);Assert.IsFalse(shell.Connections.CanSelect);
  Assert.IsTrue(shell.CodexRestartRequired);Assert.IsTrue(shell.HasError);Assert.IsFalse(shell.ErrorMessage!.Contains("fake-key"));
 }
 private sealed class Backend:IStudioBackend {
  public StudioSnapshot Next=Snapshot();public int Reads;public bool Fail,MutationFailure;
  public TaskCompletionSource<StudioSnapshot>? Pending;public List<StudioRequest> Actions=[];
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct){Reads++;return Fail?Task.FromException<StudioSnapshot>(new IOException("fake-key")):Pending?.Task??Task.FromResult(Next);}
  public Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct){
   Actions.Add(request);if(MutationFailure)return Task.FromResult(new StudioResult(1,false,null,new("startup_failed","fake-key")));
   return Task.FromResult(new StudioResult(1,true,System.Text.Json.JsonSerializer.SerializeToElement(Snapshot(selected:request.Action),new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web)),null));
  }
 }
}
