using Npgsql;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests;

/// <summary>
/// SCN allocation is the load-bearing invariant of docs/SYNC.md: per-account
/// SCNs must be strictly monotonic even under concurrent writers, otherwise the
/// pull stream breaks. These tests exercise ScnAllocator against a real
/// Postgres with genuinely concurrent transactions.
/// </summary>
public class ScnMonotonicityTests : IClassFixture<PostgresFixture>
{
    private const int Writers = 25;
    private const int SequentialAllocations = 100;

    private readonly PostgresFixture _fixture;

    public ScnMonotonicityTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task ConcurrentAllocations_SameAccount_AreUniqueStrictlyIncreasing()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedDbAsync();
        var accountId = Guid.NewGuid();
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@id, @email)",
            new { id = accountId, email = "scn@example.com" });

        var results = new long[Writers];
        await Parallel.ForAsync(0, Writers, async (i, _) =>
        {
            await using var connection = new NpgsqlConnection(db.ConnectionString);
            await connection.OpenAsync();
            await using var transaction = await connection.BeginTransactionAsync();
            var scn = await ScnAllocator.AllocateAsync(transaction, accountId);
            await transaction.CommitAsync();
            results[i] = scn;
        });

        var sorted = results.OrderBy(x => x).ToArray();

        Assert.Equal(Writers, sorted.Distinct().Count());
        for (var i = 0; i < sorted.Length - 1; i++)
        {
            Assert.True(
                sorted[i] < sorted[i + 1],
                $"SCNs must be strictly increasing; got {sorted[i]} then {sorted[i + 1]}.");
        }

        Assert.Equal(Enumerable.Range(1, Writers).Select(i => (long)i).ToArray(), sorted);
    }

    [SkippableFact]
    public async Task SequentialAllocations_SameAccount_AreExactlyOneThroughN()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedDbAsync();
        var accountId = Guid.NewGuid();
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@id, @email)",
            new { id = accountId, email = "scn-seq@example.com" });

        var allocated = new List<long>(SequentialAllocations);
        for (var i = 0; i < SequentialAllocations; i++)
        {
            await using var transaction = await db.BeginTransactionAsync();
            var scn = await ScnAllocator.AllocateAsync(transaction, accountId);
            await transaction.CommitAsync();
            allocated.Add(scn);
        }

        Assert.Equal(Enumerable.Range(1, SequentialAllocations).Select(i => (long)i).ToArray(), allocated);
    }

    [SkippableFact]
    public async Task DifferentAccounts_HaveIndependentScnSequences()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedDbAsync();
        var accountA = Guid.NewGuid();
        var accountB = Guid.NewGuid();
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@a, 'a@example.com'), (@b, 'b@example.com')",
            new { a = accountA, b = accountB });

        long scnA1;
        long scnB1;
        long scnA2;
        await using (var txA = await db.BeginTransactionAsync())
        {
            scnA1 = await ScnAllocator.AllocateAsync(txA, accountA);
            await txA.CommitAsync();
        }
        await using (var txB = await db.BeginTransactionAsync())
        {
            scnB1 = await ScnAllocator.AllocateAsync(txB, accountB);
            await txB.CommitAsync();
        }
        await using (var txA2 = await db.BeginTransactionAsync())
        {
            scnA2 = await ScnAllocator.AllocateAsync(txA2, accountA);
            await txA2.CommitAsync();
        }

        Assert.Equal(1, scnA1);
        Assert.Equal(1, scnB1);
        Assert.Equal(2, scnA2);
    }

    [SkippableFact]
    public async Task RolledBackAllocation_NeverDuplicatesACommittedScn()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedDbAsync();
        var accountId = Guid.NewGuid();
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@id, @email)",
            new { id = accountId, email = "scn-rollback@example.com" });

        long first;
        await using (var transaction = await db.BeginTransactionAsync())
        {
            first = await ScnAllocator.AllocateAsync(transaction, accountId);
            await transaction.CommitAsync();
        }

        long wasted;
        await using (var transaction = await db.BeginTransactionAsync())
        {
            wasted = await ScnAllocator.AllocateAsync(transaction, accountId);
            await transaction.RollbackAsync();
        }

        long next;
        await using (var transaction = await db.BeginTransactionAsync())
        {
            next = await ScnAllocator.AllocateAsync(transaction, accountId);
            await transaction.CommitAsync();
        }

        Assert.Equal(1, first);
        Assert.Equal(2, wasted);
        // The rolled-back value was never persisted, so re-issuing it is legal;
        // the load-bearing invariant is that committed SCNs stay unique and
        // strictly increasing.
        Assert.True(
            next > first,
            $"A committed allocation after a rollback must not duplicate a committed SCN; got {first} then {next}.");
        Assert.NotEqual(first, next);
    }

    private async Task<NpgsqlConnection> NewMigratedDbAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }
}
