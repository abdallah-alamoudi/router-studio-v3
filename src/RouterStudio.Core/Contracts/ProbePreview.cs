namespace RouterStudio.Core.Contracts;
public sealed record ProbePreview(ProbeKind Kind,string? ModelId,string? ResolvedModel,string? Effort,int? OutputTokenLimit,string? CredentialLabel,string EndpointName,string SnapshotDigest,string? CredentialId=null);
