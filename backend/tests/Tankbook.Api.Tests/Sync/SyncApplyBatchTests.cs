using System.Data;
using System.Data.Common;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Sync;
using Xunit.Abstractions;

namespace Tankbook.Api.Tests.Sync;

/// <summary>
/// L2 tests for <see cref="SyncRepository.ApplyBatchAsync"/> against real
/// Postgres via Testcontainers. These drive the repository directly (no HTTP
/// host) so the number of database commands a push issues can be asserted
/// precisely through <see cref="CountingDbConnection"/>. RV.154's defect is
/// invisible on a local Postgres - ~0.1 ms per round trip makes 270 of them
/// cost nothing - so the row's test asserts the COMMAND COUNT, not the wall
/// clock: a push batch must issue a bounded, batch-sized-independent number of
/// DB commands (one batched read, one SCN range allocation, one multi-row
/// write), never 3 x record-count round trips.
/// </summary>
public class SyncApplyBatchTests : IClassFixture<PostgresFixture>
{
    private static readonly DateTimeOffset Timestamp = new(2026, 8, 22, 12, 0, 0, TimeSpan.Zero);

    private readonly PostgresFixture _fixture;
    private readonly ITestOutputHelper _output;

    public SyncApplyBatchTests(PostgresFixture fixture, ITestOutputHelper output)
    {
        _fixture = fixture;
        _output = output;
    }

    // ---- 1. The row's point: bounded, constant DB commands per batch --------

    [SkippableFact]
    public async Task ApplyBatch_TwoHundredNewRecords_IssuesConstantThreeCommands()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-a-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        var counting = new CountingDbConnection(db);
        var repo = new SyncRepository(counting);

        var changes = Enumerable.Range(0, 200)
            .Select(_ => NewChange(Guid.NewGuid(), BaseScn: 0))
            .ToArray();

        var result = await repo.ApplyBatchAsync(accountId, deviceId, changes, CancellationToken.None);

        Assert.Equal(1, result.Commits);
        Assert.Equal(200, result.Results.Count);
        Assert.All(result.Results, r => Assert.Equal(ApplyStatus.Accepted, r.Status));
        // Fresh account: exactly the contiguous block 1..200 in batch order.
        Assert.Equal(Enumerable.Range(1, 200).Select(i => (long)i).ToArray(), result.Results.Select(r => r.Scn).ToArray());

        // Before RV.154 each record cost three round trips (read + SCN + write):
        // 200 records = 600 DB commands. A batched apply is one read, one SCN
        // range allocation and one multi-row write - three commands total,
        // independent of batch size. Assert the count, never the elapsed time.
        Assert.True(counting.CommandCount == 3,
            $"a 200-record push must issue 3 DB commands (one batched read + one SCN range + one multi-row write), not 3 per record; got {counting.CommandCount}.");

