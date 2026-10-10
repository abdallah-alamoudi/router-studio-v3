using System.Text.Json;
namespace RouterStudio.Core.Contracts;
public sealed record StudioRequest(int SchemaVersion, string Action, JsonElement Payload)
{
 public static StudioRequest Create(string action, object? payload = null) => new(1, action, JsonSerializer.SerializeToElement(payload ?? new { }, StudioJson.Options));
}
