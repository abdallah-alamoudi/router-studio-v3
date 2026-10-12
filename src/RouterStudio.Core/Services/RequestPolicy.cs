using System.Text.Json;
using System.Text.RegularExpressions;
using RouterStudio.Core.Contracts;
namespace RouterStudio.Core.Services;
internal static class RequestPolicy
{
 private static readonly Regex Label = new("^[A-Za-z][A-Za-z0-9_]{0,39}$",RegexOptions.CultureInvariant);
 private static readonly Regex Model = new("^[A-Za-z0-9][A-Za-z0-9_./:-]{0,159}$",RegexOptions.CultureInvariant);
 private static readonly Regex Backup = new(@"^\d{1,20}-[a-f0-9]{6}\.toml$",RegexOptions.CultureInvariant);
 private static readonly Regex Digest = new("^[a-f0-9]{64}$",RegexOptions.CultureInvariant);
 private static readonly Regex Identity = new(@"\A[A-Za-z][A-Za-z0-9._:-]{0,79}\z",RegexOptions.CultureInvariant);
 private static readonly Regex ExactModel = new(@"\A[A-Za-z0-9][A-Za-z0-9_./:-]{0,159}\z",RegexOptions.CultureInvariant);
 private static readonly Regex ExactDigest = new(@"\A[a-f0-9]{64}\z",RegexOptions.CultureInvariant);
 internal static bool IsCustomManagement(string action) => action is "save-credential" or "rotate-credential" or "rename-credential" or "delete-credential" or "fetch-credential-catalog" or "save-custom-model" or "delete-custom-model";
 internal static bool IsMutation(string action) => IsCustomManagement(action) || action is "install" or "official" or "router" or "start" or "stop" or "repair" or "restore" or "save-key";
 internal static string? Validate(StudioRequest request,SecretInput? secret)
 {
  if(request.SchemaVersion != 1) return "unsupported_schema";
  if(request.Payload.ValueKind != JsonValueKind.Object || request.Payload.GetRawText().Length > 65536) return "invalid_request";
  var allowed = request.Action switch {
   "status" or "official" or "repair" or "install" => Array.Empty<string>(),
   "router" or "start" or "stop" => ["ack"],
   "restore" => ["id","ack","expectedPreviewDigest"],
   "preview-backup" => ["id"],
   "preview-routes" => ["label","ids"],
   "save-key" => ["label","ids","ack","expectedPreviewDigest"],
   "save-credential" or "rename-credential" => ["credentialId","label","ack","expectedSnapshotDigest"],
   "rotate-credential" or "delete-credential" => ["credentialId","ack","expectedSnapshotDigest"],
   "fetch-credential-catalog" => ["credentialId","acknowledgement","expectedSnapshotDigest"],
   "save-custom-model" => ["customModelId","credentialId","originalModel","displayLabel","ack","expectedSnapshotDigest"],
   "delete-custom-model" => ["customModelId","ack","expectedSnapshotDigest"],
   "probe" or "preview-probe" => ["kind","modelId","credentialLabel","outputTokenLimit","expectedSnapshotDigest","acknowledgement"],
   _ => null
  };
  if(allowed is null) return "invalid_request";
  var names = new HashSet<string>(StringComparer.Ordinal);
  foreach(var property in request.Payload.EnumerateObject())
   if(!names.Add(property.Name) || !allowed.Contains(property.Name,StringComparer.Ordinal))return "invalid_request";
  var p=request.Payload;
  if(p.TryGetProperty("expectedPreviewDigest",out _) && !Text(p,"expectedPreviewDigest",Digest))return "invalid_request";
  if(p.TryGetProperty("ack",out var ack) && ack.ValueKind is not (JsonValueKind.True or JsonValueKind.False))return "invalid_request";
  if(request.Action=="stop"&&(!p.TryGetProperty("ack",out ack)||ack.ValueKind!=JsonValueKind.True))return "acknowledgement_required";
  if(request.Action is "restore" or "preview-backup")
   if(!Text(p,"id",Backup))return "invalid_request";
  if(request.Action == "restore" && (!p.TryGetProperty("ack",out ack) || ack.ValueKind!=JsonValueKind.True))return "acknowledgement_required";
  if(request.Action is "save-key" or "preview-routes") {
   if(!Text(p,"label",Label) || !p.TryGetProperty("ids",out var ids) || ids.ValueKind != JsonValueKind.Array || ids.GetArrayLength()>500)return "invalid_request";
   foreach(var id in ids.EnumerateArray())if(id.ValueKind!=JsonValueKind.String || !Model.IsMatch(id.GetString()!) || id.GetString()!.StartsWith("8s-",StringComparison.Ordinal))return "invalid_request";
   if(request.Action=="save-key" && (!p.TryGetProperty("ack",out ack) || ack.ValueKind!=JsonValueKind.True))return "acknowledgement_required";
  }
  if(request.Action is "probe" or "preview-probe") {
   if(!p.TryGetProperty("kind",out var kind) || kind.ValueKind!=JsonValueKind.String || kind.GetString() is not ("local" or "catalog" or "responses" or "stream" or "tool" or "official_config"))return "invalid_request";
   bool upstream=kind.GetString() is not ("local" or "official_config");
   if(upstream && request.Action=="probe" && (!p.TryGetProperty("acknowledgement",out var acknowledged) || acknowledged.ValueKind!=JsonValueKind.True))return "acknowledgement_required";
   if(p.TryGetProperty("acknowledgement",out var a) && a.ValueKind is not (JsonValueKind.True or JsonValueKind.False))return "invalid_request";
   if(kind.GetString()=="catalog" && !Text(p,"credentialLabel",Label))return "invalid_request";
   if(kind.GetString() is "responses" or "stream" or "tool") {
    if(!Text(p,"modelId",Model) || !Text(p,"expectedSnapshotDigest",Digest))return "invalid_request";
   }
   if(p.TryGetProperty("credentialLabel",out _) && !Text(p,"credentialLabel",Label))return "invalid_request";
   if(p.TryGetProperty("modelId",out _) && !Text(p,"modelId",Model))return "invalid_request";
   if(p.TryGetProperty("expectedSnapshotDigest",out _) && !Text(p,"expectedSnapshotDigest",Digest))return "invalid_request";
   if(p.TryGetProperty("outputTokenLimit",out var limit) && (limit.ValueKind!=JsonValueKind.Number || !limit.TryGetInt32(out int tokens) || tokens is <256 or >2048))return "invalid_request";
  }
  if(IsCustomManagement(request.Action)) {
   if(!Text(p,"expectedSnapshotDigest",ExactDigest))return "invalid_request";
   if(request.Action!="delete-custom-model" && !Text(p,"credentialId",Identity))return "invalid_request";
   if(request.Action is "save-credential" or "rename-credential")
    if(!DisplayLabel(p,"label"))return "invalid_request";
   if(request.Action is "save-custom-model" or "delete-custom-model")
    if(!Text(p,"customModelId",Identity))return "invalid_request";
   if(request.Action=="save-custom-model" && (!Text(p,"originalModel",ExactModel) || !DisplayLabel(p,"displayLabel")))return "invalid_request";
   var acknowledgement = request.Action=="fetch-credential-catalog" ? "acknowledgement" : "ack";
   if(p.TryGetProperty(acknowledgement,out var accepted) && accepted.ValueKind is not (JsonValueKind.True or JsonValueKind.False))return "invalid_request";
   if(!p.TryGetProperty(acknowledgement,out accepted) || accepted.ValueKind!=JsonValueKind.True)return "acknowledgement_required";
  }
  if(request.Action is not ("save-key" or "install" or "save-credential" or "rotate-credential"))return secret is null ? null : "invalid_request";
  if(secret is null)return "invalid_key";
  try{
   var raw=secret.Bytes.ToArray();
   try{
    if(raw.Length>65536)return "invalid_key";
    using var doc=JsonDocument.Parse(raw);
    var input=doc.RootElement;
    if(input.ValueKind!=JsonValueKind.Object)return "invalid_request";
    var fields = input.EnumerateObject().Select(x=>x.Name).ToArray();
    if(fields.Distinct(StringComparer.Ordinal).Count()!=fields.Length)return "invalid_request";
    if(request.Action is "save-credential" or "rotate-credential") {
     if(fields.Length!=2 || !input.TryGetProperty("credentialId",out var credentialId) || credentialId.ValueKind!=JsonValueKind.String || credentialId.GetString()!=p.GetProperty("credentialId").GetString())return "invalid_request";
     return Key(input,"key",true) ? null : "invalid_key";
    }
    if(request.Action=="save-key") {
     if(fields.Length!=2 || !input.TryGetProperty("label",out var label) || label.ValueKind!=JsonValueKind.String || label.GetString()!=p.GetProperty("label").GetString())return "invalid_request";
     return Key(input,"key",true) ? null : "invalid_key";
    }
    if(fields.Length!=3 || !fields.All(x=>x is "PLUS" or "PRO" or "FULL"))return "invalid_request";
    return Key(input,"PLUS",true) && Key(input,"PRO",false) && Key(input,"FULL",false) ? null : "invalid_key";
   }finally{System.Security.Cryptography.CryptographicOperations.ZeroMemory(raw);}
  }catch(JsonException){return "invalid_key";}catch(ObjectDisposedException){return "invalid_key";}
 }
 private static bool DisplayLabel(JsonElement p,string name) => p.TryGetProperty(name,out var value) && value.ValueKind==JsonValueKind.String && value.GetString() is {Length: >0 and <=80} text && text==text.Trim() && !text.Any(c=>c<=31 || c==127);
 private static bool Text(JsonElement p,string name,Regex pattern) => p.TryGetProperty(name,out var value) && value.ValueKind==JsonValueKind.String && pattern.IsMatch(value.GetString()!);
 private static bool Key(JsonElement p,string name,bool required) => p.TryGetProperty(name,out var value) && value.ValueKind==JsonValueKind.String && value.GetString()!.Length<=8192 && (!required || !string.IsNullOrWhiteSpace(value.GetString()));
}
