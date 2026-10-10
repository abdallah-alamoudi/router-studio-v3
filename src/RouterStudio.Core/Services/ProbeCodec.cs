using System.Text.Json;using System.Text.RegularExpressions;using RouterStudio.Core.Contracts;
namespace RouterStudio.Core.Services;
public static class ProbeCodec {
 public static ProbePreview ReadPreview(JsonElement data) {
  var value=data.Deserialize<ProbePreview>(StudioJson.Options)??throw new JsonException();
  if(!Enum.IsDefined(value.Kind)||!Digest(value.SnapshotDigest)||!Target(value.ModelId,160)||!Target(value.ResolvedModel,160)||!Target(value.CredentialLabel,40)||!Target(value.Effort,32)||value.OutputTokenLimit is <256 or >2048||value.EndpointName!=Endpoint(value.Kind))throw new JsonException();return value;
 }
 public static ProbeResult ReadResult(JsonElement data) => Validate(data.Deserialize<ProbeResult>(StudioJson.Options)??throw new JsonException());
 public static ProbeResult Validate(ProbeResult value) {
  if(!Enum.IsDefined(value.Kind)||!Enum.IsDefined(value.Outcome)||value.ErrorCode is {} error&&!Enum.IsDefined(error)||!Digest(value.SnapshotDigest)||!Target(value.ModelId,160)||!Target(value.CredentialLabel,40)||value.EndpointName!=Endpoint(value.Kind)||!double.IsFinite(value.ElapsedMs)||value.ElapsedMs<0||value.ElapsedMs>120000||value.FirstEventMs is {} first&&(!double.IsFinite(first)||first<0||first>value.ElapsedMs)||value.HttpStatus is <100 or >599||value.CompletedAtUtc==default)throw new JsonException();return value;
 }
 public static string Endpoint(ProbeKind kind)=>kind switch{ProbeKind.Local=>"Local router",ProbeKind.OfficialConfig=>"Official ChatGPT",_=>"8stoken"};
 public static bool Digest(string? value)=>value is not null&&Regex.IsMatch(value,"^[a-f0-9]{64}$");
 public static bool Target(string? value,int length)=>value is null||value.Length>0&&value.Length<=length&&Regex.IsMatch(value,"^[A-Za-z0-9][A-Za-z0-9_./:-]*$");
}
