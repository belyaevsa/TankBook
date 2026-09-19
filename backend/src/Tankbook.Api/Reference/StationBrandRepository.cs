using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Reference;

/// <summary>A station_brands row as served (docs/API.md "GET /reference/station-brands").
/// A mutable class so Dapper maps the text[] aliases column.</summary>
public sealed class StationBrandRow
{
    public string Id { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string Country { get; set; } = string.Empty;

    public string[] Aliases { get; set; } = [];
}

/// <summary>
/// Database access for <c>station_brands</c> and its <c>station_brand_pack_state</c>
/// bookkeeping row (migration 025): the same shape as <c>vehicle_catalog</c> +
/// <c>catalog_pack_state</c>, read-only on the API. Packs are written straight
/// to the database (a migration or an operator), never through an endpoint.
/// </summary>
public sealed class StationBrandRepository
{
    private readonly IDbConnection _db;

    public StationBrandRepository(IDbConnection db)
    {
        _db = db;
    }

    private const string Columns = """
        id      AS Id,
        name    AS Name,
        country AS Country,
        aliases AS Aliases
        """;

    /// <summary>The published pack version; 0 before migration 025 ran.</summary>
    public async Task<int> GetCurrentPackVersionAsync(CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<int?>(new CommandDefinition(
                "SELECT pack_version FROM station_brand_pack_state WHERE singleton = 1",
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

    /// <summary>How many brands changed after a version - the delta's size.</summary>
    public async Task<int> GetDeltaCountAsync(int sinceVersion, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleAsync<int>(new CommandDefinition(
                "SELECT count(*) FROM station_brands WHERE pack_version > @SinceVersion",
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

    /// <summary>Every brand, ordered deterministically - the full pack.</summary>
    public async Task<IReadOnlyList<StationBrandRow>> GetFullPackAsync(CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<StationBrandRow>(new CommandDefinition(
                $"SELECT {Columns} FROM station_brands ORDER BY country, name, id",
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

    /// <summary>Brands changed after a version, ordered deterministically - the delta.</summary>
    public async Task<IReadOnlyList<StationBrandRow>> GetDeltaAsync(int sinceVersion, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<StationBrandRow>(new CommandDefinition(
                $"SELECT {Columns} FROM station_brands WHERE pack_version > @SinceVersion ORDER BY country, name, id",
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
