using System.Text;
using System.Text.Json;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Core.Tests;
[TestClass] public sealed class CustomManagementViewModelTests {
 [TestMethod] public async Task CredentialFlowUsesIdentityNoSecretInPublicPayloadAndExplicitConfirmation(){
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();var vm=shell.SavedCredentials;vm.Label="مفتاح";
  using var secret=new SecretInput(Encoding.UTF8.GetBytes("{}"));await vm.SaveAsync(secret,false);Assert.AreEqual(0,backend.Requests.Count);
  var id=vm.NewCredentialId;await vm.SaveAsync(secret,true);Assert.AreEqual("save-credential",backend.Requests.Last().Action);Assert.AreEqual(id,backend.Requests.Last().Payload.GetProperty("credentialId").GetString());Assert.AreNotEqual(id,vm.NewCredentialId);Assert.IsFalse(backend.Requests.Last().Payload.TryGetProperty("key",out _));
  vm.Selected=vm.Items.Single();vm.Label="Renamed";await vm.RenameAsync(true);Assert.AreEqual("rename-credential",backend.Requests.Last().Action);
  await vm.FetchAsync(false);Assert.AreEqual(2,backend.Requests.Count);await vm.FetchAsync(true);Assert.AreEqual("fetch-credential-catalog",backend.Requests.Last().Action);Assert.IsTrue(backend.Requests.Last().Payload.GetProperty("acknowledgement").GetBoolean());
 }
 [TestMethod] public async Task CustomModelUsesOnlyExplicitStoredCatalogAndDoesNotInferEffort(){
  var backend=new Backend();var shell=new ShellViewModel(backend);await shell.RefreshAsync();var vm=shell.CustomModels;
  vm.SelectedCredential=vm.Credentials.Single();vm.DisplayLabel="Custom";await vm.SaveAsync(true);Assert.AreEqual(0,backend.Requests.Count);
  vm.SelectedOriginal=vm.SelectedCredential.CatalogModels.Single();await vm.SaveAsync(false);Assert.AreEqual(0,backend.Requests.Count);await vm.SaveAsync(true);
  var p=backend.Requests.Single().Payload;Assert.AreEqual("cred-1",p.GetProperty("credentialId").GetString());Assert.AreEqual("original",p.GetProperty("originalModel").GetString());Assert.IsFalse(p.TryGetProperty("effort",out _));Assert.IsFalse(p.TryGetProperty("metadata",out _));
 }
 [TestMethod] public async Task ManagementChangesRetainCodexRestartReminder()
 {
  foreach(var action in new[]{"save-credential","rotate-credential","rename-credential","delete-credential","fetch-credential-catalog","save-custom-model","delete-custom-model"}) {
   var shell=new ShellViewModel(new Backend());await shell.RefreshAsync();
   await shell.RunRequestAsync(StudioRequest.Create(action),mutation:true);
   Assert.IsTrue(shell.CodexRestartRequired,action);
   await shell.RefreshAsync();Assert.IsTrue(shell.CodexRestartRequired,action+" after refresh");
  }
 }
 private sealed class Backend:IStudioBackend {
  public List<StudioRequest> Requests=[];
  private readonly StudioSnapshot snapshot=new(){SnapshotDigest=new string('a',64),Credentials=[new(){Id="cred-1",Label="Existing",Saved=true,CatalogModels=[new(){Id="original",SupportedReasoningLevels=["medium"]}]}]};
  public Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct)=>Task.FromResult(snapshot);
  public Task<StudioResult> ExecuteAsync(StudioRequest request,SecretInput? secret,CancellationToken ct){Requests.Add(request);return Task.FromResult(new StudioResult(1,true,JsonSerializer.SerializeToElement(snapshot,new JsonSerializerOptions(JsonSerializerDefaults.Web)),null));}
 }
}
