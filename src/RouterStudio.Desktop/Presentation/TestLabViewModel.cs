using System.Diagnostics;using RouterStudio.Core.Contracts;using RouterStudio.Core.Services;
namespace RouterStudio.Desktop.Presentation;
public sealed class TestLabViewModel(ShellViewModel shell):ObservableObject {
 private StudioSnapshot? snapshot;private bool enabled,running;private ProbeKind kind=ProbeKind.Local;private string? model,credential;private int limit=256;private ProbePreview? preview;private ProbeResult? result;private CancellationTokenSource? cancellation;private readonly Stopwatch watch=new();
 public IReadOnlyList<ProbeKind> Kinds {get;}=Enum.GetValues<ProbeKind>();
 public IReadOnlyList<ProbeChoice> Choices {get;}=[new(ProbeKind.Local,"Local router health"),new(ProbeKind.Catalog,"Saved key: model catalog"),new(ProbeKind.Responses,"Model: generation"),new(ProbeKind.Stream,"Model: streaming"),new(ProbeKind.Tool,"Model: synthetic tool call"),new(ProbeKind.OfficialConfig,"Official configuration (authentication unverified)")];
 public IReadOnlyList<string> Models=>snapshot?.Models.Select(m=>m.Id).ToArray()??[];
 public IReadOnlyList<string> Credentials=>snapshot?.Keys??[];
 public ProbeKind Kind{get=>kind;set{if(Set(ref kind,value)){ClearPreview();Notify(nameof(NeedsModel));Notify(nameof(NeedsCredential));}}}
 public string? SelectedModel{get=>model;set{if(Set(ref model,value))ClearPreview();}}
 public string? SelectedCredential{get=>credential;set{if(Set(ref credential,value))ClearPreview();}}
 public int OutputTokenLimit{get=>limit;set{if(Set(ref limit,value))ClearPreview();}}
 public bool NeedsModel=>Kind is ProbeKind.Responses or ProbeKind.Stream or ProbeKind.Tool;
 public bool NeedsCredential=>Kind==ProbeKind.Catalog;
 public bool CanPreview=>enabled&&!Running&&(!NeedsModel||(Models.Contains(SelectedModel!)&&OutputTokenLimit is >=256 and <=2048))&&(!NeedsCredential||Credentials.Contains(SelectedCredential!));
 public bool CanRun=>CanPreview&&preview is not null;
 public bool Running{get=>running;private set{Set(ref running,value);Notify(nameof(CanPreview));Notify(nameof(CanRun));}}
 public string Elapsed=>Running?$"Running · {watch.Elapsed.TotalSeconds:F0}s · cancellation may not stop billing":"Idle";
 public string PreviewText=>preview is null?"Choose a check and preview its target. No upstream request is sent by preview.":$"{preview.Kind} · {preview.EndpointName}\nModel: {preview.ModelId??"Not applicable"} → {preview.ResolvedModel??"Not applicable"}\nSaved key: {preview.CredentialLabel??"None"} · Reasoning: {preview.Effort??"Not specified"} · Output cap: {preview.OutputTokenLimit?.ToString()??"Not applicable"}\n"+(Kind is ProbeKind.Local or ProbeKind.OfficialConfig?"Local configuration/health only. Official sign-in, workspace, model access and quota remain not verified.":"One direct gateway request; may incur a charge. Output caps do not bound total billed reasoning or cost. This is not an end-to-end Codex test.");
 public string ResultText=>result is null?"No test run. Catalog-declared support remains separate from observed results.":$"{result.Outcome} · {result.Kind} · {result.EndpointName}\nModel: {result.ModelId??"None"} · Key: {result.CredentialLabel??"None"}\nHTTP: {result.HttpStatus?.ToString()??"None"} · Error: {result.ErrorCode?.ToString()??"None"}\nTotal: {result.ElapsedMs:F0}ms · First event: {result.FirstEventMs?.ToString("F0")??"None"}ms\nCompleted: {result.CompletedAtUtc.LocalDateTime:g}"+(snapshot?.SnapshotDigest!=result.SnapshotDigest||!enabled&&!Running?"\nStale — refresh local status and review before relying on this result.":"");
 public void Update(StudioSnapshot? value,bool allowed){enabled=allowed;if(snapshot?.SnapshotDigest!=value?.SnapshotDigest)ClearPreview();snapshot=value;Notify(nameof(Models));Notify(nameof(Credentials));Notify(nameof(CanPreview));Notify(nameof(CanRun));Notify(nameof(ResultText));}
 private void ClearPreview(){preview=null;Notify(nameof(PreviewText));Notify(nameof(CanRun));Notify(nameof(CanPreview));}
 private ProbeRequest Request(bool acknowledged)=>new(Kind,NeedsModel?SelectedModel:null,NeedsCredential?SelectedCredential:null,NeedsModel?OutputTokenLimit:256,snapshot?.SnapshotDigest,acknowledged);
 public async Task PreviewAsync(){if(!CanPreview)return;var request=Request(false);ClearPreview();var response=await shell.RunRequestAsync(StudioRequest.Create("preview-probe",request));if(!response.Ok)return;
  try{var data=ProbeCodec.ReadPreview(response.Data!.Value);if(data.SnapshotDigest!=shell.SnapshotDigest||request!=Request(false))throw new InvalidOperationException();preview=data;Notify(nameof(PreviewText));Notify(nameof(CanRun));}catch{shell.ReportInvalidPreview();}}
 public async Task RunAsync(bool acknowledged){if(!CanRun||!acknowledged)return;var request=Request(true);ClearPreview();cancellation=new();Running=true;watch.Restart();NotifyElapsed();
  try{var response=await shell.RunProbeAsync(request,cancellation.Token);if(response.Ok)result=ProbeCodec.ReadResult(response.Data!.Value);else result=new(request.Kind,request.ModelId,preview?.CredentialLabel??(NeedsModel?snapshot?.Models.FirstOrDefault(m=>m.Id==request.ModelId)?.Credential:request.CredentialLabel),ProbeCodec.Endpoint(request.Kind),response.Error?.Code=="cancelled"?ProbeOutcome.Cancelled:ProbeOutcome.Failed,null,null,watch.Elapsed.TotalMilliseconds,null,DateTimeOffset.UtcNow,request.ExpectedSnapshotDigest!);shell.RecordProbeResult(result);}catch{shell.ReportInvalidPreview();result=null;}
  finally{watch.Stop();Running=false;cancellation.Dispose();cancellation=null;NotifyElapsed();Notify(nameof(ResultText));}}
 public void Cancel()=>cancellation?.Cancel();
 public void NotifyElapsed()=>Notify(nameof(Elapsed));
}
public sealed record ProbeChoice(ProbeKind Kind,string Label);
