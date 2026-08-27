using System.Reflection;
using System.Text.Json;
using Json.Schema;

namespace Tankbook.Api.Catalog;

/// <summary>
/// Validates a catalog pack against the embedded JSON Schema
/// (Catalog/catalog.schema.json, docs/API.md "Vehicle catalog"). Validation
/// happens AT PUBLISH TIME on the server, whole or not at all, so a malformed
/// pack never reaches a device and the previously published pack keeps serving.
/// The schema enforces structure and types only - it never interprets what a
/// field means (CLAUDE.md hard rule 9; the catalog is server-owned reference
/// data, so validating the server's own curation input against its own schema
/// is required, not a rule-9 violation).
/// </summary>
public sealed class CatalogSchemaValidator
{
    private const string EmbeddedSchemaResource = "Tankbook.Api.Catalog.catalog.schema.json";

    private readonly JsonSchema _schema;

    public CatalogSchemaValidator()
    {
        var assembly = typeof(CatalogSchemaValidator).Assembly;
        using var stream = assembly.GetManifestResourceStream(EmbeddedSchemaResource)
            ?? throw new InvalidOperationException($"Missing embedded catalog schema resource '{EmbeddedSchemaResource}'.");
        using var reader = new StreamReader(stream);
        _schema = JsonSchema.FromText(reader.ReadToEnd());
    }

    /// <summary>Validates one pack; returns the (possibly empty) list of schema errors.</summary>
    public IReadOnlyList<string> Validate(string packJson)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(packJson, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                MaxDepth = 64,
            });
        }
        catch (JsonException ex)
        {
            return new[] { $"not valid JSON: {ex.Message}" };
        }

        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return new[] { "the pack must be a JSON object" };
            }

            var evaluation = _schema.Evaluate(document.RootElement, new EvaluationOptions
            {
                OutputFormat = OutputFormat.List,
                RequireFormatValidation = true,
            });

            if (evaluation.IsValid)
            {
                return Array.Empty<string>();
            }

            return evaluation.Details
                .Where(d => d.HasErrors && d.Errors is not null)
                .Select(d => $"{d.InstanceLocation}: {string.Join("; ", d.Errors!.Select(kv => $"{kv.Key}: {kv.Value}"))}")
                .ToList();
        }
    }

    /// <summary>Convenience predicate for call sites that only need a yes/no.</summary>
    public bool IsValid(string packJson) => Validate(packJson).Count == 0;
}
