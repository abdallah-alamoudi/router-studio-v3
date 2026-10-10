using RouterStudio.Core.Services;
namespace RouterStudio.Desktop.Presentation;
public sealed class DashboardViewModel : ObservableObject {
 private DashboardState state=new();
 public DashboardState State {get=>state; private set=>Set(ref state,value);}
 public void Update(DashboardState value)=>State=value;
}
