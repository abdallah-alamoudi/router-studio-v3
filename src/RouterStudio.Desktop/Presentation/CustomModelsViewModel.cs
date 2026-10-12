using RouterStudio.Core.Contracts;
namespace RouterStudio.Desktop.Presentation;
public sealed class CustomModelsViewModel(ShellViewModel shell) : ObservableObject {
 private StudioSnapshot? snapshot;private bool enabled;private StudioCustomModel? selected;private StudioCredential? credential;private StudioCatalogModel? original;private string displayLabel="";
 public IReadOnlyList<StudioCustomModel> Items=>snapshot?.CustomModels??[];
 public IReadOnlyList<StudioCredential> Credentials=>snapshot?.Credentials??[];
 public IReadOnlyList<StudioCatalogModel> OriginalModels=>SelectedCredential?.CatalogModels??[];
 public StudioCustomModel? Selected {get=>selected;set{if(Set(ref selected,value)){SelectedCredential=Credentials.FirstOrDefault(c=>c.Id==value?.CredentialId);SelectedOriginal=OriginalModels.FirstOrDefault(m=>m.Id==value?.OriginalModel);DisplayLabel=value?.DisplayLabel??"";Notify(nameof(CanDelete));}}}
 public StudioCredential? SelectedCredential {get=>credential;set{if(Set(ref credential,value)){SelectedOriginal=null;Notify(nameof(OriginalModels));Notify(nameof(CanSave));}}}
 public StudioCatalogModel? SelectedOriginal {get=>original;set{if(Set(ref original,value))Notify(nameof(CanSave));}}
 public string DisplayLabel {get=>displayLabel;set{if(Set(ref displayLabel,value))Notify(nameof(CanSave));}}
 public bool CanManage=>enabled;
 public bool CanDelete=>enabled && Selected is not null;
 public bool CanSave=>enabled && SelectedCredential is not null && SelectedOriginal is not null && OriginalModels.Any(m=>m.Id==SelectedOriginal.Id) && !string.IsNullOrWhiteSpace(DisplayLabel);
 public void New(){if(!CanManage)return;Selected=null;SelectedCredential=null;SelectedOriginal=null;DisplayLabel="";}
 public void Update(StudioSnapshot? value,bool allowed){
  enabled=allowed;Notify(nameof(CanManage));Notify(nameof(CanSave));Notify(nameof(CanDelete));if(ReferenceEquals(snapshot,value))return;
  snapshot=value;Notify(nameof(Items));Notify(nameof(Credentials));
  if(selected is not null){selected=Items.FirstOrDefault(m=>m.Id==selected.Id);Notify(nameof(Selected));}
  if(credential is not null){credential=Credentials.FirstOrDefault(c=>c.Id==credential.Id);Notify(nameof(SelectedCredential));}
  if(original is not null){original=OriginalModels.FirstOrDefault(m=>m.Id==original.Id);Notify(nameof(SelectedOriginal));}
  Notify(nameof(OriginalModels));Notify(nameof(CanSave));Notify(nameof(CanDelete));
 }
 public async Task SaveAsync(bool confirmed){
  if(!confirmed||!CanSave)return;
  await shell.RunRequestAsync(StudioRequest.Create("save-custom-model",new{customModelId=Selected?.Id??("custom-"+Guid.NewGuid().ToString("N")),credentialId=SelectedCredential!.Id,originalModel=SelectedOriginal!.Id,displayLabel=DisplayLabel.Trim(),ack=true,expectedSnapshotDigest=shell.SnapshotDigest}),mutation:true);
 }
 public async Task DeleteAsync(bool confirmed){if(confirmed&&CanDelete)await shell.RunRequestAsync(StudioRequest.Create("delete-custom-model",new{customModelId=Selected!.Id,ack=true,expectedSnapshotDigest=shell.SnapshotDigest}),mutation:true);}
}
