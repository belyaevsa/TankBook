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
    private const string RefreshPlaceholder = "{{PAYLOAD_SCHEMAS_REFRESH}}";
    private const string ResourcePrefix = "Tankbook.Api.PayloadSchemas.";
    private const string SchemaSuffix = ".schema.json";

    /// <summary>
    /// Replaces the seed and refresh markers in a migration script with the
    /// generated INSERT statements. Scripts without either marker are returned
    /// unchanged.
    /// </summary>
    public static string Materialize(string migrationSql)
    {
        if (migrationSql.Contains(Placeholder, StringComparison.Ordinal))
        {
            migrationSql = migrationSql.Replace(Placeholder, SeedSql(), StringComparison.Ordinal);
        }

        if (migrationSql.Contains(RefreshPlaceholder, StringComparison.Ordinal))
        {
            migrationSql = migrationSql.Replace(RefreshPlaceholder, RefreshSql(), StringComparison.Ordinal);
        }

        return migrationSql;
    }

    /// <summary>
    /// Generates idempotent INSERT statements (one per embedded schema) so a
    /// re-applied migration never duplicates or overwrites a registered schema.
    /// </summary>
    public static string SeedSql() => EmitSql(overwrite: false);

    /// <summary>
    /// Generates the registry refresh statements (one per embedded schema):
    /// INSERT ... ON CONFLICT (entity_type, schema_version) DO UPDATE, so a
    /// deploy lands the embedded schemas it carries over whatever an earlier
    /// deploy seeded (docs/SYNC.md -> "The schema registry lives in the
    /// database"). The seed above is the first writer, not the only one: an
    /// additive change inside a version - a new enum value, an optional field -
    /// keeps the same (entity_type, schema_version) key, so a plain seed would
    /// DO NOTHING over the stale row and the deployed registry would reject
    /// what the app now emits (RV.284).
    /// </summary>
    public static string RefreshSql() => EmitSql(overwrite: true);

    private static string EmitSql(bool overwrite)
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
            var conflict = overwrite
                ? "DO UPDATE SET json_schema = EXCLUDED.json_schema"
                : "DO NOTHING";

            builder.Append("INSERT INTO payload_schemas (entity_type, schema_version, json_schema) VALUES (")
                .Append('\'').Append(EscapeLiteral(entityType)).Append("', ")
                .Append(version.ToString(CultureInfo.InvariantCulture))
                .Append(", '").Append(EscapeLiteral(schemaJson)).Append("'::jsonb)")
                .Append(" ON CONFLICT (entity_type, schema_version) ").Append(conflict).Append(";\n");
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
