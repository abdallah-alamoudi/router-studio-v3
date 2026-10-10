using RouterStudio.Core.Contracts;
namespace RouterStudio.Core.Services;
public sealed record DashboardState {
 public string ConfiguredProvider {get;init;}="Unknown";
 public string ConfiguredModel {get;init;}="Unknown";
 public string AuthenticationState {get;init;}="Not verified";
 public string RouterState {get;init;}="Unknown";
 public string RouterConfigurationState {get;init;}="Unknown";
 public string ReviewState {get;init;}="Unknown";
 public string CatalogState {get;init;}="Unknown";
 public string LastProbeState {get;init;}="Not tested";
 public string LastProbeTime {get;init;}="No test recorded";
 public string CheckedAt {get;init;}="Not checked yet";
 public string NodeVersion {get;init;}="Unknown";
 public string PowerShellVersion {get;init;}="Unknown";
 public int ModelCount {get;init;}
 public int RouteCount {get;init;}
 public int CredentialCount {get;init;}
 public int MissingCredentialCount {get;init;}
 public bool StatusOutdated {get;init;}
 public bool CountsAvailable {get;init;}
}
public static class DashboardComposer {
 public static DashboardState Compose(StudioSnapshot? snapshot,ProbeResult? lastProbe=null,bool statusOutdated=false) {
  var stale=lastProbe is not null && (statusOutdated || snapshot is null || string.IsNullOrEmpty(snapshot.SnapshotDigest) || lastProbe.SnapshotDigest!=snapshot.SnapshotDigest);
  return new() {
   ConfiguredProvider=snapshot?.Connection.Selected switch {"official"=>"Official ChatGPT","router"=>"8stoken router",null=>"Unknown",_=>"Other configuration"},
   ConfiguredModel=Known(snapshot?.Connection.Model),
   RouterState=snapshot is null || statusOutdated ? "Unknown" : snapshot.RouterHealth.Reachable ? "Reachable" : "Unreachable",
   RouterConfigurationState=snapshot is null || statusOutdated ? "Unknown" : snapshot.RestartRequired ? "Restart required" : snapshot.RouterHealth.ConfigurationCurrent ? "Saved configuration loaded" : "Loaded configuration unknown",
   ReviewState=snapshot is null || statusOutdated ? "Unknown" : snapshot.Connection.ReviewNeeded ? "Review needed" : "No conflict reported",
   CatalogState=snapshot is null || statusOutdated ? "Unknown" : snapshot.Models.Count==0 ? "Missing" : "Available",
   LastProbeState=stale ? "Stale" : lastProbe?.Outcome.ToString() ?? "Not tested",
   LastProbeTime=lastProbe is null ? "No test recorded" : lastProbe.CompletedAtUtc.ToLocalTime().ToString("g"),
   CheckedAt=snapshot is null || snapshot.CheckedAtUtc==default ? "Not checked yet" : snapshot.CheckedAtUtc.ToLocalTime().ToString("g"),
   NodeVersion=Known(snapshot?.RuntimeVersions.Node),PowerShellVersion=Known(snapshot?.RuntimeVersions.PowerShell),
   ModelCount=snapshot?.Models.Count ?? 0,RouteCount=snapshot?.Models.Count(m=>m.HasExplicitRoute) ?? 0,
   CredentialCount=snapshot?.CredentialLabels.Count ?? 0,MissingCredentialCount=snapshot?.Models.Count(m=>!m.Saved) ?? 0,
   StatusOutdated=statusOutdated,CountsAvailable=snapshot is not null
  };
 }
 private static string Known(string? value)=>string.IsNullOrWhiteSpace(value)?"Unknown":value;
}
