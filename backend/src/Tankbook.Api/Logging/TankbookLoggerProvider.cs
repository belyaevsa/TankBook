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

    public ILogger CreateLogger(string categoryName) => new TankbookLogger(this, categoryName);

    public void Dispose() { }

    private void Emit(string category, LogLevel level, EventId eventId, object? state, Exception? exception)
    {
        if (IsClientAbortNoise(category, exception))
        {
            return;
        }

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

        var line = _renderer.Render(category, level, eventId, state, exception, scopeProperties);
        _writer.WriteLine(line);
    }

    /// <summary>
    /// Kestrel's "Connection processing ended abnormally" with "Reading is
    /// already in progress" is how the server reports a client that hung up
    /// mid-upload - a bare ASP.NET app logs the same line for the same socket
    /// close. It carries no fault of ours, and rendered it read as a WARNING with
    /// errorCode=internal_error. The request's own line records the event as
    /// 499 (TraceCorrelationMiddleware.LoggedStatus), so this one is dropped;
    /// any other Kestrel error still logs.
    /// </summary>
    internal static bool IsClientAbortNoise(string category, Exception? exception)
        => category == "Microsoft.AspNetCore.Server.Kestrel"
           && exception is InvalidOperationException { Message: "Reading is already in progress." };

    private sealed class TankbookLogger : ILogger
    {
        private readonly TankbookLoggerProvider _provider;

        /// <summary>
        /// The logger's category - the type that logged. It was DISCARDED here
        /// until 2026-09-03: `CreateLogger` took the name and threw it away, so
        /// no line could say who wrote it. The text format now leads with it.
        /// </summary>
        private readonly string _category;

        public TankbookLogger(TankbookLoggerProvider provider, string category)
        {
            _provider = provider;
            _category = category;
        }

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
            => _provider.Emit(_category, logLevel, eventId, state, exception);
    }
}
