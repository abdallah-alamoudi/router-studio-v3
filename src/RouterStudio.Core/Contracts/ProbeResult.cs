namespace RouterStudio.Core.Contracts;
public enum ProbeOutcome { Passed, Failed, Incomplete, Cancelled, TimedOut, NotVerified }
public enum ProbeErrorCode { AuthRejected, RateLimited, NetworkError, ProtocolMismatch, ResponseLimit, UnsupportedCapability, OutputLimit, UpstreamError }
public sealed record ProbeResult(ProbeKind Kind, string? ModelId, string? CredentialLabel, string EndpointName, ProbeOutcome Outcome, ProbeErrorCode? ErrorCode, int? HttpStatus, double ElapsedMs, double? FirstEventMs, DateTimeOffset CompletedAtUtc, string SnapshotDigest);
