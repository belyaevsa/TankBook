namespace Tankbook.Api.Logging;

/// <summary>
/// Where a rendered log line lands. The production implementation writes to
/// stdout; tests swap in an in-memory writer so assertions run against the real
/// emitted output of the pipeline.
/// </summary>
public interface ILogWriter
{
    void WriteLine(string line);
}

/// <summary>Writes one line to stdout (docs/LOGGING.md §3: structured JSON to stdout).</summary>
public sealed class ConsoleLogWriter : ILogWriter
{
    private static readonly TextWriter Stdout = TextWriter.Synchronized(Console.Out);

    public void WriteLine(string line) => Stdout.WriteLine(line);
}
