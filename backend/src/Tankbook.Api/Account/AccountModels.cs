namespace Tankbook.Api.Account;

/// <summary>One registered device as served by GET /account/devices (docs/API.md).</summary>
public sealed record AccountDevice(Guid Id, string Name, string Platform, DateTimeOffset LastSeenAt, bool Revoked);

/// <summary>GET /account/devices response: this account's devices, revoked ones marked.</summary>
public sealed record DevicesResponse(IReadOnlyList<AccountDevice> Devices);

/// <summary>PUT /account/devices/{id}/push-token body. A null/absent/blank token clears the row.</summary>
public sealed record PushTokenRequest(string? ApnsToken);

/// <summary>PUT /account/devices/{id}/push-token outcome.</summary>
public enum PushTokenStatus
{
    Stored,
    NotFound,
}

/// <summary>DELETE /account/devices/{id} outcome.</summary>
public enum RevokeDeviceStatus
{
    Revoked,
    NotFound,
}
