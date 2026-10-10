using RouterStudio.Core.Contracts;
namespace RouterStudio.Desktop.Presentation;
public sealed class ModelsRoutesViewModel : ObservableObject {
 private IReadOnlyList<StudioModel> models=[];
 private string search="",filter="All";
 private StudioModel? selected;
 public string Search {get=>search;set{if(Set(ref search,value))Notify(nameof(FilteredModels));}}
 public string Filter {get=>filter;set{if(Set(ref filter,value))Notify(nameof(FilteredModels));}}
 public IReadOnlyList<string> Filters {get;}=["All","Raw model","Preset","Missing key"];
 public IReadOnlyList<StudioModel> FilteredModels=>models.Where(m=>(Filter=="All" || Filter=="Missing key" && !m.Saved || m.Kind==Filter) && (m.Id.Contains(Search,StringComparison.OrdinalIgnoreCase) || m.Name.Contains(Search,StringComparison.OrdinalIgnoreCase) || m.Credential.Contains(Search,StringComparison.OrdinalIgnoreCase))).ToArray();
 public StudioModel? SelectedModel {get=>selected;set{if(Set(ref selected,value))Notify(nameof(Details));}}
 public string Details=>SelectedModel is not { } m?"Select a model to read its route and declared capabilities.":$"{m.Id}\n{m.Kind} · Credential label: {m.Credential}\nDeclared reasoning levels: {(m.SupportedReasoningLevels.Count==0?"Unknown":string.Join(", ",m.SupportedReasoningLevels))}\nKey: {(m.Saved?"Saved locally":"Missing")} · Upstream access: Not tested. Catalog metadata is not proof of gateway support.";
 public void Update(IReadOnlyList<StudioModel> value) {
  if(ReferenceEquals(models,value))return;models=value;Notify(nameof(FilteredModels));
  if(SelectedModel is { } current)SelectedModel=models.FirstOrDefault(m=>m.Id==current.Id);
 }
}
