using RouterStudio.Core.Contracts;
namespace RouterStudio.Core.Services;
public interface IStudioBackend
{
 Task<StudioResult> ExecuteAsync(StudioRequest request, SecretInput? secret, CancellationToken ct);
 Task<StudioSnapshot> GetSnapshotAsync(CancellationToken ct);
}
