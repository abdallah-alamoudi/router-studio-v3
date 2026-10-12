using RouterStudio.Core.Contracts;
using RouterStudio.Core.Services;
namespace RouterStudio.Desktop.Presentation;
public sealed class SavedCredentialsViewModel(ShellViewModel shell) : ObservableObject {
 private StudioSnapshot? snapshot;private bool enabled;private StudioCredential? selected;private string label="";
 public IReadOnlyList<StudioCredential> Items=>snapshot?.Credentials??[];
 public StudioCredential? Selected {get=>selected;set{if(Set(ref selected,value)){Label=value?.Label??"";Notify(nameof(CanEdit));}}}
 public string Label {get=>label;set=>Set(ref label,value);}
 public string NewCredentialId {get;private set;}="cred-"+Guid.NewGuid().ToString("N");
 public bool CanManage=>enabled;
 public bool CanEdit=>enabled && Selected is not null;
 public void New(){if(!CanManage)return;Selected=null;Label="";NewCredentialId="cred-"+Guid.NewGuid().ToString("N");}
 public void Update(StudioSnapshot? value,bool allowed){
  enabled=allowed;Notify(nameof(CanManage));Notify(nameof(CanEdit));if(ReferenceEquals(snapshot,value))return;
  snapshot=value;Notify(nameof(Items));if(selected is not null){selected=Items.FirstOrDefault(c=>c.Id==selected.Id);Notify(nameof(Selected));Notify(nameof(CanEdit));}
 }
 public async Task SaveAsync(SecretInput secret,bool confirmed){
  if(!confirmed||!CanManage)return;
  var result=await shell.RunRequestAsync(StudioRequest.Create("save-credential",new{credentialId=NewCredentialId,label=Label.Trim(),ack=true,expectedSnapshotDigest=shell.SnapshotDigest}),secret,true);
  if(result.Ok){NewCredentialId="cred-"+Guid.NewGuid().ToString("N");Label="";}
 }
 public async Task RenameAsync(bool confirmed){if(confirmed&&CanEdit)await shell.RunRequestAsync(StudioRequest.Create("rename-credential",new{credentialId=Selected!.Id,label=Label.Trim(),ack=true,expectedSnapshotDigest=shell.SnapshotDigest}),mutation:true);}
 public async Task RotateAsync(SecretInput secret,bool confirmed){if(confirmed&&CanEdit)await shell.RunRequestAsync(StudioRequest.Create("rotate-credential",new{credentialId=Selected!.Id,ack=true,expectedSnapshotDigest=shell.SnapshotDigest}),secret,true);}
 public async Task DeleteAsync(bool confirmed){if(confirmed&&CanEdit)await shell.RunRequestAsync(StudioRequest.Create("delete-credential",new{credentialId=Selected!.Id,ack=true,expectedSnapshotDigest=shell.SnapshotDigest}),mutation:true);}
 public async Task FetchAsync(bool confirmed){if(confirmed&&CanEdit)await shell.RunRequestAsync(StudioRequest.Create("fetch-credential-catalog",new{credentialId=Selected!.Id,acknowledgement=true,expectedSnapshotDigest=shell.SnapshotDigest}),mutation:true);}
}