        // Constant across batch sizes: a 2-record batch costs the same three.
        counting.ResetCommandCount();
        var small = new[] { NewChange(Guid.NewGuid(), BaseScn: 0), NewChange(Guid.NewGuid(), BaseScn: 0) };
        var smallResult = await repo.ApplyBatchAsync(accountId, deviceId, small, CancellationToken.None);
        Assert.Equal(1, smallResult.Commits);
        Assert.True(counting.CommandCount == 3,
            $"the command count must not depend on batch size (2 records must also cost 3 commands); got {counting.CommandCount}.");
    }

    // ---- 2. A realistic-latency demonstration (report only, never the gate) --

    [SkippableFact]
    public async Task ApplyBatch_TwoHundredNewRecords_CommandCountGate_WithLatencyReport()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-b-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        // Simulate the production database link: ~145 ms/round trip makes a
        // local Postgres defect invisible. Ten milliseconds per command is
        // enough to separate 3 commands from 600 on a stopwatch.
        var counting = new CountingDbConnection(db, commandDelay: TimeSpan.FromMilliseconds(10));
        var repo = new SyncRepository(counting);

        var changes = Enumerable.Range(0, 200)
            .Select(_ => NewChange(Guid.NewGuid(), BaseScn: 0))
            .ToArray();

        var stopwatch = Stopwatch.StartNew();
        var result = await repo.ApplyBatchAsync(accountId, deviceId, changes, CancellationToken.None);
        stopwatch.Stop();

        _output.WriteLine(
            $"RV.154 latency demo (10 ms simulated round trip): {counting.CommandCount} commands, " +
            $"{stopwatch.Elapsed.TotalMilliseconds:F0} ms for 200 records.");

        // The assertion that owns this test is the command count; the elapsed
        // time above is the demonstration. 3 commands x 10 ms can never approach
        // the bound; 600 x 10 ms = 6 s sails past it.
        Assert.True(counting.CommandCount == 3,
            $"a 200-record push must issue 3 DB commands; got {counting.CommandCount} " +
            $"({stopwatch.Elapsed.TotalMilliseconds:F0} ms at the simulated latency).");
    }

    // ---- 3. Mixed outcomes resolve in order; a conflict never rolls back -----

    [SkippableFact]
    public async Task ApplyBatch_MixedInsertConflictReplayUpdate_ResolvesPerRecordInOrder()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-c-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        var plain = new NpgsqlConnection(db.ConnectionString);
        await using (plain)
        {
            await plain.OpenAsync();
            var plainRepo = new SyncRepository(plain);

            // Seed one existing record at SCN 1.
            var seeded = Guid.NewGuid();
            var seed = await plainRepo.ApplyBatchAsync(accountId, deviceId, new[] { NewChange(seeded, BaseScn: 0) }, CancellationToken.None);
            Assert.Equal(1, seed.Commits);
            Assert.Equal(1L, seed.Results[0].Scn);

            var brandNewA = Guid.NewGuid();
            var brandNewD = Guid.NewGuid();
            var batch = new[]
            {
                NewChange(brandNewA, BaseScn: 0), // insert -> SCN 2
                NewChange(seeded, BaseScn: 999),  // stale base -> conflict, current = SCN 1
                NewChange(seeded, BaseScn: 0),    // idempotent replay -> accepted at SCN 1
                NewChange(brandNewD, BaseScn: 0), // insert -> SCN 3
                NewChange(seeded, BaseScn: 1),    // matching base -> update -> SCN 4
            };

            var applied = await plainRepo.ApplyBatchAsync(accountId, deviceId, batch, CancellationToken.None);

            // Same outcomes, same order, as the per-record path produced.
            Assert.Equal(1, applied.Commits);
            Assert.Equal(5, applied.Results.Count);
            Assert.Equal(ApplyStatus.Accepted, applied.Results[0].Status);
            Assert.Equal(2L, applied.Results[0].Scn);
            Assert.Equal(ApplyStatus.Conflict, applied.Results[1].Status);
            Assert.Equal(seeded, applied.Results[1].Current!.Id);
            Assert.Equal(1L, applied.Results[1].Current!.Scn);
            Assert.Equal(ApplyStatus.Accepted, applied.Results[2].Status);
            Assert.Equal(1L, applied.Results[2].Scn);
            Assert.Equal(ApplyStatus.Accepted, applied.Results[3].Status);
            Assert.Equal(3L, applied.Results[3].Scn);
            Assert.Equal(ApplyStatus.Accepted, applied.Results[4].Status);
            Assert.Equal(4L, applied.Results[4].Scn);

            // The conflict did not roll the batch back: all three writes landed.
            Assert.Equal(3, await plain.QuerySingleAsync<int>(
                "SELECT count(*) FROM records WHERE account_id = @p", new { p = accountId }));
            Assert.Equal(4L, await plain.QuerySingleAsync<long>(
                "SELECT scn FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = seeded }));
            Assert.Equal(2L, await plain.QuerySingleAsync<long>(
                "SELECT scn FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = brandNewA }));
        }
    }

    [SkippableFact]
    public async Task ApplyBatch_AssignedScns_AreContiguousAndStrictlyIncreasing()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-d-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        var repo = new SyncRepository(db);

        // Warm up so this batch's block starts somewhere other than 1.
        var existing = Guid.NewGuid();
        var warm = await repo.ApplyBatchAsync(accountId, deviceId, new[] { NewChange(existing, BaseScn: 0) }, CancellationToken.None);
        Assert.Equal(1L, warm.Results[0].Scn);

        // A batch whose accepted writes are separated by a conflict and a replay
        // must still hand out one contiguous, gap-free, increasing block.
        var batch = new[]
        {
            NewChange(Guid.NewGuid(), BaseScn: 0),
            NewChange(existing, BaseScn: 0),  // replay: consumes no SCN
            NewChange(Guid.NewGuid(), BaseScn: 0),
            NewChange(existing, BaseScn: 42), // conflict: consumes no SCN
            NewChange(existing, BaseScn: 1),  // update: consumes an SCN
        };

        var applied = await repo.ApplyBatchAsync(accountId, deviceId, batch, CancellationToken.None);
        var assigned = applied.Results
            .Select((r, i) => (r, i))
            .Where(t => t.r.Status == ApplyStatus.Accepted && t.r.Scn > 1) // writes, not the replay at SCN 1
            .Select(t => t.r.Scn)
            .ToArray();

        Assert.Equal(new long[] { 2, 3, 4 }, assigned);
        Assert.Equal(3, assigned.Distinct().Count());
        for (var i = 1; i < assigned.Length; i++)
        {
            Assert.True(assigned[i] == assigned[i - 1] + 1,
                $"assigned SCNs must be contiguous and strictly increasing; got {assigned[i - 1]} then {assigned[i]}.");
        }

        Assert.Equal(4L, applied.Results[4].Scn);
        Assert.Equal(4L, await db.QuerySingleAsync<long>(
            "SELECT next_scn FROM account_seq WHERE account_id = @p", new { p = accountId }));
    }

    // ---- 4. A no-op batch writes nothing and commits zero --------------------

    [SkippableFact]
    public async Task ApplyBatch_OnlyReplaysAndConflicts_WritesNothingCommitsZero()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-e-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        var repo = new SyncRepository(db);
        var existing = Guid.NewGuid();
        var seed = await repo.ApplyBatchAsync(accountId, deviceId, new[] { NewChange(existing, BaseScn: 0) }, CancellationToken.None);
        Assert.Equal(1L, seed.Results[0].Scn);

        var applied = await repo.ApplyBatchAsync(accountId, deviceId, new[]
        {
            NewChange(existing, BaseScn: 0),
            NewChange(existing, BaseScn: 999),
        }, CancellationToken.None);

        Assert.Equal(0, applied.Commits);
        Assert.Equal(ApplyStatus.Accepted, applied.Results[0].Status);
        Assert.Equal(1L, applied.Results[0].Scn);
        Assert.Equal(ApplyStatus.Conflict, applied.Results[1].Status);
        Assert.Equal(1L, applied.Results[1].Current!.Scn);

        // Nothing moved: no SCN was consumed, the row is untouched.
        Assert.Equal(1L, await db.QuerySingleAsync<long>(
            "SELECT next_scn FROM account_seq WHERE account_id = @p", new { p = accountId }));
        Assert.Equal(1L, await db.QuerySingleAsync<long>(
            "SELECT scn FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = existing }));
    }

    [SkippableFact]
    public async Task ApplyBatch_EmptyBatch_CommitsZeroAndTouchesNothing()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-f-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        // A closed connection proves the empty batch opens nothing.
        var counting = new CountingDbConnection(new NpgsqlConnection(db.ConnectionString));
        var repo = new SyncRepository(counting);

        var result = await repo.ApplyBatchAsync(accountId, deviceId, Array.Empty<BatchChange>(), CancellationToken.None);

        Assert.Empty(result.Results);
        Assert.Equal(0, result.Commits);
        Assert.Equal(0, counting.CommandCount);
        Assert.Equal(ConnectionState.Closed, counting.State);
    }

    // ---- 5. An id repeated inside one batch resolves against the batch's write

    [SkippableFact]
    public async Task ApplyBatch_DuplicateIdWithinBatch_ResolvesAgainstTheBatchOwnWrite()
    {
        _fixture.RequireAvailable();
        await using var db = await NewMigratedOpenDbAsync();
        Seed(out var accountId, out var deviceId);
        await db.ExecuteAsync(InsertAccount, new { Id = accountId, Email = $"rv154-g-{accountId:N}@example.com" });
        await db.ExecuteAsync(InsertDevice, new { Id = deviceId, AccountId = accountId });

        var repo = new SyncRepository(db);

        // A brand-new id sent twice (base 0) then once stale: the first
        // occurrence inserts at SCN 1, the second replays it at SCN 1, the
        // third conflicts against the batch's own insert - never a rollback.
        var dup = Guid.NewGuid();
        var applied = await repo.ApplyBatchAsync(accountId, deviceId, new[]
        {
            NewChange(dup, BaseScn: 0),
            NewChange(dup, BaseScn: 0),
            NewChange(dup, BaseScn: 5),
        }, CancellationToken.None);

        Assert.Equal(1, applied.Commits);
        Assert.Equal(3, applied.Results.Count);
        Assert.Equal(ApplyStatus.Accepted, applied.Results[0].Status);
        Assert.Equal(1L, applied.Results[0].Scn);
        Assert.Equal(ApplyStatus.Accepted, applied.Results[1].Status);
        Assert.Equal(1L, applied.Results[1].Scn);
        Assert.Equal(ApplyStatus.Conflict, applied.Results[2].Status);
        Assert.Equal(dup, applied.Results[2].Current!.Id);
        Assert.Equal(1L, applied.Results[2].Current!.Scn);
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = dup }));

        // An existing id updated then replayed in the same batch: the replay
        // returns the batch-assigned SCN, never the pre-batch one.
        var existing = Guid.NewGuid();
        var seed = await repo.ApplyBatchAsync(accountId, deviceId, new[] { NewChange(existing, BaseScn: 0) }, CancellationToken.None);
        Assert.Equal(2L, seed.Results[0].Scn);

        var replay = await repo.ApplyBatchAsync(accountId, deviceId, new[]
        {
            NewChange(existing, BaseScn: 2),
            NewChange(existing, BaseScn: 0),
        }, CancellationToken.None);

        Assert.Equal(1, replay.Commits);
        Assert.Equal(ApplyStatus.Accepted, replay.Results[0].Status);
        Assert.Equal(3L, replay.Results[0].Scn);
        Assert.Equal(ApplyStatus.Accepted, replay.Results[1].Status);
        Assert.Equal(3L, replay.Results[1].Scn);
        Assert.Equal(3L, await db.QuerySingleAsync<long>(
            "SELECT scn FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = existing }));
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = existing }));
    }

    // ---- helpers -----------------------------------------------------------

    private const string InsertAccount = "INSERT INTO accounts (id, email) VALUES (@Id, @Email)";
    private const string InsertDevice =
        "INSERT INTO devices (id, account_id, name, platform) VALUES (@Id, @AccountId, 'iPhone', 'ios')";

    private async Task<NpgsqlConnection> NewMigratedOpenDbAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static void Seed(out Guid accountId, out Guid deviceId)
    {
        accountId = Guid.NewGuid();
        deviceId = Guid.NewGuid();
    }

    private static BatchChange NewChange(Guid id, long BaseScn, string? payload = null)
        => new(
            id,
            EntityType: "vehicle",
            SchemaVersion: 1,
            BaseScn,
            payload ?? $$""" { "id": "{{id}}", "name": "Volvo V60" } """,
            Timestamp,
            Deleted: false);

    /// <summary>
    /// A DbConnection that counts every database command created through it and
    /// can simulate a slow database link. Each Dapper call on the wrapped
    /// connection creates exactly one command, so the count is the number of
    /// SQL round trips the caller issued - the machine-independent measure that
    /// replaces a wall-clock assertion. SCN allocation must run through this
    /// same connection (never the transaction's raw connection) or it evades
    /// the count and the per-record allocation trap goes uncaught.
    /// </summary>
    internal sealed class CountingDbConnection : DbConnection
    {
        private readonly NpgsqlConnection _inner;
        private int _commandCount;

        public CountingDbConnection(NpgsqlConnection inner, TimeSpan? commandDelay = null)
        {
            _inner = inner;
            CommandDelay = commandDelay;
        }

        public TimeSpan? CommandDelay { get; }

        public int CommandCount => Volatile.Read(ref _commandCount);

        public void ResetCommandCount() => Volatile.Write(ref _commandCount, 0);

        [AllowNull]
        public override string ConnectionString
        {
            get => _inner.ConnectionString;
            set => _inner.ConnectionString = value;
        }

        public override string Database => _inner.Database;
        public override string DataSource => _inner.DataSource;
        public override string ServerVersion => _inner.ServerVersion;
        public override ConnectionState State => _inner.State;

        public override void ChangeDatabase(string databaseName) => _inner.ChangeDatabase(databaseName);
        public override void Close() => _inner.Close();
        public override void Open() => _inner.Open();
        public override Task OpenAsync(CancellationToken cancellationToken) => _inner.OpenAsync(cancellationToken);

        protected override DbTransaction BeginDbTransaction(IsolationLevel isolationLevel)
            => _inner.BeginTransaction(isolationLevel);

        protected override async ValueTask<DbTransaction> BeginDbTransactionAsync(
            IsolationLevel isolationLevel,
            CancellationToken cancellationToken)
            => await _inner.BeginTransactionAsync(isolationLevel, cancellationToken);

        protected override DbCommand CreateDbCommand()
        {
            Interlocked.Increment(ref _commandCount);
            if (CommandDelay is { } delay)
            {
                Thread.Sleep(delay);
            }

            return _inner.CreateCommand();
        }
    }
}
