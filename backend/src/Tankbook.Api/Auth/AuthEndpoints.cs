namespace Tankbook.Api.Auth;

/// <summary>POST /auth/session body (docs/API.md Auth).</summary>
public sealed record CreateSessionRequest(string? Provider, string? IdToken, DeviceInfo? Device);

/// <summary>The device descriptor in a session exchange.</summary>
public sealed record DeviceInfo(string? Name, string? Platform);

/// <summary>POST /auth/refresh body (docs/API.md Auth).</summary>
public sealed record RefreshRequest(string? RefreshToken);

/// <summary>POST /auth/session response.</summary>
public sealed record SessionResponse(string AccessToken, string RefreshToken, Guid AccountId, Guid DeviceId);

/// <summary>POST /auth/refresh response.</summary>
public sealed record RefreshResponse(string AccessToken, string RefreshToken);

/// <summary>
/// The auth HTTP surface (docs/API.md Auth). Thin wire handlers: request-shape
/// validation (400), then the service, mapped to 200 / 401 / 204. No token,
/// idToken, or email ever enters a log line or a problem+json body.
/// </summary>
public static class AuthEndpoints
{
    public static async Task<IResult> CreateSession(
        AuthService auth,
        CreateSessionRequest request,
        CancellationToken cancellationToken)
    {
        var provider = request.Provider?.Trim();
        if (provider is not ("apple" or "google"))
        {
            return Problem(StatusCodes.Status400BadRequest, "Unsupported provider.", "provider must be \"apple\" or \"google\".");
        }

        if (string.IsNullOrWhiteSpace(request.IdToken))
        {
            return Problem(StatusCodes.Status400BadRequest, "Missing identity token.", "idToken is required.");
        }

        if (string.IsNullOrWhiteSpace(request.Device?.Name) || string.IsNullOrWhiteSpace(request.Device?.Platform))
        {
            return Problem(StatusCodes.Status400BadRequest, "Missing device details.", "device.name and device.platform are required.");
        }

        var result = await auth.ExchangeAsync(provider, request.IdToken, request.Device!.Name!, request.Device.Platform!, cancellationToken);
        if (!result.Success)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Invalid identity token.", result.FailureReason ?? "invalid_token");
        }

        return Results.Ok(new SessionResponse(result.AccessToken!, result.RefreshToken!, result.AccountId!.Value, result.DeviceId!.Value));
    }

    public static async Task<IResult> Refresh(AuthService auth, RefreshRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            return Problem(StatusCodes.Status400BadRequest, "Missing refresh token.", "refreshToken is required.");
        }

        var result = await auth.RefreshAsync(request.RefreshToken, cancellationToken);
        if (!result.Success)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Invalid refresh token.", result.FailureReason ?? "invalid_refresh_token");
        }

        return Results.Ok(new RefreshResponse(result.AccessToken!, result.RefreshToken!));
    }

    public static async Task<IResult> SignOut(AuthService auth, HttpContext httpContext, CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(StatusCodes.Status401Unauthorized, "Authentication required.", "A valid bearer token is required.");
        }

        await auth.SignOutAsync(identity.Value.DeviceId, cancellationToken);
        return Results.NoContent();
    }

    private static IResult Problem(int status, string title, string detail)
        => Results.Problem(statusCode: status, title: title, detail: detail);
}
