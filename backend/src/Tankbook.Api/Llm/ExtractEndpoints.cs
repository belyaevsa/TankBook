using Tankbook.Api.Auth;

namespace Tankbook.Api.Llm;

/// <summary>
/// The LLM gateway HTTP surface (docs/API.md "LLM gateway (Pro)"): POST
/// /v1/extract. Thin wire handler: auth, input shape (kind), then the service,
/// mapped to 200 / 400 / 401 / 402 / 413 / 429 / 502. The 402 (tier lacks quota)
/// and 429 (period spent) are two distinct conditions with two distinct codes -
/// the client falls back to the on-device result on either, never an upsell
/// mid-capture (JOURNEYS F4). The response is exactly the ExtractionMeta shape:
/// field values with per-field confidence, never a domain judgement (hard rule 9).
/// </summary>
public static class ExtractEndpoints
{
    public static async Task<IResult> Extract(
        HttpContext httpContext,
        LlmService service,
        ExtractRequest? request,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        if (request is null || !ExtractKinds.IsValid(request.Kind))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Invalid extraction request.",
                "kind must be one of receipt, pump, chargeScreenshot, invoice.");
        }

        var hints = request.Hints ?? new ExtractHints(null, null, null);
        var outcome = await service.ExtractAsync(identity.Value.AccountId, request.Kind!, request.Image, hints, cancellationToken);
        return outcome.Status switch
        {
            ExtractStatus.Ok => Results.Ok(outcome.Response),
            ExtractStatus.ImageMissing => Problem(
                StatusCodes.Status400BadRequest,
                "Missing image.",
                "image is required and must be a base64-encoded JPEG/PNG rendition."),
            ExtractStatus.ImageInvalid => Problem(
                StatusCodes.Status400BadRequest,
                "Invalid image.",
                "image must be a valid base64 string."),
            ExtractStatus.ImageTooLarge => Problem(
                StatusCodes.Status413PayloadTooLarge,
                "Payload too large.",
                "The base64 image may be at most 4 MB."),
            ExtractStatus.TierLacksQuota => Problem(
                StatusCodes.Status402PaymentRequired,
                "No extraction allowance.",
                "This account's tier has no cloud-extraction allowance."),
            ExtractStatus.QuotaSpent => Problem(
                StatusCodes.Status429TooManyRequests,
                "Extraction allowance spent.",
                "This period's cloud-extraction allowance is used up; try again next period."),
            ExtractStatus.ProviderFailed => Problem(
                StatusCodes.Status502BadGateway,
                "Extraction provider unavailable.",
                "The extraction provider could not answer; continue with the on-device result."),
            _ => throw new InvalidOperationException($"Unknown extract status {outcome.Status}."),
        };
    }

    private static IResult Problem(int status, string title, string detail)
        => Results.Problem(statusCode: status, title: title, detail: detail);
}
