using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace Tankbook.Api.Config;

/// <summary>
/// Canonical serialization of a config document (docs/CONFIG.md "Guardrails on
/// apiBaseUrl" - signed payload). Client and server MUST agree byte-for-byte on
/// these bytes, because the Ed25519 signature is computed over them; a
/// divergence on either side silently breaks every document.
///
/// Canonicalization rule (the client must implement exactly this):
///   1. The document is a single JSON object.
///   2. Object members are emitted in lexicographic order of their keys
///      (ordinal / culture-invariant byte order) at EVERY nesting level.
///   3. No insignificant whitespace: ":" after each key, "," between members
///      and array elements, nothing else. Compact JSON.
///   4. Strings are emitted in minimal escape form: only " and \ are escaped,
///      control characters as \uXXXX, and everything else as raw UTF-8 bytes
///      (JavaScriptEncoder.UnsafeRelaxedJsonEscaping). Non-ASCII characters
///      are NOT escaped - so "0.75" the number and Cyrillic notice text both
///      stay as themselves.
///   5. Numbers are emitted EXACTLY as their source token (JsonElement
///      GetRawText): "0.75" stays "0.75", "1e3" stays "1e3". Neither side
///      re-serializes from a parsed floating-point value - that is the one
///      place naive implementations diverge. Both sides canonicalize the same
///      input bytes (the client canonicalizes the document exactly as served),
///      so this is safe.
///   6. Array element order is preserved. JSON defines no canonical array
///      ordering, so arrays are compared and signed in their given order.
/// </summary>
public static class ConfigCanonicalizer
{
    /// <summary>Returns the canonical UTF-8 bytes of <paramref name="documentJson"/>.</summary>
    public static byte[] Canonicalize(string documentJson)
    {
        using var document = JsonDocument.Parse(documentJson, new JsonDocumentOptions
        {
            MaxDepth = 64,
            AllowTrailingCommas = false,
        });

        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions
        {
            Indented = false,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        }))
        {
            WriteCanonical(writer, document.RootElement);
        }

        return buffer.ToArray();
    }

    private static void WriteCanonical(Utf8JsonWriter writer, JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var property in element.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(property.Name);
                    WriteCanonical(writer, property.Value);
                }

                writer.WriteEndObject();
                break;

            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var item in element.EnumerateArray())
                {
                    WriteCanonical(writer, item);
                }

                writer.WriteEndArray();
                break;

            case JsonValueKind.String:
                writer.WriteStringValue(element.GetString());
                break;

            case JsonValueKind.Number:
                // Rule 5: keep the source token verbatim, never a parsed float.
                writer.WriteRawValue(element.GetRawText(), skipInputValidation: false);
                break;

            case JsonValueKind.True:
                writer.WriteBooleanValue(true);
                break;

            case JsonValueKind.False:
                writer.WriteBooleanValue(false);
                break;

            case JsonValueKind.Null:
                writer.WriteNullValue();
                break;

            default:
                throw new InvalidOperationException($"Cannot canonicalize JSON kind {element.ValueKind}.");
        }
    }
}
