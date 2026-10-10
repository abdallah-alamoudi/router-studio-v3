using System.Text.Json;
namespace RouterStudio.Core.Contracts;
public sealed record StudioError(string Code, string Message);
public sealed record StudioResult(int SchemaVersion, bool Ok, JsonElement? Data, StudioError? Error)
{
 public static StudioResult Failure(string code) => new(1, false, null, StudioErrors.Get(code));
}
public static class StudioErrors
{
 private static readonly Dictionary<string,string> Messages = new(StringComparer.Ordinal)
 {
  ["invalid_request"]="Choose a supported management action and valid input.",
  ["unsupported_schema"]="This request version is not supported. Update Router Studio.",
  ["acknowledgement_required"]="Save your work and close Codex, then confirm the restart acknowledgement.",
  ["invalid_key"]="Enter a non-empty API key.",
  ["installation_incomplete"]="Installation is incomplete. Use setup or your installation backup.",
  ["installation_failed"]="Setup could not finish. Review prerequisites and the installation backup before retrying.",
  ["endpoint_override"]="Remove the endpoint override before selecting subscription access.",
  ["config_changed"]="Connection settings changed. Refresh status before applying changes.",
  ["busy"]="Another action is running. Wait for it to finish.",
  ["recovery_required"]="Recovery needs attention. Review the final state and encrypted backups.",
  ["startup_failed"]="The router did not start with the saved configuration. Saved keys and routes were kept; a restart is still required.",
  ["operation_failed"]="The operation failed. Refresh status and check the local installation.",
  ["worker_failed"]="The management worker could not finish. Refresh status and check recovery before retrying.",
  ["invalid_result"]="The worker returned an unreadable result. Refresh status before making another change.",
  ["cancelled"]="The read or test was cancelled.",
  ["unsupported_capability"]="This feature is not available in the current installation."
 };
 public static StudioError Get(string code) => Messages.TryGetValue(code,out var message) ? new(code,message) : new("operation_failed",Messages["operation_failed"]);
}
