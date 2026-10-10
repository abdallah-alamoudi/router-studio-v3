using Microsoft.VisualStudio.TestTools.UnitTesting;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class ShellViewModelTests
{
 [TestMethod] public void NavigationDoesNotCallProbe() {
  var backend = new ControlledBackend(); var shell = new ShellViewModel(backend);
  foreach(var page in Enum.GetValues<StudioPage>()) { shell.Navigate(page); Assert.AreEqual(page,shell.CurrentPage); }
  Assert.AreEqual(0,backend.Actions.Count); Assert.AreEqual(0,backend.Reads);
 }
 [TestMethod] public async Task BusyMutationDisablesConflictingCommands() {
  var backend = new ControlledBackend(); var shell = new ShellViewModel(backend);
  var running = shell.ExecuteMutationAsync(StudioRequest.Create("stop"));
  Assert.IsTrue(shell.IsBusy); Assert.IsFalse(shell.CanMutate);
  shell.Navigate(StudioPage.Settings); Assert.AreEqual(StudioPage.Settings,shell.CurrentPage);
  await shell.ExecuteMutationAsync(StudioRequest.Create("start")); await shell.RefreshAsync();
  Assert.AreEqual(1,backend.Actions.Count); Assert.AreEqual("stop",backend.Actions[0]); Assert.AreEqual(0,backend.Reads);
  backend.Pending.SetResult(new(1,true,null,null)); await running;
  Assert.IsFalse(shell.IsBusy); Assert.IsTrue(shell.CanMutate);
 }
 [TestMethod] public async Task BackendFailureLeavesNavigationUsable() {
  var backend = new ControlledBackend { FailRead = true }; var shell = new ShellViewModel(backend);
  await shell.RefreshAsync();
  Assert.IsNotNull(shell.ErrorMessage); Assert.IsFalse(shell.ErrorMessage.Contains("fake-private-key"));
  Assert.IsFalse(shell.IsBusy); shell.Navigate(StudioPage.Keys);
  Assert.AreEqual(StudioPage.Keys,shell.CurrentPage); Assert.IsTrue(shell.CanMutate);
 }
 [TestMethod] public async Task FailedMutationReleasesBusyAndUsesSafeError() {
  var backend = new ControlledBackend(); var shell = new ShellViewModel(backend);
  var running = shell.ExecuteMutationAsync(StudioRequest.Create("stop"));
  backend.Pending.SetResult(new(1,false,null,new("worker_failed","fake-private-key"))); await running;
  Assert.IsNotNull(shell.ErrorMessage); Assert.IsFalse(shell.ErrorMessage.Contains("fake-private-key"));
  Assert.IsFalse(shell.IsBusy);
 }
 [TestMethod] public async Task ErrorDetailsOpensClosedDrawerAndNeverClosesOpenDrawer() {
  var backend=new ControlledBackend{FailRead=true};var shell=new ShellViewModel(backend);
  await shell.RefreshAsync();Assert.IsTrue(shell.DiagnosticsOpen);
  var message=shell.ErrorMessage;var code=shell.DiagnosticCode;
  shell.OpenDiagnosticsCommand.Execute(null);Assert.IsTrue(shell.DiagnosticsOpen);
  shell.CloseDiagnosticsCommand.Execute(null);Assert.IsFalse(shell.DiagnosticsOpen);
  for(var i=0;i<3;i++){shell.OpenDiagnosticsCommand.Execute(null);Assert.IsTrue(shell.DiagnosticsOpen);}
  Assert.AreEqual(message,shell.ErrorMessage);Assert.AreEqual(code,shell.DiagnosticCode);
  Assert.AreEqual(1,backend.Reads);Assert.AreEqual(0,backend.Actions.Count);
 }
 [TestMethod] public void DiagnosticsToggleAndCloseRetainExistingBehavior() {
  var shell=new ShellViewModel(new ControlledBackend());
  shell.DiagnosticsCommand.Execute(null);Assert.IsTrue(shell.DiagnosticsOpen);
  shell.DiagnosticsCommand.Execute(null);Assert.IsFalse(shell.DiagnosticsOpen);
  shell.DiagnosticsCommand.Execute(null);shell.CloseDiagnosticsCommand.Execute(null);Assert.IsFalse(shell.DiagnosticsOpen);
  shell.CloseDiagnosticsCommand.Execute(null);Assert.IsFalse(shell.DiagnosticsOpen);
 }
 private sealed class ControlledBackend : IStudioBackend {
  public List<string> Actions {get;}=[]; public int Reads; public bool FailRead;
  public TaskCompletionSource<StudioResult> Pending {get;}=new(TaskCreationOptions.RunContinuationsAsynchronously);
  public Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct) { Actions.Add(request.Action); return Pending.Task; }
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct) {
   Reads++; if(FailRead) throw new IOException("fake-private-key");
   return Task.FromResult(new StudioSnapshot());
  }
 }
}
