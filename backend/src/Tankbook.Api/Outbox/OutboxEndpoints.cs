using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Outbox;

/// <summary>One queued delivery on the wire: the row id and the opaque payload, base64-encoded (the server never parses it).</summary>
public sealed record OutboxItemResponse(Guid Id, string Payload);

/// <summary>The drain response: every pending delivery for this device, oldest first. Never more than a list of opaque rows.</summary>
public sealed record OutboxDrainResponse(IReadOnlyList<OutboxItemResponse> Items);

/// <summary>
/// The delivery-outbox HTTP surface (docs/API.md "Delivery outbox"). Thin wire
/// handlers: bearer auth, then the service. GET drains (read-only - the ack is
/// the DELETE); DELETE acks one collected row, idempotently and scoped to the
/// caller's own device, so a foreign id is indistinguishable from absence (no
/// existence leak, the blob/import 404 principle). The payload leaves the
/// server base64-encoded and is never decoded or read here - the server offers
/// no search, stats or read-by-meaning over it (hard rule 9).
/// </summary>
public static class OutboxEndpoints
{
    public static async Task<IResult> Drain(
        HttpContext httpContext,
        OutboxService outbox,
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

        var rows = await outbox.DrainAsync(identity.Value.AccountId, identity.Value.DeviceId, cancellationToken);
        var items = rows
            .Select(row => new OutboxItemResponse(row.Id, Convert.ToBase64String(row.Payload)))
            .ToList();
        return Results.Ok(new OutboxDrainResponse(items));
    }

    public static async Task<IResult> Ack(
        HttpContext httpContext,
        OutboxService outbox,
        Guid id,
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

        await outbox.AckAsync(identity.Value.AccountId, identity.Value.DeviceId, id, cancellationToken);
        return Results.NoContent();
    }

    private static IResult Problem(int status, string code, string title, string detail)
        => ProblemResponses.Problem(status, code, title, detail);
}
