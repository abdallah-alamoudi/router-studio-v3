using System.Text.Json;
using RouterStudio.Core.Contracts;
namespace RouterStudio.Desktop.Presentation;
public sealed class BackupsViewModel(ShellViewModel shell) : ObservableObject {
 private StudioSnapshot? snapshot;
 private bool enabled;
 private StudioBackup? selected;
 private BackupPreview? preview;
 public IReadOnlyList<StudioBackup> Items=>snapshot?.Backups??[];
 public StudioBackup? SelectedBackup {get=>selected;set{if(Set(ref selected,value)){ClearPreview();Notify(nameof(CanPreview));}}}
 public bool CanPreview=>enabled && SelectedBackup is not null;
 public bool CanRestore=>CanPreview && preview is not null;
 public string PreviewText=>preview is null?"Select a backup and preview its managed changes. Configuration restore does not replace keys or catalog files.":preview.Changes.Count==0?"No managed settings differ. The full configuration file will be restored; keys and catalog remain unchanged.":string.Join("\n",preview.Changes.Select(c=>$"{c.Field}: {c.Before} → {c.After}"));
 private void ClearPreview(){preview=null;Notify(nameof(CanRestore));Notify(nameof(PreviewText));}
 public void Update(StudioSnapshot? value,bool allowed) {
  enabled=allowed;Notify(nameof(CanPreview));Notify(nameof(CanRestore));
  if(ReferenceEquals(snapshot,value))return;
  if(snapshot?.SnapshotDigest!=value?.SnapshotDigest)ClearPreview();
  snapshot=value;Notify(nameof(Items));
  if(SelectedBackup is { } old)SelectedBackup=Items.FirstOrDefault(b=>b.Id==old.Id);
 }
 public async Task PreviewAsync() {
  if(!CanPreview)return;var id=SelectedBackup!.Id;ClearPreview();
  var result=await shell.RunRequestAsync(StudioRequest.Create("preview-backup",new{id}));if(!result.Ok)return;
  try{
   var data=result.Data!.Value.Deserialize<BackupPreview>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
   if(data.PreviewDigest.Length!=64 || data.SnapshotDigest!=shell.SnapshotDigest || SelectedBackup?.Id!=id)throw new JsonException();
   preview=data;Notify(nameof(CanRestore));Notify(nameof(PreviewText));
  }catch{shell.ReportInvalidPreview();}
 }
 public async Task RestoreAsync(bool confirmed) {
  if(!confirmed || !CanRestore)return;var id=SelectedBackup!.Id;var current=preview!;ClearPreview();
  await shell.RunRequestAsync(StudioRequest.Create("restore",new{id,ack=true,expectedPreviewDigest=current.PreviewDigest}),null,true);
 }
}
