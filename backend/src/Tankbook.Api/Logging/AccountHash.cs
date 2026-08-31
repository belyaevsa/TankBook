using System.Security.Cryptography;
using System.Text;

namespace Tankbook.Api.Logging;

/// <summary>
/// Stable salted hash of an email, used instead of the plaintext address in
/// every log line (docs/LOGGING.md §1). Enough to correlate a support request,
/// useless in a leak: the salt lives in configuration and the truncated hash
/// cannot be reversed.
/// </summary>
public static class AccountHash
{
    private const int HexChars = 8;

    public static string Compute(string email, string salt)
    {
        var normalized = email.Trim();
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(salt + ":" + normalized));
        return "acct_" + Convert.ToHexString(bytes)[..HexChars].ToLowerInvariant();
    }

    /// <summary>
    /// The per-request stand-in for the email hash (docs/LOGGING.md §2). An
    /// access token carries the account id, not the email, so a bearer request
    /// cannot recompute the email hash; this hashes the account id instead - a
    /// stable, salted identifier that still joins a support lookup, and never
    /// a raw id in the log.
    /// </summary>
    public static string ForAccount(Guid accountId, string salt)
        => Compute(accountId.ToString("N"), salt);
}
