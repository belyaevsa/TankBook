namespace Tankbook.Api.Blobs;

/// <summary>A presigned URL and the moment it stops working.</summary>
public sealed record PresignedUrl(string Url, DateTimeOffset ExpiresAt);

/// <summary>
/// The storage seam (docs/TESTING.md "mock the boundary"): the server talks to
/// S3-compatible object storage only through this interface, so the L2 suite can
/// swap in a recording/in-memory double and assert presign generation and expiry
/// without a running container. The production implementation is
/// <see cref="S3BlobStorage"/>; nothing above this interface knows the provider.
/// Keys are always within one account's prefix ({account_id}/{sha256}) - callers
/// supply the full key, the interface never derives it from untrusted input.
/// </summary>
public interface IBlobStorage
{
    /// <summary>Mints a presigned PUT valid for <paramref name="lifetime"/>. Pure local computation, no network.</summary>
    PresignedUrl CreateUploadUrl(string key, TimeSpan lifetime);

    /// <summary>Mints a presigned GET valid for <paramref name="lifetime"/>. Pure local computation, no network.</summary>
    PresignedUrl CreateDownloadUrl(string key, TimeSpan lifetime);

    /// <summary>Writes an object's bytes. Used by import parsing (docs/API.md
    /// "Import parsing"): the uploaded file and its parse result are stored here
    /// server-side, unlike the presigned-URL blob pipeline where the client PUTs
    /// to storage directly.</summary>
    Task PutObjectAsync(string key, byte[] bytes, string contentType, CancellationToken cancellationToken);

    /// <summary>Reads an object's bytes, or null when the key does not exist. Used to re-read a stored import result.</summary>
    Task<byte[]?> GetObjectAsync(string key, CancellationToken cancellationToken);

    /// <summary>The stored object's size in bytes, or null when the key does not exist.</summary>
    Task<long?> GetObjectSizeAsync(string key, CancellationToken cancellationToken);

    /// <summary>Every key under <paramref name="prefix"/> (used by the sweep and account purge).</summary>
    Task<IReadOnlyList<string>> ListKeysAsync(string prefix, CancellationToken cancellationToken);

    /// <summary>Deletes one object. Idempotent: deleting a missing key is not an error.</summary>
    Task DeleteAsync(string key, CancellationToken cancellationToken);

    /// <summary>Deletes many objects. Idempotent; missing keys are not errors.</summary>
    Task DeleteManyAsync(IReadOnlyList<string> keys, CancellationToken cancellationToken);
}
