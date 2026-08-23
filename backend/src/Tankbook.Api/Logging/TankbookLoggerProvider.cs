using Microsoft.Extensions.Logging;

namespace Tankbook.Api.Logging;

/// <summary>
/// The pipeline provider: every log call from any call site lands here, is run
/// through the redactor + renderer, and is written as one line. Implements
/// ISupportExternalScope so the factory's scope provider (traceId, accountHash,
/// deviceId pushed by middleware) flows into every emitted line.
/// </summary>
public sealed class TankbookLoggerProvider : ILoggerProvider, ISupportExternalScope
{
    private readonly LogRenderer _renderer;
    private readonly ILogWriter _writer;
    private IExternalScopeProvider? _scopeProvider;

    public TankbookLoggerProvider(LogRenderer renderer, ILogWriter writer)
    {
        _renderer = renderer;
        _writer = writer;
    }

    public void SetScopeProvider(IExternalScopeProvider scopeProvider) => _scopeProvider = scopeProvider;

    public ILogger CreateLogger(string categoryName) => new TankbookLogger(this);

    public void Dispose() { }

    private void Emit(LogLevel level, EventId eventId, object? state, Exception? exception)
    {
        var scopeProperties = new List<KeyValuePair<string, object?>>();
        _scopeProvider?.ForEachScope((scope, list) =>
        {
            switch (scope)
            {
                case IReadOnlyList<KeyValuePair<string, object?>> kvList when kvList.Count > 0:
                    list.AddRange(kvList);
                    break;
                case IEnumerable<KeyValuePair<string, object?>> kvEnum:
                    list.AddRange(kvEnum);
                    break;
            }
        }, scopeProperties);

        var line = _renderer.Render(level, eventId, state, exception, scopeProperties);
        _writer.WriteLine(line);
    }

    private sealed class TankbookLogger : ILogger
    {
        private readonly TankbookLoggerProvider _provider;

        public TankbookLogger(TankbookLoggerProvider provider) => _provider = provider;

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull
            => _provider._scopeProvider?.Push(state);

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
            => _provider.Emit(logLevel, eventId, state, exception);
    }
}
