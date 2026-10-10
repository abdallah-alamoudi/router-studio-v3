using System.Text.Json;using RouterStudio.Core.Contracts;using RouterStudio.Core.Services;using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Core.Tests;
[TestClass] public sealed class TestLabViewModelTests {
 private sealed class Backend:IStudioBackend {
  public int Calls;public bool Slow;public StudioRequest? LastRequest;public StudioSnapshot Snapshot=new(){SnapshotDigest=new string('a',64),Keys=["PRO"],Models=[new(){Id="heavy",Credential="PRO",Saved=true,Kind="Preset",SupportedReasoningLevels=["high"]}]};
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct)=>Task.FromResult(Snapshot);
  public async Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct){Calls++;LastRequest=request;
   if(request.Action=="preview-probe")return new(1,true,JsonSerializer.SerializeToElement(new{kind="stream",modelId="heavy",resolvedModel="raw",credentialLabel="PRO",effort="high",outputTokenLimit=256,endpointName="8stoken",snapshotDigest=new string('a',64)}),null);
   if(Slow)try{await Task.Delay(Timeout.Infinite,ct);}catch(OperationCanceledException){return StudioResult.Failure("cancelled");}
   return new(1,true,JsonSerializer.SerializeToElement(new{kind="stream",modelId="heavy",credentialLabel="PRO",endpointName="8stoken",outcome="passed",elapsedMs=2,firstEventMs=1,completedAtUtc=DateTimeOffset.UtcNow,snapshotDigest=new string('a',64)}),null);
  }
 }
 [TestMethod] public async Task OpeningLabSendsNoRequestAndPreviewShowsEffectiveRoute() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.Navigate(StudioPage.TestLab);Assert.AreEqual(0,backend.Calls);
  shell.TestLab.Kind=ProbeKind.Stream;shell.TestLab.SelectedModel="heavy";await shell.TestLab.PreviewAsync();
  Assert.IsTrue(shell.TestLab.PreviewText.Contains("raw"));Assert.IsTrue(shell.TestLab.PreviewText.Contains("PRO"));Assert.IsTrue(shell.TestLab.PreviewText.Contains("high"));Assert.IsTrue(shell.TestLab.PreviewText.Contains("charge",StringComparison.OrdinalIgnoreCase));
 }
 [TestMethod] public async Task RunRequiresAcknowledgementAndSelectionInvalidatesPreview() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.TestLab.Kind=ProbeKind.Stream;shell.TestLab.SelectedModel="heavy";await shell.TestLab.PreviewAsync();await shell.TestLab.RunAsync(false);Assert.AreEqual(1,backend.Calls);
  shell.TestLab.OutputTokenLimit=512;Assert.IsFalse(shell.TestLab.CanRun);await shell.TestLab.RunAsync(true);Assert.AreEqual(1,backend.Calls);
 }
 [TestMethod] public async Task OnlyOneProbeRunsBlocksMutationAndCancelNeverReportsPassed() {
  var backend=new Backend{Slow=true};var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.TestLab.Kind=ProbeKind.Stream;shell.TestLab.SelectedModel="heavy";await shell.TestLab.PreviewAsync();
  var running=shell.TestLab.RunAsync(true);Assert.IsTrue(shell.IsBusy);Assert.IsTrue(shell.TestLab.Running);await shell.TestLab.RunAsync(true);await shell.ExecuteMutationAsync(StudioRequest.Create("official"));Assert.AreEqual(2,backend.Calls);
  shell.TestLab.Cancel();await running;Assert.IsFalse(shell.IsBusy);Assert.IsFalse(shell.TestLab.ResultText.Contains("Passed"));Assert.IsTrue(shell.TestLab.ResultText.Contains("Cancelled"));
 }
 [TestMethod] public async Task FinishedProbeReachesDashboardAndSnapshotChangeIsStale() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.TestLab.Kind=ProbeKind.Stream;shell.TestLab.SelectedModel="heavy";await shell.TestLab.PreviewAsync();await shell.TestLab.RunAsync(true);
  Assert.AreEqual("Passed",shell.Dashboard.State.LastProbeState);backend.Snapshot=backend.Snapshot with {SnapshotDigest=new string('b',64)};await shell.RefreshAsync();Assert.AreEqual("Stale",shell.Dashboard.State.LastProbeState);
 }
 [TestMethod] public async Task InvalidModelCapDoesNotTrapNonmodelChecks() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();
  foreach(var cap in new[]{0,2049}){
   shell.TestLab.Kind=ProbeKind.Stream;shell.TestLab.SelectedModel="heavy";shell.TestLab.OutputTokenLimit=cap;Assert.IsFalse(shell.TestLab.CanPreview);
   foreach(var kind in new[]{ProbeKind.Local,ProbeKind.OfficialConfig,ProbeKind.Catalog}){
    shell.TestLab.Kind=kind;shell.TestLab.SelectedCredential="PRO";Assert.IsTrue(shell.TestLab.CanPreview);
    await shell.TestLab.PreviewAsync();Assert.AreEqual(256,backend.LastRequest!.Payload.GetProperty("outputTokenLimit").GetInt32());
   }
  }
 }
}
