using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// A scripted <see cref="IRateFeed"/> double (docs/TESTING.md "mock the
/// boundary"): the daily job talks to the feed only through this interface, so
/// the L2 suite never touches the ECB/CIS network. The handler is reassignable
/// between passes, which is what the append-only and correction tests use to make
/// a re-fetch return a different value.
/// </summary>
public sealed class RecordingRateFeed : IRateFeed
{
    private Func<DateOnly, string, IReadOnlyList<RateQuote>> _handler;

    public RecordingRateFeed(string source)
    {
        Source = source;
        _handler = static (_, _) => [];
    }

    public string Source { get; }

    public void SetHandler(Func<DateOnly, string, IReadOnlyList<RateQuote>> handler) => _handler = handler;

    public Task<IReadOnlyList<RateQuote>> FetchAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
        => Task.FromResult(_handler(date, baseCurrency));
}
