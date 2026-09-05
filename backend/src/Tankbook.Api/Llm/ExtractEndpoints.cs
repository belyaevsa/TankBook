using System.Globalization;
using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

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
            return Problem(
                StatusCodes.Status401Unauthorized,
                TankbookErrorCodes.TokenInvalid,
                "Authentication required.",
                "A valid bearer token is required.");
        }

        if (request is null || !ExtractKinds.IsValid(request.Kind))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Invalid extraction request.",
                "kind must be one of receipt, pump, chargeScreenshot, invoice.");
        }

        var hints = request.Hints ?? new ExtractHints(null, null, null);
        var outcome = await service.ExtractAsync(identity.Value.AccountId, identity.Value.DeviceId, request.Kind!, request.Image, hints, request.CaptureId, cancellationToken);
        return outcome.Status switch
        {
            ExtractStatus.Ok => Results.Ok(outcome.Response),
            // RV.44: the answer was queued in the outbox because the client is
            // gone. There is nobody to answer, so return 204 rather than write a
            // response into a void; the device drains the outbox on next launch.
            ExtractStatus.DeliveredViaOutbox => Results.NoContent(),
            ExtractStatus.ImageMissing => Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Missing image.",
                "image is required and must be a base64-encoded JPEG/PNG rendition."),
            ExtractStatus.ImageInvalid => Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Invalid image.",
                "image must be a valid base64 string."),
            ExtractStatus.ImageTooLarge => Problem(
                StatusCodes.Status413PayloadTooLarge,
                TankbookErrorCodes.PayloadTooLarge,
                "Payload too large.",
                "The base64 image may be at most 4 MB."),
            ExtractStatus.TierLacksQuota => Problem(
                StatusCodes.Status402PaymentRequired,
                TankbookErrorCodes.TierRefused,
                "No extraction allowance.",
                "This account's tier has no cloud-extraction allowance."),
            ExtractStatus.QuotaSpent => QuotaSpent(httpContext, outcome),
            ExtractStatus.ProviderFailed => Problem(
                StatusCodes.Status502BadGateway,
                TankbookErrorCodes.UpstreamUnavailable,
                "Extraction provider unavailable.",
                "The extraction provider could not answer; continue with the on-device result."),
            _ => throw new InvalidOperationException($"Unknown extract status {outcome.Status}."),
        };
    }

    private static IResult Problem(int status, string code, string title, string detail)
        => ProblemResponses.Problem(status, code, title, detail);

    /// <summary>The period is spent, so the 429 names when the next period begins (Retry-After, hard rule 7).</summary>
    private static IResult QuotaSpent(HttpContext httpContext, ExtractOutcome outcome)
    {
        if (outcome.RetryAfterSeconds > 0)
        {
            httpContext.Response.Headers.RetryAfter =
                outcome.RetryAfterSeconds.ToString(CultureInfo.InvariantCulture);
        }

        return Problem(
            StatusCodes.Status429TooManyRequests,
            TankbookErrorCodes.RateLimited,
            "Extraction allowance spent.",
            "This period's cloud-extraction allowance is used up; try again next period.");
    }
}
