using System.Data;
using Dapper;

namespace Tankbook.Api.Data;

/// <summary>
/// Atomically allocates server change numbers (SCNs) for an account. SCNs must
/// be strictly monotonic per account even under concurrent writers
/// (docs/SYNC.md) - the sync protocol breaks otherwise. The upsert acquires the
/// account_seq row lock on conflict, so concurrent allocators serialize and
/// each returns a distinct, strictly increasing value. Call inside the same
/// transaction that writes the record.
///
/// The batch apply path allocates a whole batch's SCNs as one contiguous block
/// in a single round trip: <see cref="AllocateRangeAsync"/> bumps next_scn by
/// the batch's write count and returns the block's last value. The connection
/// is passed explicitly (rather than taken from the transaction) so callers
/// that wrap the connection for measurement count every allocation; the
/// command must run on the same connection the transaction belongs to.
/// </summary>
public static class ScnAllocator
{
    /// <summary>Allocates a single SCN. Retained as the concurrency-test entry point; the sync apply path uses the range variant.</summary>
    public static Task<long> AllocateAsync(IDbTransaction transaction, Guid accountId)
        => AllocateRangeAsync(transaction.Connection!, transaction, accountId, 1);

    /// <summary>
    /// Allocates <paramref name="count"/> contiguous SCNs in one statement and
    /// returns the LAST value of the block; the block is
    /// [last - count + 1 .. last]. Callers assign block values to the batch's
    /// writes in allocation order.
    /// </summary>
    public static async Task<long> AllocateRangeAsync(
        IDbConnection connection,
        IDbTransaction transaction,
        Guid accountId,
        int count)
    {
        const string sql = """
            INSERT INTO account_seq (account_id, next_scn)
            VALUES (@accountId, @count)
            ON CONFLICT (account_id)
            DO UPDATE SET next_scn = account_seq.next_scn + @count
            RETURNING next_scn;
            """;
        return await connection.QuerySingleAsync<long>(sql, new { accountId, count }, transaction);
    }
}
