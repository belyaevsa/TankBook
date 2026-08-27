namespace Tankbook.Api.Catalog;

/// <summary>
/// A typed refusal from <see cref="CatalogPublishService.PublishAsync"/>. Not an
/// exception: the publish path is a routine internal operation and its failures
/// are ordinary control flow that callers must be able to match on.
/// </summary>
public enum CatalogPublishErrorKind
{
    /// <summary>The operation succeeded; no error.</summary>
    None = 0,

    /// <summary>The pack is not parseable JSON, not an object, or lacks packVersion/entries.</summary>
    InvalidDocument,

    /// <summary>The pack violates its JSON Schema (Catalog/catalog.schema.json).</summary>
    SchemaValidationFailed,

    /// <summary>The pack's version is not greater than the current one (rollback protection, docs/SYNC.md "Applying an update").</summary>
    VersionNotMonotonic,
}

/// <summary>The reason a publish was refused, with a human-readable detail.</summary>
public sealed record CatalogPublishError(CatalogPublishErrorKind Kind, string Detail)
{
    public static readonly CatalogPublishError None = new(CatalogPublishErrorKind.None, "");

    public bool IsSuccess => Kind == CatalogPublishErrorKind.None;
}

/// <summary>The outcome of a publish attempt.</summary>
public sealed record CatalogPublishResult(CatalogPublishError Error, int Version = 0, int EntriesPublished = 0)
{
    public bool IsSuccess => Error.IsSuccess;
}
