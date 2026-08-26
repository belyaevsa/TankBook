namespace Tankbook.Api.Tests;

/// <summary>A settable <see cref="TimeProvider"/> so "today" can be pinned and advanced deterministically without sleeping.</summary>
public sealed class MutableTimeProvider : TimeProvider
{
    private DateTimeOffset _now;

    public MutableTimeProvider(DateTimeOffset now) => _now = now;

    public override DateTimeOffset GetUtcNow() => _now;

    public void SetUtcNow(DateTimeOffset now) => _now = now;

    public void Advance(TimeSpan span) => _now += span;
}
