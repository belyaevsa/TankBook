using Microsoft.AspNetCore.Mvc;
using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Feedback;

/// <summary>
/// The feedback HTTP surface (docs/API.md "Feedback"): POST /v1/feedback,
/// public with the bearer optional. A user with no account can complain too -
/// the account id attaches when a token is present, and its absence is not an
/// error. 202 means accepted, which is what the outbox client expects; the row
/// is written before the response. Nothing but shape is ever logged (hard rule
/// 12). The body cap and the rate limit are PR.17's real machinery
/// (BodySizeLimits / AddTankbookRateLimiting), never a local reimplementation.
/// </summary>
public static class FeedbackEndpoints
{
    public static async Task<IResult> Submit(
        FeedbackService feedback,
        FeedbackRequest request,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        if (!FeedbackCategories.IsValid(request.Category))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Unsupported category.",
                "category must be \"feature\", \"problem\", or \"other\".");
        }

        if (string.IsNullOrWhiteSpace(request.Text))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Missing feedback text.",
                "text is required.");
        }

        if (string.IsNullOrWhiteSpace(request.AppVersion))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Missing app version.",
                "appVersion is required.");
        }

        // The bearer is optional (docs/API.md): with a token the case is
        // attributed to the account; signed out, account_id stays NULL.
        var accountId = AuthContext.From(httpContext)?.AccountId;

        await feedback.SubmitAsync(
            request.Category!,
            request.Text,
            request.AppVersion,
            request.DeviceModel,
            request.ReplyTo,
            accountId,
            cancellationToken);

        return Results.StatusCode(StatusCodes.Status202Accepted);
    }

    private static IResult Problem(int status, string code, string title, string detail)
        => ProblemResponses.Problem(status, code, title, detail);
}
