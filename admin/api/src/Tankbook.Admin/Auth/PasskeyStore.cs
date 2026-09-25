using Dapper;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Auth;

public sealed record Passkey(Guid Id, byte[] CredentialId, byte[] PublicKey, long SignCount, byte[] UserHandle, string Label);

/// <summary>The owner's passkeys, in <c>admin.passkeys</c>.</summary>
public sealed class PasskeyStore(Db db)
{
    public async Task<bool> AnyAsync()
    {
        await using var c = db.AdminWrite();
        return await c.ExecuteScalarAsync<bool>("SELECT EXISTS (SELECT 1 FROM admin.passkeys)");
    }

    public async Task<IReadOnlyList<Passkey>> AllAsync()
    {
        await using var c = db.AdminWrite();
        return (await c.QueryAsync<Passkey>(
            "SELECT id, credential_id AS CredentialId, public_key AS PublicKey, sign_count AS SignCount, " +
            "user_handle AS UserHandle, label FROM admin.passkeys")).ToList();
    }

    public async Task<Passkey?> FindAsync(byte[] credentialId)
    {
        await using var c = db.AdminWrite();
        return await c.QuerySingleOrDefaultAsync<Passkey>(
            "SELECT id, credential_id AS CredentialId, public_key AS PublicKey, sign_count AS SignCount, " +
            "user_handle AS UserHandle, label FROM admin.passkeys WHERE credential_id = @credentialId",
            new { credentialId });
    }

    public async Task AddAsync(Passkey passkey)
    {
        await using var c = db.AdminWrite();
        await c.ExecuteAsync(
            "INSERT INTO admin.passkeys (id, credential_id, public_key, sign_count, user_handle, label) " +
            "VALUES (@Id, @CredentialId, @PublicKey, @SignCount, @UserHandle, @Label)", passkey);
    }

    public async Task TouchAsync(Guid id, long signCount)
    {
        await using var c = db.AdminWrite();
        await c.ExecuteAsync(
            "UPDATE admin.passkeys SET sign_count = @signCount, last_used_at = now() WHERE id = @id",
            new { id, signCount });
    }
}
