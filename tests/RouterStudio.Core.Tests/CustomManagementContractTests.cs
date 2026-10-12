using System.Reflection;
using System.Text;
using System.Text.Json;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
namespace RouterStudio.Core.Tests;
[TestClass]
public sealed class CustomManagementContractTests
{
 private const string Digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
 private static string? Validate(StudioRequest request, SecretInput? secret = null) => (string?)typeof(WorkerBackend).Assembly.GetType("RouterStudio.Core.Services.RequestPolicy")!.GetMethod("Validate", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, [request, secret]);
 private static StudioRequest Request(string action, object payload) => StudioRequest.Create(action, payload);
 private static SecretInput Secret(string json) => new(Encoding.UTF8.GetBytes(json));
 [TestMethod] public void NewActionsAcceptOnlyTheirExplicitContracts()
 {
  using var create = Secret("{\"credentialId\":\"cred-1\",\"key\":\"fake-contract-key\"}");
  foreach(var action in new[]{"save-credential","rotate-credential"}) {
   object payload = action=="save-credential" ? new {credentialId="cred-1",label="مفتاح شخصي",ack=true,expectedSnapshotDigest=Digest} : new {credentialId="cred-1",ack=true,expectedSnapshotDigest=Digest};
   Assert.IsNull(Validate(Request(action,payload),create),action);
  }
  Assert.IsNull(Validate(Request("rename-credential",new{credentialId="cred-1",label="Personal key",ack=true,expectedSnapshotDigest=Digest})));
  foreach(var action in new[]{"delete-credential","delete-custom-model"}) {
   object payload=action=="delete-credential" ? new{credentialId="cred-1",ack=true,expectedSnapshotDigest=Digest} : new{customModelId="custom-1",ack=true,expectedSnapshotDigest=Digest};
   Assert.IsNull(Validate(Request(action,payload)),action);
  }
  Assert.IsNull(Validate(Request("fetch-credential-catalog",new{credentialId="cred-1",acknowledgement=true,expectedSnapshotDigest=Digest})));
  Assert.IsNull(Validate(Request("save-custom-model",new{customModelId="custom-1",credentialId="cred-1",originalModel="provider/model-v1",displayLabel="نموذج خاص",ack=true,expectedSnapshotDigest=Digest})));
 }
 [TestMethod] public void SecretIdentityMustMatchAndNoOtherActionMayReceiveSecret()
 {
  using var secret=Secret("{\"credentialId\":\"other\",\"key\":\"fake-contract-key\"}");
  Assert.AreEqual("invalid_request",Validate(Request("save-credential",new{credentialId="cred-1",label="Personal",ack=true,expectedSnapshotDigest=Digest}),secret));
  Assert.AreEqual("invalid_request",Validate(Request("rename-credential",new{credentialId="cred-1",label="Personal",ack=true,expectedSnapshotDigest=Digest}),secret));
  Assert.AreEqual("invalid_key",Validate(Request("rotate-credential",new{credentialId="cred-1",ack=true,expectedSnapshotDigest=Digest})));
 }
 [TestMethod] public void PublicPayloadRejectsSecretsPathsMetadataAndDuplicateProperties()
 {
  foreach(var extra in new[]{"key","keyEnv","endpoint","metadata","supportedReasoningLevels","force"}) {
   var payload=JsonSerializer.Deserialize<JsonElement>("{\"credentialId\":\"cred-1\",\"ack\":true,\"expectedSnapshotDigest\":\""+Digest+"\",\""+extra+"\":\"bad\"}");
   Assert.AreEqual("invalid_request",Validate(new(1,"delete-credential",payload)),extra);
  }
  var duplicate=JsonSerializer.Deserialize<JsonElement>("{\"credentialId\":\"cred-1\",\"credentialId\":\"other\",\"ack\":true,\"expectedSnapshotDigest\":\""+Digest+"\"}");
  Assert.AreEqual("invalid_request",Validate(new(1,"delete-credential",duplicate)));
 }
 [TestMethod] public void IdentityLabelModelAndSnapshotInputsAreBounded()
 {
  foreach(var id in new[]{"../secret","",new string('a',81),"cred\n"})
   Assert.AreEqual("invalid_request",Validate(Request("delete-credential",new{credentialId=id,ack=true,expectedSnapshotDigest=Digest})));
  foreach(var label in new[]{"", " padded", "trailing ", "unsafe\nlabel",new string('a',81)})
   Assert.AreEqual("invalid_request",Validate(Request("rename-credential",new{credentialId="cred-1",label,ack=true,expectedSnapshotDigest=Digest})));
  Assert.AreEqual("invalid_request",Validate(Request("save-custom-model",new{customModelId="custom-1",credentialId="cred-1",originalModel="model\n",displayLabel="Test",ack=true,expectedSnapshotDigest=Digest})));
  Assert.AreEqual("invalid_request",Validate(Request("delete-credential",new{credentialId="cred-1",ack=true})));
  Assert.AreEqual("invalid_request",Validate(Request("delete-credential",new{credentialId="cred-1",ack=true,expectedSnapshotDigest=Digest+"\n"})));
 }
 [TestMethod] public void CatalogFetchAndMutationsRequireExplicitAcknowledgement()
 {
  Assert.AreEqual("acknowledgement_required",Validate(Request("fetch-credential-catalog",new{credentialId="cred-1",expectedSnapshotDigest=Digest})));
  Assert.AreEqual("acknowledgement_required",Validate(Request("delete-credential",new{credentialId="cred-1",ack=false,expectedSnapshotDigest=Digest})));
  Assert.AreEqual("invalid_request",Validate(Request("fetch-credential-catalog",new{credentialId="cred-1",acknowledgement="true",expectedSnapshotDigest=Digest})));
 }
 [TestMethod] public void NewActionsAreClassifiedAsMutationsIncludingCatalogPersistence()
 {
  var method=typeof(WorkerBackend).Assembly.GetType("RouterStudio.Core.Services.RequestPolicy")!.GetMethod("IsMutation",BindingFlags.Static|BindingFlags.NonPublic)!;
  foreach(var action in new[]{"save-credential","rotate-credential","rename-credential","delete-credential","fetch-credential-catalog","save-custom-model","delete-custom-model"})
   Assert.IsTrue((bool)method.Invoke(null,[action])!,action);
 }
}
