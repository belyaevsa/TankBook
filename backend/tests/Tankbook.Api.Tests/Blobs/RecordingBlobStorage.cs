using Tankbook.Api.Blobs;

namespace Tankbook.Api.Tests.Blobs;

/// <summary>
/// An in-memory, recording <see cref="IBlobStorage"/> double (docs/TESTING.md
/// "mock the boundary"): it holds objects as key->size, records every presigned
/// URL it minted (with its lifetime) and every key it deleted, so tests can
/// assert presign generation, the two lifetimes, and - crucially - that a
/// cross-account 404 never minted a URL at all. No network, no container.
/// </summary>
public sealed class RecordingBlobStorage : IBlobStorage
{
    private readonly TimeProvider _time;
    private readonly Dictionary<string, long> _objects = new(StringComparer.Ordinal);

    public RecordingBlobStorage(TimeProvider? time = null)
    {
        _time = time ?? TimeProvider.System;
    }

    public IReadOnlyList<(string Key, string ContentType, long ContentLength, TimeSpan Lifetime)> UploadUrls { get; private set; } = [];

    public IReadOnlyList<(string Key, TimeSpan Lifetime)> DownloadUrls { get; private set; } = [];
    public IReadOnlyList<string> DeletedKeys { get; private set; } = [];

    public IReadOnlyDictionary<string, long> Objects => _objects;

    private readonly Dictionary<string, byte[]> _bytes = new(StringComparer.Ordinal);

    /// <summary>The raw bytes held for each key (import files and results).</summary>
    public IReadOnlyDictionary<string, byte[]> ByteObjects => _bytes;

    /// <summary>Seeds an object into storage (the "client PUTs the bytes" step, done by the test).</summary>
    public void Put(string key, long size) => _objects[key] = size;

    public Task PutObjectAsync(string key, byte[] bytes, string contentType, CancellationToken cancellationToken)
    {
        _objects[key] = bytes.Length;
        _bytes[key] = bytes;
        return Task.CompletedTask;
    }

    public Task<byte[]?> GetObjectAsync(string key, CancellationToken cancellationToken)
        => Task.FromResult(_bytes.TryGetValue(key, out var bytes) ? bytes : (byte[]?)null);

    public PresignedUrl CreateUploadUrl(string key, string contentType, long contentLength, TimeSpan lifetime)
    {
        UploadUrls = UploadUrls.Append((key, contentType, contentLength, lifetime)).ToList();
        var expiresAt = _time.GetUtcNow().Add(lifetime);
        return new PresignedUrl(
            $"https://presign.invalid/{key}?X-Amz-Expires={(int)lifetime.TotalSeconds}&X-Amz-Signature=upload",
            expiresAt);
    }

    public PresignedUrl CreateDownloadUrl(string key, TimeSpan lifetime)
    {
        DownloadUrls = DownloadUrls.Append((key, lifetime)).ToList();
        var expiresAt = _time.GetUtcNow().Add(lifetime);
        return new PresignedUrl(
            $"https://presign.invalid/{key}?X-Amz-Expires={(int)lifetime.TotalSeconds}&X-Amz-Signature=download",
            expiresAt);
    }

    public Task<long?> GetObjectSizeAsync(string key, CancellationToken cancellationToken)
        => Task.FromResult(_objects.TryGetValue(key, out var size) ? size : (long?)null);

    public Task<IReadOnlyList<string>> ListKeysAsync(string prefix, CancellationToken cancellationToken)
        => Task.FromResult<IReadOnlyList<string>>(
            _objects.Keys.Where(k => k.StartsWith(prefix, StringComparison.Ordinal)).ToList());

    public Task DeleteAsync(string key, CancellationToken cancellationToken)
    {
        DeletedKeys = DeletedKeys.Append(key).ToList();
        _objects.Remove(key);
        _bytes.Remove(key);
        return Task.CompletedTask;
    }

    public Task DeleteManyAsync(IReadOnlyList<string> keys, CancellationToken cancellationToken)
    {
        foreach (var key in keys)
        {
            DeletedKeys = DeletedKeys.Append(key).ToList();
            _objects.Remove(key);
            _bytes.Remove(key);
        }

        return Task.CompletedTask;
    }
}
