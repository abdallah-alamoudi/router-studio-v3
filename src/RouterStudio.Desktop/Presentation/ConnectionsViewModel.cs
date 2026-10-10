using RouterStudio.Core.Contracts;
namespace RouterStudio.Desktop.Presentation;
public sealed class ConnectionsViewModel : ObservableObject {
 private bool canSelect;
 private string selected="Unknown",endpoint="Unknown",protocol="Unknown";
 public bool CanSelect {get=>canSelect;private set=>Set(ref canSelect,value);}
 public string Selected {get=>selected;private set=>Set(ref selected,value);}
 public string Endpoint {get=>endpoint;private set=>Set(ref endpoint,value);}
 public string Protocol {get=>protocol;private set=>Set(ref protocol,value);}
 public void Update(StudioSnapshot? snapshot,bool enabled) {
  CanSelect=enabled;
  Selected=snapshot?.Connection.Selected switch {"official"=>"Official ChatGPT","router"=>"8stoken router",null=>"Unknown",_=>"Other configuration"};
  Endpoint=snapshot?.Connection.Endpoint switch {"Official ChatGPT sign-in"=>"Official ChatGPT sign-in","http://127.0.0.1:18761/v1"=>"http://127.0.0.1:18761/v1","https://8stoken.com/v1"=>"https://8stoken.com/v1",null or ""=>"Unknown",_=>"Another endpoint (hidden)"};
  Protocol=snapshot is null ? "Unknown" : snapshot.Connection.Selected=="official" ? "Managed by official sign-in" : snapshot.Connection.Responses ? "Responses" : "Review protocol configuration";
 }
}
