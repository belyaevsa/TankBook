namespace Tankbook.Api.Sync;

/// <summary>
/// Read-only view of the payload schema registry (payload_schemas). The server
/// validates payload STRUCTURE against these schemas and never reads domain
/// meaning (CLAUDE.md hard rule 9). Implementations may source the registry
/// from the database or from the schemas embedded at build time.
/// </summary>
public interface IPayloadSchemaProvider
{
    /// <summary>True when the registry holds at least one version of the entity.</summary>
    bool IsKnownEntityType(string entityType);

    /// <summary>The highest registered schema_version for the entity, or 0 when unknown.</summary>
    int MaxKnownVersion(string entityType);

    /// <summary>The registered schema text for (entity_type, schema_version), or null.</summary>
    string? GetSchemaJson(string entityType, int schemaVersion);
}
