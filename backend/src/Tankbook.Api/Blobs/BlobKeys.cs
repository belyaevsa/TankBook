namespace Tankbook.Api.Blobs;

/// <summary>
/// The storage key layout (docs/SYNC.md): one private bucket, keys
/// <c>{account_id}/{sha256}</c>. Content-addressed, so identical files dedupe
/// per account and a key never changes; the account-id prefix is what makes
/// per-account prefix purges and cross-account isolation structural. The digest
/// is always a validated 64-hex lower-case string (BlobContentTypes.IsValidSha256),
/// so it can never carry a separator or ".." that would escape the prefix.
/// </summary>
public static class BlobKeys
{
    public static string Key(Guid accountId, string sha256) =>
        $"{accountId.ToString("N")}/{sha256}";

    public static string Prefix(Guid accountId) =>
        $"{accountId.ToString("N")}/";
}
