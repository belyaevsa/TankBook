namespace Tankbook.Api.Auth;

/// <summary>
/// Bearer authentication for the endpoints that need it (docs/API.md Auth:
/// DELETE /auth/session today, sync/blobs in P4.2/P4.3). Non-blocking: it
/// validates an Authorization: Bearer header when one is present and exposes the
/// account + device identity via <see cref="AuthContext"/>. Public endpoints
/// (health, config, session exchange, refresh) simply see no identity.
/// </summary>
public sealed class BearerAuthenticationMiddleware
{
    private readonly RequestDelegate _next;
    private readonly JwtAccessTokenIssuer _issuer;

    public BearerAuthenticationMiddleware(RequestDelegate next, JwtAccessTokenIssuer issuer)
    {
        _next = next;
        _issuer = issuer;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var token = ReadBearerToken(context);
        if (token is not null && _issuer.TryValidate(token, out var accountId, out var deviceId))
        {
            context.Items[AuthContext.AccountIdKey] = accountId;
            context.Items[AuthContext.DeviceIdKey] = deviceId;
        }

        await _next(context);
    }

    private static string? ReadBearerToken(HttpContext context)
    {
        var header = context.Request.Headers.Authorization.ToString();
        if (string.IsNullOrWhiteSpace(header) ||
            !header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var token = header["Bearer ".Length..].Trim();
        return token.Length == 0 ? null : token;
    }
}
