using System.Text.Json;
using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
namespace RouterStudio.Desktop.Presentation;
public sealed class KeysViewModel(ShellViewModel shell) : ObservableObject {
 private StudioSnapshot? snapshot;
 private bool enabled;
 private string label="";
 private string[] previewIds=[];
 private string previewLabel="";
 private RoutePreview? preview;
 public string Label {get=>label;set{if(Set(ref label,value))ClearPreview();}}
 public IReadOnlyList<StudioModel> RawModels=>snapshot?.Models.Where(m=>m.Kind=="Raw model").ToArray()??[];
 public string References=>snapshot is null?"Refresh locally to read saved labels.":snapshot.Keys.Count==0?"No saved credential labels.":string.Join("\n",snapshot.Keys.Select(key=>$"{key}: {string.Join(", ",snapshot.Models.Where(m=>m.Credential==key).Select(m=>m.Id))}"));
 public bool CanPreview=>enabled;
 public bool CanApply=>enabled && preview is not null;
 public string PreviewText=>preview is null?"Choose a label and raw models, then preview. Existing unselected routes remain unchanged.":string.Join("\n",preview.Changes.Select(c=>$"{c.ModelId} ({c.Kind}): {c.BeforeCredential} → {c.AfterCredential}"));
 public string PreviewLabel=>previewLabel;
 public void ClearPreview(){preview=null;Notify(nameof(CanApply));Notify(nameof(PreviewText));}
 public void Update(StudioSnapshot? value,bool allowed) {
  enabled=allowed;Notify(nameof(CanPreview));Notify(nameof(CanApply));
  if(ReferenceEquals(snapshot,value))return;
  if(snapshot?.SnapshotDigest!=value?.SnapshotDigest)ClearPreview();
  snapshot=value;Notify(nameof(RawModels));Notify(nameof(References));
 }
 public async Task PreviewAsync(IEnumerable<string> ids) {
  if(!CanPreview)return;ClearPreview();var requestedLabel=Label.Trim();var selectedIds=ids.Distinct(StringComparer.Ordinal).ToArray();
  var result=await shell.RunRequestAsync(StudioRequest.Create("preview-routes",new{label=requestedLabel,ids=selectedIds}));
  if(!result.Ok)return;
  try{
   var data=result.Data!.Value.Deserialize<RoutePreview>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
   if(data.PreviewDigest.Length!=64 || data.SnapshotDigest!=shell.SnapshotDigest || Label.Trim()!=requestedLabel)throw new JsonException();
   previewLabel=requestedLabel;previewIds=selectedIds;preview=data;Notify(nameof(CanApply));Notify(nameof(PreviewText));
  }catch{ClearPreview();shell.ReportInvalidPreview();}
 }
 public async Task ApplyAsync(SecretInput secret,bool confirmed) {
  if(!confirmed || !CanApply)return;
  var current=preview!;ClearPreview();
  await shell.RunRequestAsync(StudioRequest.Create("save-key",new{label=previewLabel,ids=previewIds,ack=true,expectedPreviewDigest=current.PreviewDigest}),secret,true);
 }
}
