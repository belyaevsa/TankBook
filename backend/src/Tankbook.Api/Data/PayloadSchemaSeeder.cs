using System.Globalization;
using System.Reflection;
using System.Text;

namespace Tankbook.Api.Data;

/// <summary>
/// Seeds the <c>payload_schemas</c> registry from the canonical schema files
/// (docs/schemas/v&lt;N&gt;/&lt;entityType&gt;.schema.json), which are embedded as resources
/// at build time (Tankbook.Api.csproj, Link "PayloadSchemas\v&lt;N&gt;\..."). The seed
/// runs as part of migration 002: its SQL text carries a marker that
/// <see cref="Materialize"/> replaces with idempotent INSERT statements, so
/// applying the migration IS what populates the registry and schema evolution
/// stays a data change, never a per-entity code deploy (docs/SYNC.md).
/// </summary>
public static class PayloadSchemaSeeder
{
    private const string Placeholder = "{{PAYLOAD_SCHEMAS_SEED}}";
    private const string ResourcePrefix = "Tankbook.Api.PayloadSchemas.";
    private const string SchemaSuffix = ".schema.json";

    /// <summary>
    /// Replaces the seed marker in a migration script with the generated INSERT
    /// statements. Scripts without the marker are returned unchanged.
    /// </summary>
    public static string Materialize(string migrationSql)
    {
        if (!migrationSql.Contains(Placeholder, StringComparison.Ordinal))
        {
            return migrationSql;
        }

        return migrationSql.Replace(Placeholder, SeedSql(), StringComparison.Ordinal);
    }

    /// <summary>
    /// Generates idempotent INSERT statements (one per embedded schema) so a
    /// re-applied migration never duplicates or overwrites a registered schema.
    /// </summary>
    public static string SeedSql()
    {
        var builder = new StringBuilder();
        var assembly = typeof(PayloadSchemaSeeder).Assembly;
        var resources = assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith(ResourcePrefix, StringComparison.Ordinal) &&
                           name.EndsWith(SchemaSuffix, StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal);

        foreach (var resourceName in resources)
        {
            var (entityType, version) = ParseResourceName(resourceName);
            var schemaJson = ReadResourceText(assembly, resourceName);

            builder.Append("INSERT INTO payload_schemas (entity_type, schema_version, json_schema) VALUES (")
                .Append('\'').Append(EscapeLiteral(entityType)).Append("', ")
                .Append(version.ToString(CultureInfo.InvariantCulture))
                .Append(", '").Append(EscapeLiteral(schemaJson)).Append("'::jsonb)")
                .Append(" ON CONFLICT (entity_type, schema_version) DO NOTHING;\n");
        }

        return builder.ToString();
    }

    private static (string EntityType, int Version) ParseResourceName(string resourceName)
    {
        // Tankbook.Api.PayloadSchemas.v1.vehicle.schema.json
        var rest = resourceName[ResourcePrefix.Length..];
        var versionPart = rest[..rest.IndexOf('.')];
        var fileName = rest[(versionPart.Length + 1)..];
        var entityType = fileName[..^SchemaSuffix.Length];
        var version = int.Parse(versionPart[1..], CultureInfo.InvariantCulture);
        return (entityType, version);
    }

    private static string ReadResourceText(Assembly assembly, string resourceName)
    {
        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing embedded payload schema resource '{resourceName}'.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static string EscapeLiteral(string value) => value.Replace("'", "''", StringComparison.Ordinal);
}
