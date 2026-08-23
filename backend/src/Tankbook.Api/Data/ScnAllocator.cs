using System.Data;
using Dapper;

namespace Tankbook.Api.Data;

/// <summary>
/// Atomically allocates the next server change number (SCN) for an account.
/// SCNs must be strictly monotonic per account even under concurrent writers
/// (docs/SYNC.md) - the sync protocol breaks otherwise. The upsert acquires the
/// account_seq row lock on conflict, so concurrent allocators serialize and each
/// returns a distinct, strictly increasing value. Call inside the same
/// transaction that writes the record.
/// </summary>
public static class ScnAllocator
{
    public static async Task<long> AllocateAsync(IDbTransaction transaction, Guid accountId)
    {
        const string sql = """
            INSERT INTO account_seq (account_id, next_scn)
            VALUES (@accountId, 1)
            ON CONFLICT (account_id)
            DO UPDATE SET next_scn = account_seq.next_scn + 1
            RETURNING next_scn;
            """;
        return await transaction.Connection!.QuerySingleAsync<long>(sql, new { accountId }, transaction);
    }
}
