using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Json.Schema;

namespace Tankbook.Api.Sync;

/// <summary>
/// Structural payload validation for POST /sync/push (docs/SYNC.md "Payload
/// contract and versioning", docs/API.md rejection codes). The server validates
/// payload STRUCTURE only - never domain meaning: a payload is checked against
/// the registered JSON Schema for its (entity_type, schema_version), and an
/// unknown entity_type with a well-formed envelope is accepted unvalidated so
/// the entity set stays open for older servers.
/// </summary>
public sealed partial class PayloadValidator
{
    public const int MaxPayloadBytes = 256 * 1024; // 256 KB, docs/SYNC.md
    public const int MaxEntityTypeLength = 64;     // chars, docs/SYNC.md

    private readonly IPayloadSchemaProvider _schemas;
    private readonly int _minSupportedVersion;

    public PayloadValidator(IPayloadSchemaProvider schemas, int minSupportedVersion = 1)
    {
        _schemas = schemas;
        _minSupportedVersion = minSupportedVersion;
    }

    /// <summary>
    /// Validates one change's payload. Pure, side-effect free, and unit-testable
    /// without any host or database.
    /// </summary>
    public PayloadValidationResult Validate(string entityType, int schemaVersion, string payloadJson)
    {
        // Envelope checks (docs/SYNC.md "What the server enforces").
        if (string.IsNullOrWhiteSpace(entityType) || entityType.Length > MaxEntityTypeLength)
        {
            return PayloadValidationResult.Reject(PayloadRejectionCode.PayloadInvalid);
        }

        if (Encoding.UTF8.GetByteCount(payloadJson) > MaxPayloadBytes)
        {
            return PayloadValidationResult.Reject(PayloadRejectionCode.PayloadInvalid);
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(payloadJson, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                MaxDepth = 128,
            });
        }
        catch (JsonException)
        {
            return PayloadValidationResult.Reject(PayloadRejectionCode.PayloadInvalid);
        }

        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return PayloadValidationResult.Reject(PayloadRejectionCode.PayloadInvalid);
            }

            // Unknown entity_type with a well-formed envelope is accepted
            // unvalidated (docs/SYNC.md) - it keeps the open set open.
            if (!_schemas.IsKnownEntityType(entityType))
            {
                return PayloadValidationResult.Accepted;
            }

            if (schemaVersion < _minSupportedVersion)
            {
                return PayloadValidationResult.Reject(PayloadRejectionCode.UpgradeRequired);
            }

            if (schemaVersion > _schemas.MaxKnownVersion(entityType))
            {
                return PayloadValidationResult.Reject(PayloadRejectionCode.SchemaVersionUnsupported);
            }

            var schemaJson = _schemas.GetSchemaJson(entityType, schemaVersion);
            if (schemaJson is null)
            {
                return PayloadValidationResult.Reject(PayloadRejectionCode.SchemaVersionUnsupported);
            }

            return ValidateAgainstSchema(schemaJson, document.RootElement);
        }
    }

    private static PayloadValidationResult ValidateAgainstSchema(string schemaJson, JsonElement payload)
    {
        JsonSchema schema;
        try
        {
            schema = JsonSchema.FromText(schemaJson);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // A malformed registered schema is a server-side data problem, not a
            // client payload problem; failing loudly beats silently accepting or
            // mis-rejecting every payload of this entity.
            throw new InvalidOperationException("The registered JSON Schema is not valid JSON Schema.", ex);
        }

        var evaluation = schema.Evaluate(payload, new EvaluationOptions
        {
            OutputFormat = OutputFormat.List,
            RequireFormatValidation = true,
        });

        if (evaluation.IsValid)
        {
            return PayloadValidationResult.Accepted;
        }

        var pointer = FailingPointer(evaluation);
        return PayloadValidationResult.Reject(PayloadRejectionCode.PayloadSchemaViolation, pointer);
    }

    /// <summary>
    /// Names the failing field as a JSON pointer (RFC 6901), never its value.
    /// A missing-required-property failure points at the absent property
    /// (e.g. /createdAt); everything else points at the instance location of
    /// the offending value (e.g. /units/distance).
    /// </summary>
    private static string? FailingPointer(EvaluationResults evaluation)
    {
        string? best = null;
        var bestDepth = -1;

        foreach (var detail in evaluation.Details)
        {
            if (!detail.HasErrors)
            {
                continue;
            }

            var candidate = DetailPointer(detail);
            if (candidate is null)
            {
                continue;
            }

            var depth = candidate.Length == 0 ? 0 : candidate.Count(c => c == '/');
            if (depth > bestDepth)
            {
                best = candidate;
                bestDepth = depth;
            }
        }

        return best;
    }

    private static string? DetailPointer(EvaluationResults detail)
    {
        var instance = detail.InstanceLocation.ToString();

        // A "required" keyword failure carries the missing property names in its
        // error message; append the first missing field to the containing object.
        if (detail.Errors is not null && detail.Errors.TryGetValue("required", out var message))
        {
            var missing = FirstMissingProperty(message);
            if (missing is not null)
            {
                return instance + "/" + EscapePointerSegment(missing);
            }
        }

        return instance;
    }

    /// <summary>Extracts the first missing property name from a "required" error.</summary>
    private static string? FirstMissingProperty(string message)
    {
        // e.g. Required properties ["createdAt","updatedAt",...] were not present
        var match = RequiredErrorRegex().Match(message);
        if (!match.Success)
        {
            return null;
        }

        try
        {
            using var doc = JsonDocument.Parse(match.Groups[1].Value);
            if (doc.RootElement.ValueKind == JsonValueKind.Array && doc.RootElement.GetArrayLength() > 0)
            {
                return doc.RootElement[0].GetString();
            }
        }
        catch (JsonException)
        {
            return null;
        }

        return null;
    }

    private static string EscapePointerSegment(string segment)
        => segment.Replace("~", "~0", StringComparison.Ordinal)
                  .Replace("/", "~1", StringComparison.Ordinal);

    [GeneratedRegex("Required properties (\\[[^\\]]*\\])")]
    private static partial Regex RequiredErrorRegex();
}
