using Tankbook.Api.Auth;

namespace Tankbook.Api.Account;

/// <summary>
/// The account & devices HTTP surface (docs/API.md "Account & devices"). Thin
/// wire handlers: auth, then the service, mapped to 200 / 204 / 401 / 404. A
/// device id belonging to another account is 404 (not 403) - cross-account
/// access is indistinguishable from absence, so no information leaks and no
/// mutation of another account's row is ever attempted.
/// </summary>
public static class AccountEndpoints
{
    public static async Task<IResult> GetDevices(
        HttpContext httpContext,
        AccountService account,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        var devices = await account.GetDevicesAsync(identity.Value.AccountId, cancellationToken);
        return Results.Ok(new DevicesResponse(devices));
    }

    public static async Task<IResult> SetPushToken(
        HttpContext httpContext,
        AccountService account,
        Guid id,
        PushTokenRequest? request,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        // A null/absent/blank token clears the row (APNs invalidation -> polling).
        var token = string.IsNullOrWhiteSpace(request?.ApnsToken) ? null : request.ApnsToken.Trim();

        var status = await account.SetPushTokenAsync(identity.Value.AccountId, id, token, cancellationToken);
        return status switch
        {
            PushTokenStatus.Stored => Results.NoContent(),
            PushTokenStatus.NotFound => Problem(
                StatusCodes.Status404NotFound,
                "Device not found.",
                "No device with this id belongs to this account."),
            _ => throw new InvalidOperationException($"Unknown push-token status {status}."),
        };
    }

    public static async Task<IResult> DeleteDevice(
        HttpContext httpContext,
        AccountService account,
        Guid id,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        var status = await account.RevokeDeviceAsync(identity.Value.AccountId, id, cancellationToken);
        return status switch
        {
            RevokeDeviceStatus.Revoked => Results.NoContent(),
            RevokeDeviceStatus.NotFound => Problem(
                StatusCodes.Status404NotFound,
                "Device not found.",
                "No device with this id belongs to this account."),
            _ => throw new InvalidOperationException($"Unknown revoke-device status {status}."),
        };
    }

    public static async Task<IResult> DeleteAccount(
        HttpContext httpContext,
        AccountService account,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        await account.DeleteAccountAsync(identity.Value.AccountId, cancellationToken);
        return Results.NoContent();
    }

    private static IResult Problem(int status, string title, string detail)
        => Results.Problem(statusCode: status, title: title, detail: detail);
}
