using Microsoft.Extensions.Logging;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// An in-memory ILogger so tests can assert on the real emitted event name and
/// level (docs/LOGGING.md). The state dict carries the "Event" field that
/// TankbookLog sets; the event name is what call sites assert on.
/// </summary>
internal sealed class CaptureLogger<T> : ILogger<T>
{
    public sealed record Entry(LogLevel Level, string Event, string Message);

    public List<Entry> Entries { get; } = new();

    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
    {
        var eventName = (state as IReadOnlyDictionary<string, object?>)?.GetValueOrDefault("Event") as string;
        Entries.Add(new Entry(logLevel, eventName ?? formatter(state, exception), formatter(state, exception)));
    }

    public bool Any(LogLevel level, string eventName)
        => Entries.Any(e => e.Level == level && e.Event == eventName);
}
