using Tankbook.Api.Sync;

namespace Tankbook.Api.Tests;

/// <summary>
/// In-memory <see cref="IPayloadSchemaProvider"/> built from a directory of
/// canonical schema files (docs/schemas/v&lt;N&gt;/*.schema.json), so the unit tests
/// validate against the exact files that the server and the iOS client share.
/// </summary>
internal sealed class DirectorySchemaProvider : IPayloadSchemaProvider
{
    private readonly IReadOnlyDictionary<string, IReadOnlyDictionary<int, string>> _schemas;

    private DirectorySchemaProvider(IReadOnlyDictionary<string, IReadOnlyDictionary<int, string>> schemas)
    {
        _schemas = schemas;
    }

    /// <summary>Loads every &lt;entityType&gt;.schema.json in <paramref name="directory"/> at version 1.</summary>
    public static DirectorySchemaProvider FromV1(string directory)
    {
        var byEntity = new Dictionary<string, Dictionary<int, string>>(StringComparer.Ordinal);
        foreach (var file in Directory.EnumerateFiles(directory, "*.schema.json").OrderBy(f => f, StringComparer.Ordinal))
        {
            var fileName = Path.GetFileName(file);
            var entityType = fileName[..^".schema.json".Length];
            byEntity[entityType] = new Dictionary<int, string> { [1] = File.ReadAllText(file) };
        }

        var frozen = byEntity.ToDictionary(
            kvp => kvp.Key,
            kvp => (IReadOnlyDictionary<int, string>)kvp.Value,
            StringComparer.Ordinal);
        return new DirectorySchemaProvider(frozen);
    }

    public bool IsKnownEntityType(string entityType) => _schemas.ContainsKey(entityType);

    public int MaxKnownVersion(string entityType)
        => _schemas.TryGetValue(entityType, out var versions) ? versions.Keys.Max() : 0;

    public string? GetSchemaJson(string entityType, int schemaVersion)
        => _schemas.TryGetValue(entityType, out var versions) && versions.TryGetValue(schemaVersion, out var json)
            ? json
            : null;
}
