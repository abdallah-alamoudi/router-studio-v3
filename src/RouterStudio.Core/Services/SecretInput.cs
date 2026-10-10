using System.Security.Cryptography;
namespace RouterStudio.Core.Services;
/// <summary>Owns a copy of UTF-8 action-specific JSON bytes. Disposal clears that copy; callers must clear their source bytes.</summary>
public sealed class SecretInput : IDisposable
{
 private byte[]? bytes;
 public SecretInput(ReadOnlySpan<byte> utf8Json) => bytes = utf8Json.ToArray();
 internal ReadOnlySpan<byte> Bytes => bytes ?? throw new ObjectDisposedException(nameof(SecretInput));
 public void Dispose() { if (bytes is null) return; CryptographicOperations.ZeroMemory(bytes); bytes = null; }
 public override string ToString() => "[protected input]";
}
