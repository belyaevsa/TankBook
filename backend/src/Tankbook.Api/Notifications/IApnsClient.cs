namespace Tankbook.Api.Notifications;

/// <summary>How a single APNs send resolved. The nudge layer only ever acts on <see cref="InvalidToken"/>.</summary>
public enum ApnsOutcome
{
    /// <summary>APNs accepted the push.</summary>
    Delivered,

    /// <summary>APNs says the token is dead (BadDeviceToken, Unregistered): the row must be cleared so the device falls back to polling.</summary>
    InvalidToken,

    /// <summary>Everything else (5xx, timeout, 429, provider-token trouble, not configured): retry later, keep the token.</summary>
    TransientFailure,
}

/// <summary>The outcome of one APNs send, with an optional machine reason code (never the token).</summary>
public sealed record ApnsSendResult(ApnsOutcome Outcome, string? Reason = null);

/// <summary>
/// The APNs send seam (docs/TESTING.md "mock the boundary"): the nudge layer
/// talks to Apple only through this interface, so the L2 suite swaps in a
/// recording double and asserts throttle + invalidation behavior without any
/// network. The production implementation is <see cref="ApnsClient"/>; the
/// payload it is handed is already the complete silent body (see
/// <see cref="ApnsPayload"/>), so the transport never composes user-visible
/// content - there is none.
/// </summary>
public interface IApnsClient
{
    /// <summary>Sends one silent push. Returns an outcome, never throws: a transport failure is a <see cref="ApnsOutcome.TransientFailure"/>.</summary>
    Task<ApnsSendResult> SendAsync(string deviceToken, string payloadJson, CancellationToken cancellationToken);
}
