namespace RouterStudio.Core.Contracts;
public sealed record RouteChange(string ModelId,string Kind,string BeforeCredential,string AfterCredential);
public sealed record SettingChange(string Field,string Before,string After);
public sealed record RoutePreview {
 public string PreviewDigest {get;init;}="";
 public string SnapshotDigest {get;init;}="";
 public List<RouteChange> Changes {get;init;}=[];
}
public sealed record BackupPreview {
 public string PreviewDigest {get;init;}="";
 public string SnapshotDigest {get;init;}="";
 public List<SettingChange> Changes {get;init;}=[];
}
