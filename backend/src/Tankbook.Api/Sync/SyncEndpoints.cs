using Tankbook.Api.Auth;

namespace Tankbook.Api.Sync;

/// <summary>
/// The sync HTTP surface (docs/API.md Sync). Bearer endpoints; thin wire
/// handlers: identity + request-shape checks, then the service, mapped to
/// 200 / 401 / 410 / 426 / 400. Both endpoints are idempotent and partial
/// batch success is the contract, so the endpoint never all-or-nothings a batch.
/// </summary>
public static class SyncEndpoints
{
    public static async Task<IResult> Pull(
        HttpContext httpContext,
        SyncService sync,
        long? since,
        int? limit,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        var sinceScn = since ?? 0;
        if (sinceScn < 0)
        {
            return Problem(StatusCodes.Status400BadRequest, "Invalid cursor.", "since must be >= 0.");
        }

        var effectiveLimit = limit is null
            ? SyncService.MaxPullLimit
            : Math.Clamp(limit.Value, 1, SyncService.MaxPullLimit);

        var outcome = await sync.PullAsync(identity.Value.AccountId, identity.Value.DeviceId, sinceScn, effectiveLimit, cancellationToken);
        return outcome.Status switch
        {
            PullStatus.Ok => Results.Ok(outcome.Response),
            PullStatus.DeviceRevoked => Revoked(),
            _ => throw new InvalidOperationException($"Unknown pull status {outcome.Status}."),
        };
    }

    public static async Task<IResult> Push(
        HttpContext httpContext,
        SyncService sync,
        PushRequest request,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        if (request.Changes is null)
        {
            return Problem(StatusCodes.Status400BadRequest, "Malformed body.", "changes is required.");
        }

        if (request.Changes.Count > SyncService.MaxChangesPerBatch)
        {
            return Problem(StatusCodes.Status400BadRequest, "Batch too large.", $"A push batch holds at most {SyncService.MaxChangesPerBatch} changes.");
        }

        var outcome = await sync.PushAsync(identity.Value.AccountId, identity.Value.DeviceId, request.Changes, cancellationToken);
        return outcome.Status switch
        {
            PushStatus.Ok => Results.Ok(new PushResponse(outcome.Results!)),
            PushStatus.DeviceRevoked => Revoked(),
            PushStatus.UpgradeRequired => Problem(
                StatusCodes.Status426UpgradeRequired,
                "Upgrade required.",
                "The client's schema_version is below the server's minimum supported version. Update the app; pulling still works."),
            _ => throw new InvalidOperationException($"Unknown push status {outcome.Status}."),
        };
    }

    private static IResult Revoked()
        => Problem(
            StatusCodes.Status410Gone,
            "Device revoked or account deleted.",
            "This device has been revoked or the account was deleted. Re-onboard or detach; local data stays local.");

    private static IResult Problem(int status, string title, string detail)
        => Results.Problem(statusCode: status, title: title, detail: detail);
}
