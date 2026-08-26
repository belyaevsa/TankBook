using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Tankbook.Api.Llm;

/// <summary>
/// The real cloud-vision provider (docs/EXTRACTION.md "The P4.12 measurement").
/// Talks the OpenAI-compatible chat-completions wire shape to the configured
/// <see cref="LlmGatewayOptions.BaseUrl"/>, sending the image inline as a base64
/// data URL and asking for one JSON object: a <c>fields</c> array of
/// <c>{ name, value, confidence }</c> entries plus the standard <c>usage</c>
/// token counts. The vendor is configuration (base URL, key, model id) - nothing
/// here is hard-coded to a specific provider, and the endpoint never references
/// this class directly (it goes through <see cref="ILlmProvider"/>).
///
/// This implementation is not exercised by the suite (docs/TESTING.md): the L2
/// tests drive the seam with a recording double, so no paid call and no real key
/// is ever used. The API key stays inside this class and is never logged
/// (docs/SECURITY.md, hard rule 12). The image bytes live only for the request's
/// duration; nothing is written to disk, blob storage, or a log line.
/// </summary>
public sealed class OpenAiCompatibleLlmProvider : ILlmProvider
{
    private readonly HttpClient _http;
    private readonly LlmGatewayOptions _options;

    public OpenAiCompatibleLlmProvider(IHttpClientFactory httpClientFactory, IOptions<LlmGatewayOptions> options)
    {
        _http = httpClientFactory.CreateClient();
        _options = options.Value;
    }

    public async Task<LlmExtraction> ExtractAsync(
        string kind,
        byte[] imageBytes,
        ExtractHints hints,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.BaseUrl) ||
            string.IsNullOrWhiteSpace(_options.ApiKey) ||
            string.IsNullOrWhiteSpace(_options.ModelId))
        {
            throw new InvalidOperationException("The LLM provider is not configured (LlmGateway:BaseUrl/ApiKey/ModelId).");
        }

        var requestBody = JsonSerializer.Serialize(new
        {
            model = _options.ModelId,
            messages = new object[]
            {
                new { role = "system", content = SystemPrompt(kind, hints) },
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new
                        {
                            type = "text",
                            text = "Extract the fuel fields from this image as the JSON object described.",
                        },
                        new
                        {
                            type = "image_url",
                            image_url = new { url = DataUrl(imageBytes) },
                        },
                    },
                },
            },
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, _options.BaseUrl.TrimEnd('/') + "/chat/completions");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        request.Content = new StringContent(requestBody, Encoding.UTF8, "application/json");

        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var root = document.RootElement;
        var model = root.TryGetProperty("model", out var modelElement) ? modelElement.GetString() ?? _options.ModelId : _options.ModelId;

        long promptTokens = 0;
        long completionTokens = 0;
        if (root.TryGetProperty("usage", out var usage))
        {
            promptTokens = usage.TryGetProperty("prompt_tokens", out var p) ? p.GetInt64() : 0;
            completionTokens = usage.TryGetProperty("completion_tokens", out var c) ? c.GetInt64() : 0;
        }

        var fields = ParseFields(root);
        return new LlmExtraction(fields, model, promptTokens, completionTokens);
    }

    private static string SystemPrompt(string kind, ExtractHints hints)
    {
        var hintsJson = JsonSerializer.Serialize(new
        {
            kind,
            hints = new
            {
                currency = hints.Currency,
                locale = hints.Locale,
                vehicleFuelKinds = hints.VehicleFuelKinds,
            },
        });

        return "You extract fuel-purchase fields from an image. " +
               "Respond with a single JSON object and nothing else: " +
               "{ \"fields\": [ { \"name\": string, \"value\": number|string, \"confidence\": 0..1 } ] }. " +
               "Allowed field names: total, volume, unitPrice, date, station, fuelKind, energy, currency, vendor. " +
               "A field you cannot read is omitted, never guessed. Request context: " + hintsJson;
    }

    private static string DataUrl(byte[] imageBytes)
        => "data:image/jpeg;base64," + Convert.ToBase64String(imageBytes);

    private static IReadOnlyDictionary<string, LlmField> ParseFields(JsonElement root)
    {
        var result = new Dictionary<string, LlmField>(StringComparer.Ordinal);

        var content = root.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0
            ? choices[0].TryGetProperty("message", out var message) ? message : default
            : default;
        if (content.ValueKind == JsonValueKind.Undefined)
        {
            return result;
        }

        var text = content.TryGetProperty("content", out var contentValue) && contentValue.ValueKind == JsonValueKind.String
            ? contentValue.GetString()
            : null;
        if (text is null)
        {
            return result;
        }

        using var document = JsonDocument.Parse(ExtractJsonObject(text));
        if (!document.RootElement.TryGetProperty("fields", out var fields) || fields.ValueKind != JsonValueKind.Array)
        {
            return result;
        }

        foreach (var field in fields.EnumerateArray())
        {
            if (!field.TryGetProperty("name", out var nameElement) || nameElement.GetString() is not { Length: > 0 } name)
            {
                continue;
            }

            if (!field.TryGetProperty("value", out var valueElement) || valueElement.ValueKind == JsonValueKind.Null)
            {
                continue;
            }

            var confidence = field.TryGetProperty("confidence", out var confidenceElement) &&
                             confidenceElement.ValueKind == JsonValueKind.Number
                ? confidenceElement.GetDouble()
                : 0;

            result[name] = new LlmField(valueElement.Clone(), confidence);
        }

        return result;
    }

    /// <summary>
    /// The model may wrap its JSON in a markdown code fence; strip it so the body
    /// parses. A model that refuses to return JSON yields an empty field set, not
    /// a throw - the gateway then answers 200 with no fields and the client falls
    /// back to what it read on-device (JOURNEYS F4).
    /// </summary>
    private static string ExtractJsonObject(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.StartsWith("```", StringComparison.Ordinal))
        {
            var newline = trimmed.IndexOf('\n');
            if (newline >= 0)
            {
                trimmed = trimmed[(newline + 1)..].TrimEnd();
            }

            var fenceEnd = trimmed.LastIndexOf("```", StringComparison.Ordinal);
            if (fenceEnd >= 0)
            {
                trimmed = trimmed[..fenceEnd].Trim();
            }
        }

        var open = trimmed.IndexOf('{');
        var close = trimmed.LastIndexOf('}');
        return open >= 0 && close > open ? trimmed[open..(close + 1)] : "{}";
    }
}
