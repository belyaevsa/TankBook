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
    /// <summary>
    /// The field-name prefix of an invoice line item: <c>lineItem[n].title</c>,
    /// <c>lineItem[n].category</c>, <c>lineItem[n].amount</c>, n from 0 in
    /// printed order. The device pairs them onto its own split; the server never
    /// reads them (hard rule 9).
    /// </summary>
    public const string LineItemPrefix = "lineItem[";

    /// <summary>The system message: the JSON shape, the kind's allowed field names, and the request hints.</summary>
    public static string SystemPrompt(string kind, ExtractHints hints) => SystemPrompt(kind, hints, lineItems: false, pageCount: 1);

    /// <summary>
    /// The multi-page form (docs/API.md "multi-page invoices"): the pages are
    /// one document in order, and an invoice asked for its line items returns
    /// them as indexed <c>lineItem[n].*</c> fields beside the header.
    /// </summary>
    public static string SystemPrompt(string kind, ExtractHints hints, bool lineItems, int pageCount)
    {
        var hintsJson = JsonSerializer.Serialize(HintsFor(kind, hints));
        var subject = pageCount > 1
            ? $"{pageCount} images that are the pages, in order, of {Document(kind)}"
            : $"an image of {Document(kind)}";

        return $"You extract fields from {subject}. " +
               "Respond with a single JSON object and nothing else: " +
               "{ \"fields\": [ { \"name\": string, \"value\": number|string, \"confidence\": 0..1 } ] }. " +
               $"Allowed field names: {AllowedFields(kind, lineItems)}. " +
               (lineItems ? LineItemInstruction : string.Empty) +
               "A field you cannot read is omitted, never guessed. Request context: " + hintsJson;
    }

    /// <summary>The user message: names the document so the model reads the right fields.</summary>
    public static string UserMessage(string kind) => UserMessage(kind, pageCount: 1);

    public static string UserMessage(string kind, int pageCount)
        => pageCount > 1
            ? $"Extract the fields from these {pageCount} pages of {Document(kind)}, read in order, as the JSON object described."
            : $"Extract the fields from this image of {Document(kind)} as the JSON object described.";

    private const string LineItemInstruction =
        "Each billed line is one item: lineItem[n].title (the printed text), lineItem[n].amount (that line's total), " +
        "and lineItem[n].category when the line is clearly parts, labour, oil, tyres, or a fee, else omit it; " +
        "n counts from 0 in printed order across all pages. The header total is the invoice's grand total. ";

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
    /// the pump-card vocabulary; an invoice keeps its header, plus its line
    /// items when the multi-page shape asked for them (the device pairs them
    /// onto its deterministic split, docs/JOURNEYS.md J7); an expense names a
    /// category and no fuel fields (docs/JOURNEYS.md J7b).
    /// </summary>
    private static string AllowedFields(string kind, bool lineItems) => kind switch
    {
        "invoice" when lineItems =>
            "vendor, total, date, currency, lineItem[n].title, lineItem[n].category, lineItem[n].amount",
        "invoice" => "vendor, total, date, currency",
        "expense" => "total, date, currency, vendor, category",
        _ => "total, volume, unitPrice, date, station, fuelKind, energy, currency, vendor",
    };
}
