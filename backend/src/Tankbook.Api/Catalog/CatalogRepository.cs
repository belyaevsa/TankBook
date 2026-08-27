using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Catalog;

/// <summary>A vehicle_catalog row as served to clients (docs/SCHEMA.md "Vehicle catalog").
/// A mutable class, not a positional record, so Dapper can map a nullable years
/// range (lower()/upper() read back as int even when the range is NULL).</summary>
public sealed class CatalogEntryRow
{
    public Guid Id { get; set; }

    public string Make { get; set; } = string.Empty;

    public string Model { get; set; } = string.Empty;

    public string? Generation { get; set; }

    public int? YearsStart { get; set; }

    public int? YearsEnd { get; set; }

    public string Powertrain { get; set; } = string.Empty;

    public string[] FuelKinds { get; set; } = [];

    public decimal? TankCapacityL { get; set; }

    public decimal? BatteryCapacityKwh { get; set; }
}

/// <summary>One entry of a pack being published (docs/API.md "Vehicle catalog").</summary>
public sealed record CatalogEntryInsert(
    Guid Id,
    string Make,
    string Model,
    string? Generation,
    int? YearsStart,
    int? YearsEnd,
    string Powertrain,
    string[] FuelKinds,
    decimal? TankCapacityL,
    decimal? BatteryCapacityKwh);

/// <summary>
/// Database access for <c>vehicle_catalog</c> and its <c>catalog_pack_state</c>
/// bookkeeping row (migrations 001 + 011, docs/SYNC.md "Reference data"). One
/// row per catalog entry (id is the primary key), so publishing a corrected
/// entry upserts it in place and bumps its <c>pack_version</c>. The current
/// version lives in the singleton <c>catalog_pack_state</c> row, claimed
/// atomically by <see cref="TryPublishPackAsync"/> with an
/// INSERT ... ON CONFLICT ... WHERE pack_version &lt; EXCLUDED.pack_version gate
/// that serializes concurrent publishes on the row lock - a version not greater
/// than the current one is refused at the database, not just in C#.
/// </summary>
public sealed class CatalogRepository
{
    private readonly IDbConnection _db;

    public CatalogRepository(IDbConnection db)
    {
        _db = db;
    }

    private const string EntryColumns = """
        id                    AS Id,
        make                  AS Make,
        model                 AS Model,
        generation            AS Generation,
        lower(years)          AS YearsStart,
        upper(years) - 1      AS YearsEnd,
        powertrain            AS Powertrain,
        fuel_kinds            AS FuelKinds,
        tank_capacity_l       AS TankCapacityL,
        battery_capacity_kwh  AS BatteryCapacityKwh
        """;

    /// <summary>
    /// The currently published pack version (the singleton catalog_pack_state
    /// row, seeded from the table's max on migration 011). 0 when nothing has
    /// ever been published.
    /// </summary>
    public async Task<int> GetCurrentPackVersionAsync(CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<int?>(new CommandDefinition(
                "SELECT pack_version FROM catalog_pack_state WHERE singleton = 1",
                cancellationToken: cancellationToken)) ?? 0;
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// The number of entries changed since a version - the delta's size. With
    /// one row per entry, this counts the entries whose last change landed after
    /// <paramref name="sinceVersion"/>. The endpoint compares it against the
    /// <c>MaxDeltaEntries</c> bound to decide delta vs full pack
    /// (docs/API.md "Vehicle catalog").
    /// </summary>
    public async Task<int> GetDeltaCountAsync(int sinceVersion, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleAsync<int>(new CommandDefinition(
                "SELECT count(*) FROM vehicle_catalog WHERE pack_version > @SinceVersion",
                new { SinceVersion = sinceVersion },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Every entry, ordered deterministically - the full pack.</summary>
    public async Task<IReadOnlyList<CatalogEntryRow>> GetFullPackAsync(CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<CatalogEntryRow>(new CommandDefinition(
                $"""
                SELECT {EntryColumns}
                FROM vehicle_catalog
                ORDER BY make, model, id
                """,
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Entries whose last change landed after a version, ordered deterministically - the delta.</summary>
    public async Task<IReadOnlyList<CatalogEntryRow>> GetDeltaAsync(int sinceVersion, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<CatalogEntryRow>(new CommandDefinition(
                $"""
                SELECT {EntryColumns}
                FROM vehicle_catalog
                WHERE pack_version > @SinceVersion
                ORDER BY pack_version, id
                """,
                new { SinceVersion = sinceVersion },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// Publishes a pack: claims <paramref name="version"/> on the singleton
    /// state row (refusing a version not greater than the current one, which
    /// serializes concurrent publishes and gives rollback protection at the
    /// database) and upserts the entries at that version, all in one
    /// transaction. Returns false when the version claim failed - nothing was
    /// written. Returns true when the whole pack landed atomically.
    /// </summary>
    public async Task<bool> TryPublishPackAsync(
        int version,
        IReadOnlyList<CatalogEntryInsert> entries,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var db = (DbConnection)_db;
            await using var transaction = await db.BeginTransactionAsync(cancellationToken);

            var claimed = await _db.QuerySingleOrDefaultAsync<int?>(new CommandDefinition(
                """
                INSERT INTO catalog_pack_state (singleton, pack_version)
                VALUES (1, @Version)
                ON CONFLICT (singleton) DO UPDATE SET pack_version = @Version
                WHERE catalog_pack_state.pack_version < @Version
                RETURNING pack_version
                """,
                new { Version = version },
                transaction: transaction,
                cancellationToken: cancellationToken));

            if (claimed is null)
            {
                return false;
            }

            foreach (var entry in entries)
            {
                await _db.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO vehicle_catalog
                        (id, make, model, generation, years, powertrain, fuel_kinds, tank_capacity_l, battery_capacity_kwh, pack_version)
                    VALUES
                        (@Id, @Make, @Model, @Generation,
                         CASE WHEN @YearsStart IS NULL THEN NULL ELSE int4range(@YearsStart, @YearsEnd + 1, '[)') END,
                         @Powertrain, @FuelKinds, @TankCapacityL, @BatteryCapacityKwh, @Version)
                    ON CONFLICT (id) DO UPDATE SET
                        make = EXCLUDED.make,
                        model = EXCLUDED.model,
                        generation = EXCLUDED.generation,
                        years = EXCLUDED.years,
                        powertrain = EXCLUDED.powertrain,
                        fuel_kinds = EXCLUDED.fuel_kinds,
                        tank_capacity_l = EXCLUDED.tank_capacity_l,
                        battery_capacity_kwh = EXCLUDED.battery_capacity_kwh,
                        pack_version = EXCLUDED.pack_version
                    """,
                    new
                    {
                        entry.Id,
                        entry.Make,
                        entry.Model,
                        entry.Generation,
                        entry.YearsStart,
                        entry.YearsEnd,
                        entry.Powertrain,
                        entry.FuelKinds,
                        entry.TankCapacityL,
                        entry.BatteryCapacityKwh,
                        Version = version,
                    },
                    transaction: transaction,
                    cancellationToken: cancellationToken));
            }

            await transaction.CommitAsync(cancellationToken);
            return true;
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    private async Task<bool> OpenIfNeededAsync()
    {
        if (_db.State == ConnectionState.Open)
        {
            return false;
        }

        await ((DbConnection)_db).OpenAsync();
        return true;
    }
}
