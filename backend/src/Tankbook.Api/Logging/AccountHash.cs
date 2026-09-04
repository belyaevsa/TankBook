using System.Security.Cryptography;
using System.Text;

namespace Tankbook.Api.Logging;

/// <summary>
/// The log's one identifier for one account: a stable, salted hash of the
/// ACCOUNT ID, rendered as `acct_xxxxxxxx` under the `accountHash` field on
/// every line that can resolve the account (docs/LOGGING.md §1/§2). Useless in
/// a leak - the salt lives in configuration and the truncated hash cannot be
/// reversed - and enough to correlate a support request, because every code
/// path hashes the SAME value. Two lines about one account always join.
///
/// There is exactly one other hash in this class: <see cref="ForEmail"/>, the
/// mask the redactor applies to an email that reached a log payload with no
/// account context. Its output must NEVER be written under the `accountHash`
/// field - it is a different value over a different input, and labelling it as
/// the account identifier is what broke log correlation (RV.63).
/// </summary>
public static class AccountHash
{
    private const int HexChars = 8;

    private static string Hash(string value, string salt)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(salt + ":" + value));
        return "acct_" + Convert.ToHexString(bytes)[..HexChars].ToLowerInvariant();
    }

    /// <summary>
    /// The per-request identifier behind the `accountHash` log field
    /// (docs/LOGGING.md §2). A bearer token carries the account id, not the
    /// email, so the scope hash is over the id; `auth.session` and
    /// `account.delete` compute the SAME value now that the account is resolved
    /// at the point they log (RV.63) - one identifier per account, and never a
    /// raw id in the log.
    /// </summary>
    public static string ForAccount(Guid accountId, string salt)
        => Hash(accountId.ToString("N"), salt);

    /// <summary>
    /// The mask for an email that reached the logging pipeline with no account
    /// context (docs/LOGGING.md §1, <see cref="TankbookRedactor"/>): hashes the
    /// address so it is never plaintext. It is NOT the account identifier - it
    /// cannot be, the caller has no account id - so its output belongs under the
    /// distinct `emailHash` key, never `accountHash` (RV.63: an email hash and
    /// an account-id hash answering to the same name made lines about one
    /// account unjoinable).
    /// </summary>
    public static string ForEmail(string email, string salt)
    {
        var normalized = email.Trim();
        return Hash(normalized, salt);
    }
}
