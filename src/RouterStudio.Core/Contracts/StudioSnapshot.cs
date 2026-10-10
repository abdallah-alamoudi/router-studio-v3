using System.Text.Json.Serialization;
namespace RouterStudio.Core.Contracts;
public sealed record StudioSnapshot
{
 public ConnectionState Connection { get; init; } = new();
 public bool Healthy { get; init; }
 public RouterHealth RouterHealth { get; init; } = new();
 public List<StudioModel> Models { get; init; } = [];
 public List<string> Keys { get; init; } = [];
 [JsonIgnore] public IReadOnlyList<string> CredentialLabels => Keys;
 public List<StudioBackup> Backups { get; init; } = [];
 public RuntimeVersions RuntimeVersions { get; init; } = new();
 public string SnapshotDigest { get; init; } = "";
 public DateTimeOffset CheckedAtUtc { get; init; }
 public bool RestartRequired { get; init; }
 public string Message { get; init; } = "";
}
public sealed record ConnectionState
{
 public string Provider { get; init; } = "";
 public string Selected { get; init; } = "other";
 public bool LocalRoute { get; init; }
 public bool LocalEndpoint { get; init; }
 public bool LocalCredential { get; init; }
 public bool Responses { get; init; }
 public bool ReviewNeeded { get; init; }
 public bool CanAdopt { get; init; }
 public int? StateVersion { get; init; }
 public string Model { get; init; } = "";
 public string Endpoint { get; init; } = "";
}
public sealed record RouterHealth { public bool Reachable {get;init;} public bool ConfigurationCurrent {get;init;} }
public sealed record RuntimeVersions { public string Node {get;init;}=""; public string PowerShell {get;init;}=""; }
public sealed record StudioModel
{
 public string Id {get;init;}="";
 public string Name {get;init;}="";
 public string Credential {get;init;}="";
 public string Kind {get;init;}="";
 public bool Saved {get;init;}
 public bool HasExplicitRoute {get;init;}
 public string KeyStatus {get;init;}="";
 public List<string> SupportedReasoningLevels {get;init;}=[];
}
public sealed record StudioBackup { public string Id {get;init;}=""; public DateTimeOffset Date {get;init;} public long Bytes {get;init;} }
