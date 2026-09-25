using System.Security.Cryptography;
using System.Text;
using Dapper;
using Microsoft.Extensions.Options;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Auth;

/// <summary>
/// The one-time token that registers the first passkey (docs/SECURITY.md -> "The admin
/// viewer"). The configured token is seeded as its SHA-256 while no passkey exists; it is
/// valid only unconsumed and only while no passkey exists, and registering consumes it.
/// </summary>
public sealed class BootstrapTokens(Db db, IOptions<AdminOptions> options)
{
    public static string Hash(string token) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    /// <summary>Records the configured token's hash, if one is set and no passkey exists.</summary>
    public async Task SeedAsync()
    {
        var token = options.Value.BootstrapToken;
        if (string.IsNullOrWhiteSpace(token))
        {
            return;
        }
        await using var c = db.AdminWrite();
        await c.ExecuteAsync(
            "INSERT INTO admin.bootstrap_tokens (token_hash) " +
            "SELECT @hash WHERE NOT EXISTS (SELECT 1 FROM admin.passkeys) " +
            "ON CONFLICT (token_hash) DO NOTHING",
            new { hash = Hash(token) });
    }

    /// <summary>True for an unconsumed token while no passkey exists.</summary>
    public async Task<bool> IsValidAsync(string? token)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return false;
        }
        await using var c = db.AdminWrite();
        return await c.ExecuteScalarAsync<bool>(
            "SELECT EXISTS (SELECT 1 FROM admin.bootstrap_tokens WHERE token_hash = @hash AND consumed_at IS NULL) " +
            "AND NOT EXISTS (SELECT 1 FROM admin.passkeys)",
            new { hash = Hash(token) });
    }

    public async Task ConsumeAsync(string token)
    {
        await using var c = db.AdminWrite();
        await c.ExecuteAsync(
            "UPDATE admin.bootstrap_tokens SET consumed_at = now() WHERE token_hash = @hash AND consumed_at IS NULL",
            new { hash = Hash(token) });
    }
}
