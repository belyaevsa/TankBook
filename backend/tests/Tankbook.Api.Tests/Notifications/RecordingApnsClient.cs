using Tankbook.Api.Notifications;

namespace Tankbook.Api.Tests.Notifications;

/// <summary>
/// A recording <see cref="IApnsClient"/> double (docs/TESTING.md "mock the
/// boundary"): records every (token, payload) it was handed and returns a
/// scripted outcome - delivered by default, or whatever <see cref="OnSend"/>
/// decides, or an exception when it throws. No network, no credential. Tests
/// assert on the recorded sends: to whom (never the pusher), how many (the
/// throttle), and the exact payload (silent, no alert/sound/badge).
/// </summary>
public sealed class RecordingApnsClient : IApnsClient
{
    private readonly List<(string Token, string PayloadJson)> _sends = [];

    /// <summary>Scripted per-send behavior. Throwing here models a provider that is entirely down.</summary>
    public Func<string, string, ApnsSendResult>? OnSend { get; set; }

    public IReadOnlyList<(string Token, string PayloadJson)> Sends => _sends;

    public Task<ApnsSendResult> SendAsync(string deviceToken, string payloadJson, CancellationToken cancellationToken)
    {
        _sends.Add((deviceToken, payloadJson));
        return Task.FromResult(
            OnSend?.Invoke(deviceToken, payloadJson) ?? new ApnsSendResult(ApnsOutcome.Delivered));
    }
}
