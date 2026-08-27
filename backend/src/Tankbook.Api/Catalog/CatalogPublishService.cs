using System.Text.Json;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Catalog;

/// <summary>
/// The operator publish path for vehicle catalog packs (docs/SYNC.md "Reference
/// data", docs/API.md "Vehicle catalog"). Whole or not at all: validate against
/// the JSON Schema first (a malformed pack must never reach a device), then
/// enforce version monotonicity (rollback protection - publishing a version not
/// greater than the current one is refused, &lt;= because re-publishing the same
/// version is equally a rollback), then insert. Any refusal is a typed
/// <see cref="CatalogPublishError"/>, never an exception string, and leaves the
/// previously published pack serving untouched.
/// </summary>
public sealed class CatalogPublishService
{
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    private readonly CatalogRepository _repository;
    private readonly CatalogSchemaValidator _validator;
    private readonly ILogger<CatalogPublishService> _logger;

    public CatalogPublishService(
        CatalogRepository repository,
        CatalogSchemaValidator validator,
        ILogger<CatalogPublishService> logger)
    {
        _repository = repository;
        _validator = validator;
        _logger = logger;
    }

    /// <summary>Validates, checks monotonicity and publishes a catalog pack.</summary>
    /// <param name="packJson">The complete pack as JSON text (see Catalog/catalog.schema.json).</param>
    public async Task<CatalogPublishResult> PublishAsync(string packJson, CancellationToken cancellationToken)
    {
        if (!TryReadEnvelope(packJson, out var version, out var entryCount))
        {
            return new CatalogPublishResult(new CatalogPublishError(
                CatalogPublishErrorKind.InvalidDocument,
                "The pack is not parseable JSON, not an object, or lacks packVersion/entries."));
        }

        var errors = _validator.Validate(packJson);
        if (errors.Count > 0)
        {
            TankbookLog.CatalogPublish(_logger, version, entryCount, "rejected", "schema_validation_failed");
            return new CatalogPublishResult(new CatalogPublishError(
                CatalogPublishErrorKind.SchemaValidationFailed,
                string.Join(" | ", errors)));
        }

        if (!TryMapPack(packJson, out var entries, out var removedIds))
        {
            // The schema guarantees the mapping below succeeds; reaching here
            // means the schema and the mapper disagree, which is a server bug.
            TankbookLog.CatalogPublish(_logger, version, entryCount, "rejected", "invalid_document");
            return new CatalogPublishResult(new CatalogPublishError(
                CatalogPublishErrorKind.InvalidDocument,
                "The pack could not be mapped to catalog entries."));
        }

        // Rollback protection (docs/SYNC.md "Applying an update"): a pack must
        // always be newer than the one currently published. <= not <, because
        // re-publishing the same version is equally a rollback. The database
        // gate in TryPublishPackAsync re-checks this atomically, so a concurrent
        // publish that lands between here and the insert is caught there.
        var current = await _repository.GetCurrentPackVersionAsync(cancellationToken);
        if (version <= current)
        {
            TankbookLog.CatalogPublish(_logger, version, entries.Count, "rejected", "version_not_monotonic");
            return new CatalogPublishResult(new CatalogPublishError(
                CatalogPublishErrorKind.VersionNotMonotonic,
                $"Pack version {version} is not greater than the current version {current}."));
        }

        if (!await _repository.TryPublishPackAsync(version, entries, removedIds, cancellationToken))
        {
            var nowCurrent = await _repository.GetCurrentPackVersionAsync(cancellationToken);
            TankbookLog.CatalogPublish(_logger, version, entries.Count, "rejected", "version_not_monotonic");
            return new CatalogPublishResult(new CatalogPublishError(
                CatalogPublishErrorKind.VersionNotMonotonic,
                $"Pack version {version} was superseded by a concurrent publish at version {nowCurrent}."));
        }

        TankbookLog.CatalogPublish(_logger, version, entries.Count, "published");
        return new CatalogPublishResult(CatalogPublishError.None, version, entries.Count);
    }

    /// <summary>
    /// Structural parse only - enough to log a version/count and to order schema
    /// validation before any write. Field-level rules belong to the schema.
    /// </summary>
    private static bool TryReadEnvelope(string packJson, out int version, out int entryCount)
    {
        version = 0;
        entryCount = 0;

        try
        {
            using var document = JsonDocument.Parse(packJson);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var root = document.RootElement;
            if (!root.TryGetProperty("packVersion", out var versionElement) || !versionElement.TryGetInt32(out version))
            {
                return false;
            }

            if (!root.TryGetProperty("entries", out var entriesElement) || entriesElement.ValueKind != JsonValueKind.Array)
            {
                return false;
            }

            entryCount = entriesElement.GetArrayLength();
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>Maps a schema-valid pack to typed inserts and withdrawals. Runs only after schema validation has passed.</summary>
    private static bool TryMapPack(
        string packJson,
        out IReadOnlyList<CatalogEntryInsert> entries,
        out IReadOnlyList<Guid> removedIds)
    {
        entries = [];
        removedIds = [];

        PackEnvelope? envelope;
        try
        {
            envelope = JsonSerializer.Deserialize<PackEnvelope>(packJson, WireJson);
        }
        catch (JsonException)
        {
            return false;
        }

        if (envelope?.Entries is null)
        {
            return false;
        }

        var list = new List<CatalogEntryInsert>(envelope.Entries.Count);
        foreach (var entry in envelope.Entries)
        {
            // The schema guarantees these fields (required + non-empty) before
            // this mapping runs; the nullable types are only the deserializer's
            // view, so the values are known-present here.
            list.Add(new CatalogEntryInsert(
                entry.Id,
                entry.Make!,
                entry.Model!,
                entry.Generation,
                entry.Years is { Length: 2 } ? entry.Years[0] : null,
                entry.Years is { Length: 2 } ? entry.Years[1] : null,
                entry.Powertrain!,
                entry.FuelKinds!.ToArray(),
                entry.TankCapacityL,
                entry.BatteryCapacityKwh));
        }

        entries = list;
        removedIds = envelope.RemovedIds ?? [];
        return true;
    }

    private sealed class PackEnvelope
    {
        public int PackVersion { get; set; }

        public List<EntryEnvelope>? Entries { get; set; }

        public List<Guid>? RemovedIds { get; set; }
    }

    private sealed class EntryEnvelope
    {
        public Guid Id { get; set; }

        public string? Make { get; set; }

        public string? Model { get; set; }

        public string? Generation { get; set; }

        public int[]? Years { get; set; }

        public string? Powertrain { get; set; }

        public List<string>? FuelKinds { get; set; }

        public decimal? TankCapacityL { get; set; }

        public decimal? BatteryCapacityKwh { get; set; }
    }
}
