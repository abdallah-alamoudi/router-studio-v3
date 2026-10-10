namespace RouterStudio.Core.Contracts;
public enum ProbeKind { Local, Catalog, Responses, Stream, Tool, OfficialConfig }
public sealed record ProbeRequest(ProbeKind Kind, string? ModelId = null, string? CredentialLabel = null, int OutputTokenLimit = 256, string? ExpectedSnapshotDigest = null, bool Acknowledgement = false);
