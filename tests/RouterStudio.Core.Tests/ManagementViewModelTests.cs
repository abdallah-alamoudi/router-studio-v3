using System.Text;
using System.Text.Json;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class ManagementViewModelTests {
 private static StudioSnapshot Snapshot()=>new(){SnapshotDigest=new string('a',64),Connection=new(){Selected="router",CanAdopt=true},Models=[new(){Id="raw",Name="Raw model",Kind="Raw model",Credential="PLUS",Saved=true,SupportedReasoningLevels=["medium"]},new(){Id="8s-heavy",Kind="Preset",Credential="PRO",Saved=false}],Keys=["PLUS","PRO"],Backups=[new(){Id="123456-abcdef.toml"}]};
 [TestMethod] public async Task ModelSearchFiltersDeclaredCapabilitiesWithoutBackendCalls() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();
  shell.ModelsRoutes.Search="RAW";Assert.AreEqual("raw",shell.ModelsRoutes.FilteredModels.Single().Id);
  shell.ModelsRoutes.Search="";shell.ModelsRoutes.Filter="Missing key";Assert.AreEqual("8s-heavy",shell.ModelsRoutes.FilteredModels.Single().Id);
  shell.ModelsRoutes.Filter="All";shell.ModelsRoutes.SelectedModel=shell.ModelsRoutes.FilteredModels.First();
  Assert.IsTrue(shell.ModelsRoutes.Details.Contains("medium"));Assert.IsTrue(shell.ModelsRoutes.Details.Contains("Declared"));Assert.AreEqual(0,backend.Requests.Count);
 }
 [TestMethod] public async Task KeyPreviewLabelEditInvalidatesApplyAndCancelledApplyDoesNothing() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.Keys.Label="CHINESE";
  await shell.Keys.PreviewAsync(["raw"]);Assert.IsTrue(shell.Keys.CanApply);Assert.IsTrue(shell.Keys.PreviewText.Contains("CHINESE"));
  using var secret=new SecretInput(Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-ui-key"}"""));
  await shell.Keys.ApplyAsync(secret,false);Assert.AreEqual(1,backend.Requests.Count);
  shell.Keys.Label="OTHER";Assert.IsFalse(shell.Keys.CanApply);await shell.Keys.ApplyAsync(secret,true);Assert.AreEqual(1,backend.Requests.Count);
 }
 [TestMethod] public async Task ConfirmedKeyApplyCarriesPreviewGuardAndClearPreview() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.Keys.Label="CHINESE";
  await shell.Keys.PreviewAsync(["raw"]);
  using var secret=new SecretInput(Encoding.UTF8.GetBytes("""{"label":"CHINESE","key":"fake-ui-key"}"""));await shell.Keys.ApplyAsync(secret,true);
  var request=backend.Requests.Last();Assert.AreEqual("save-key",request.Action);Assert.AreEqual(new string('b',64),request.Payload.GetProperty("expectedPreviewDigest").GetString());
  Assert.IsTrue(request.Payload.GetProperty("ack").GetBoolean());Assert.IsFalse(request.Payload.GetRawText().Contains("fake-ui-key"));Assert.IsFalse(shell.Keys.CanApply);Assert.IsTrue(shell.CodexRestartRequired);
 }
 [TestMethod] public async Task BackupSelectionInvalidatesPreviewAndOnlyConfirmedRestoreRuns() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.Backups.SelectedBackup=shell.Backups.Items.Single();
  await shell.Backups.PreviewAsync();Assert.IsTrue(shell.Backups.CanRestore);await shell.Backups.RestoreAsync(false);Assert.AreEqual(1,backend.Requests.Count);
  await shell.Backups.RestoreAsync(true);Assert.AreEqual("restore",backend.Requests.Last().Action);Assert.AreEqual(new string('b',64),backend.Requests.Last().Payload.GetProperty("expectedPreviewDigest").GetString());
  shell.Backups.SelectedBackup=null;Assert.IsFalse(shell.Backups.CanRestore);
 }
 [TestMethod] public async Task SnapshotChangesInvalidatePreviewsAndBusyBlocksOtherActions() {
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();shell.Keys.Label="CHINESE";await shell.Keys.PreviewAsync(["raw"]);
  backend.Snapshot=backend.Snapshot with {SnapshotDigest=new string('c',64)};await shell.RefreshAsync();Assert.IsFalse(shell.Keys.CanApply);
  backend.Pending=new();var action=shell.ExecuteMutationAsync(StudioRequest.Create("repair"));
  Assert.IsFalse(shell.Keys.CanPreview);Assert.IsFalse(shell.CanStartRouter);await shell.Keys.PreviewAsync(["raw"]);Assert.AreEqual(2,backend.Requests.Count);
  backend.Pending.SetResult(Result(backend.Snapshot));await action;Assert.IsFalse(shell.IsBusy);
 }
 private static StudioResult Result(object data)=>new(1,true,JsonSerializer.SerializeToElement(data,new JsonSerializerOptions(JsonSerializerDefaults.Web)),null);
 private sealed class Backend:IStudioBackend {
  public StudioSnapshot Snapshot=ManagementViewModelTests.Snapshot();public List<StudioRequest> Requests=[];public TaskCompletionSource<StudioResult>? Pending;
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct)=>Task.FromResult(Snapshot);
  public Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct){
   Requests.Add(request);if(Pending is not null)return Pending.Task;
   return Task.FromResult(request.Action switch {
    "preview-routes"=>Result(new{previewDigest=new string('b',64),snapshotDigest=Snapshot.SnapshotDigest,changes=new[]{new{modelId="raw",kind="Raw model",beforeCredential="PLUS",afterCredential="CHINESE"}}}),
    "preview-backup"=>Result(new{previewDigest=new string('b',64),snapshotDigest=Snapshot.SnapshotDigest,changes=new[]{new{field="model",before="Absent",after="Configured"}}}),
    _=>Result(Snapshot)
   });
  }
 }
}
