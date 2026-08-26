namespace Tankbook.Api.Auth;

/// <summary>
/// The authenticated identity the bearer middleware has established for the
/// current request, carried in HttpContext.Items. Endpoints that require auth
/// read it via <see cref="From"/> and answer 401 when absent.
/// </summary>
public static class AuthContext
{
    public const string AccountIdKey = "Tankbook.AccountId";
    public const string DeviceIdKey = "Tankbook.DeviceId";

    public static (Guid AccountId, Guid DeviceId)? From(HttpContext context)
        => context.Items[AccountIdKey] is Guid accountId && context.Items[DeviceIdKey] is Guid deviceId
            ? (accountId, deviceId)
            : null;
}
