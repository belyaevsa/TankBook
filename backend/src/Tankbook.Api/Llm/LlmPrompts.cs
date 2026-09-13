using System.Text.Json;

namespace Tankbook.Api.Llm;

/// <summary>
/// The provider prompt for one extraction kind (docs/EXTRACTION.md "The Expense
/// hand-off"). The document kind changes what the model is asked to read: a fuel
/// receipt has a volume and a unit price, a shop or parking receipt has a
/// category and no fuel fields at all. The server still reads no meaning - it
/// forwards a field NAME list and a one-line description of the document (hard
/// rule 9); the model decides what a pixel is.
///
/// This is a separate type so the prompt is unit-testable without an HTTP call:
/// <see cref="OpenAiCompatibleLlmProvider"/> is never exercised by the suite
/// (docs/TESTING.md), but the per-kind vocabulary is part of the contract and
/// must not regress silently.
/// </summary>
internal static class LlmPrompts
{
    /// <summary>The system message: the JSON shape, the kind's allowed field names, and the request hints.</summary>
    public static string SystemPrompt(string kind, ExtractHints hints)
    {
        var hintsJson = JsonSerializer.Serialize(HintsFor(kind, hints));

        return $"You extract fields from an image of {Document(kind)}. " +
               "Respond with a single JSON object and nothing else: " +
               "{ \"fields\": [ { \"name\": string, \"value\": number|string, \"confidence\": 0..1 } ] }. " +
               $"Allowed field names: {AllowedFields(kind)}. " +
               "A field you cannot read is omitted, never guessed. Request context: " + hintsJson;
    }

    /// <summary>The user message: names the document so the model reads the right fields.</summary>
    public static string UserMessage(string kind)
        => $"Extract the fields from this image of {Document(kind)} as the JSON object described.";

    /// <summary>
    /// The request context, with empty members omitted. A fuel hint list on a
    /// shop receipt would name fields the kind does not have; omitting it keeps
    /// the prompt about the document actually sent.
    /// </summary>
    private static object HintsFor(string kind, ExtractHints hints)
    {
        var context = new Dictionary<string, object?> { ["kind"] = kind };
        if (!string.IsNullOrWhiteSpace(hints.Currency))
        {
            context["currency"] = hints.Currency;
        }

        if (!string.IsNullOrWhiteSpace(hints.Locale))
        {
            context["locale"] = hints.Locale;
        }

        if (hints.VehicleFuelKinds is { Count: > 0 })
        {
            context["vehicleFuelKinds"] = hints.VehicleFuelKinds;
        }

        return context;
    }

    /// <summary>The document the image is, in the model's terms.</summary>
    private static string Document(string kind) => kind switch
    {
        "receipt" => "a fuel receipt",
        "pump" => "a fuel pump display",
        "chargeScreenshot" => "an EV charging-app screenshot",
        "invoice" => "a service invoice",
        "expense" => "a shop, parking or toll receipt",
        _ => "a document",
    };

    /// <summary>
    /// The field names the model may return for the kind. A fuel receipt keeps
    /// the pump-card vocabulary; an invoice keeps its header only (the line
    /// items are the device's deterministic split, docs/JOURNEYS.md J7); an
    /// expense names a category and no fuel fields (docs/JOURNEYS.md J7b).
    /// </summary>
    private static string AllowedFields(string kind) => kind switch
    {
        "invoice" => "vendor, total, date, currency",
        "expense" => "total, date, currency, vendor, category",
        _ => "total, volume, unitPrice, date, station, fuelKind, energy, currency, vendor",
    };
}
