namespace RouterStudio.Core.Services;
public sealed record WorkerFixturePaths(string InstallRoot, string ConfigPath, Uri HealthUri);
public sealed record WorkerBackendOptions
{
 public required string PowerShellPath { get; init; }
 public required string WorkerPath { get; init; }
 public string? ProbeWorkerPath { get; init; }
 public string JobsRoot { get; init; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RouterStudioJobs");
 public WorkerFixturePaths? FixturePaths { get; init; }
}
