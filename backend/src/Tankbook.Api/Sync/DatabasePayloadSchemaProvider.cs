using System.Data;
using Dapper;

namespace Tankbook.Api.Sync;

/// <summary>
/// Schema provider backed by the <c>payload_schemas</c> table (the registry of
/// record, per docs/SYNC.md). Reads the whole registry on first use and caches
/// it for the instance lifetime; the registry only changes on deploy, so this
/// is safe for a scoped service. The schema lives in the database - never in a
/// per-entity C# type - so the server keeps no domain knowledge.
/// </summary>
public sealed class DatabasePayloadSchemaProvider : IPayloadSchemaProvider
{
    private readonly IDbConnection _db;
    private IReadOnlyDictionary<string, IReadOnlyDictionary<int, string>>? _schemas;

    public DatabasePayloadSchemaProvider(IDbConnection db)
    {
        _db = db;
    }

    public bool IsKnownEntityType(string entityType)
        => EnsureLoaded().ContainsKey(entityType);

    public int MaxKnownVersion(string entityType)
        => EnsureLoaded().TryGetValue(entityType, out var versions) ? versions.Keys.Max() : 0;

    public string? GetSchemaJson(string entityType, int schemaVersion)
        => EnsureLoaded().TryGetValue(entityType, out var versions) && versions.TryGetValue(schemaVersion, out var json)
            ? json
            : null;

    private IReadOnlyDictionary<string, IReadOnlyDictionary<int, string>> EnsureLoaded()
    {
        if (_schemas is not null)
        {
            return _schemas;
        }

        var rows = _db.Query<RegistryRow>("SELECT entity_type, schema_version, json_schema::text AS json_schema FROM payload_schemas");
        var byEntity = new Dictionary<string, Dictionary<int, string>>(StringComparer.Ordinal);
        foreach (var row in rows)
        {
            if (!byEntity.TryGetValue(row.entity_type, out var versions))
            {
                versions = new Dictionary<int, string>();
                byEntity.Add(row.entity_type, versions);
            }

            versions[row.schema_version] = row.json_schema;
        }

        _schemas = byEntity
            .ToDictionary(kvp => kvp.Key, kvp => (IReadOnlyDictionary<int, string>)kvp.Value, StringComparer.Ordinal);
        return _schemas;
    }

    private sealed record RegistryRow(string entity_type, int schema_version, string json_schema);
}
