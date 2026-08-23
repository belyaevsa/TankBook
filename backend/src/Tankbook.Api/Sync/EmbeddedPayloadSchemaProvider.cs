using System.Reflection;

namespace Tankbook.Api.Sync;

/// <summary>
/// Schema provider backed by the canonical schema files embedded at build time
/// (docs/schemas/v&lt;N&gt;/&lt;entityType&gt;.schema.json). Deterministic and independent of
/// any database - used by unit tests and as a build-time parity source for the
/// registry seed (see Data/PayloadSchemaSeeder).
/// </summary>
public sealed class EmbeddedPayloadSchemaProvider : IPayloadSchemaProvider
{
    private const string ResourcePrefix = "Tankbook.Api.PayloadSchemas.";
    private const string SchemaSuffix = ".schema.json";

    private readonly IReadOnlyDictionary<string, IReadOnlyDictionary<int, string>> _schemas;

    public EmbeddedPayloadSchemaProvider() : this(typeof(EmbeddedPayloadSchemaProvider).Assembly) { }

    public EmbeddedPayloadSchemaProvider(Assembly assembly)
    {
        var byEntity = new Dictionary<string, Dictionary<int, string>>(StringComparer.Ordinal);
        foreach (var resourceName in assembly.GetManifestResourceNames()
                     .Where(name => name.StartsWith(ResourcePrefix, StringComparison.Ordinal) &&
                                    name.EndsWith(SchemaSuffix, StringComparison.Ordinal)))
        {
            var (entityType, version) = ParseResourceName(resourceName);
            using var stream = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException($"Missing embedded payload schema resource '{resourceName}'.");
            using var reader = new StreamReader(stream);
            var schemaJson = reader.ReadToEnd();

            if (!byEntity.TryGetValue(entityType, out var versions))
            {
                versions = new Dictionary<int, string>();
                byEntity.Add(entityType, versions);
            }

            versions[version] = schemaJson;
        }

        _schemas = byEntity
            .ToDictionary(kvp => kvp.Key, kvp => (IReadOnlyDictionary<int, string>)kvp.Value, StringComparer.Ordinal);
    }

    public bool IsKnownEntityType(string entityType) => _schemas.ContainsKey(entityType);

    public int MaxKnownVersion(string entityType)
        => _schemas.TryGetValue(entityType, out var versions) ? versions.Keys.Max() : 0;

    public string? GetSchemaJson(string entityType, int schemaVersion)
        => _schemas.TryGetValue(entityType, out var versions) && versions.TryGetValue(schemaVersion, out var json)
            ? json
            : null;

    private static (string EntityType, int Version) ParseResourceName(string resourceName)
    {
        // Tankbook.Api.PayloadSchemas.v1.vehicle.schema.json
        var rest = resourceName[ResourcePrefix.Length..];
        var versionPart = rest[..rest.IndexOf('.')];
        var fileName = rest[(versionPart.Length + 1)..];
        var entityType = fileName[..^SchemaSuffix.Length];
        var version = int.Parse(versionPart[1..], System.Globalization.CultureInfo.InvariantCulture);
        return (entityType, version);
    }
}
