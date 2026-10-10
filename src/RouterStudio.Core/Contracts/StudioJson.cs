using System.Text.Json;
using System.Text.Json.Serialization;
namespace RouterStudio.Core.Contracts;
internal static class StudioJson
{
 internal static readonly JsonSerializerOptions Options = Create();
 private static JsonSerializerOptions Create()
 {
  var options = new JsonSerializerOptions(JsonSerializerDefaults.Web) { MaxDepth = 32, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };
  options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower));
  return options;
 }
}
