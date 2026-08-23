using System.Reflection;
using System.Text.Json;
using Json.Schema;

namespace Tankbook.Api.Config;

/// <summary>
/// Validates config documents against the embedded JSON Schema
/// (Config/config.schema.json, docs/CONFIG.md). Validation happens AT PUBLISH
/// TIME on the server, so a malformed document never reaches a device. The
/// schema enforces structure and types only - it never interprets what a field
/// means (CLAUDE.md hard rule 9).
/// </summary>
public sealed class ConfigSchemaValidator
{
    private const string EmbeddedSchemaResource = "Tankbook.Api.Config.config.schema.json";

    private readonly JsonSchema _schema;

    public ConfigSchemaValidator()
    {
        var assembly = typeof(ConfigSchemaValidator).Assembly;
        using var stream = assembly.GetManifestResourceStream(EmbeddedSchemaResource)
            ?? throw new InvalidOperationException($"Missing embedded config schema resource '{EmbeddedSchemaResource}'.");
        using var reader = new StreamReader(stream);
        _schema = JsonSchema.FromText(reader.ReadToEnd());
    }

    /// <summary>Validates one document; returns the (possibly empty) list of schema errors.</summary>
    public IReadOnlyList<string> Validate(string documentJson)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(documentJson, new JsonDocumentOptions
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
                return new[] { "the document must be a JSON object" };
            }

            // jsonb storage de-duplicates object keys (last wins), so a document
            // with duplicate member names would be signed in one form and served
            // in another, breaking the signature. Reject them outright.
            if (HasDuplicateMemberNames(document.RootElement))
            {
                return new[] { "the document contains duplicate member names" };
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

    private static bool HasDuplicateMemberNames(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!seen.Add(property.Name))
                {
                    return true;
                }
            }

            foreach (var property in element.EnumerateObject())
            {
                if (HasDuplicateMemberNames(property.Value))
                {
                    return true;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                if (HasDuplicateMemberNames(item))
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// <summary>Convenience predicate for call sites that only need a yes/no.</summary>
    public bool IsValid(string documentJson) => Validate(documentJson).Count == 0;
}
