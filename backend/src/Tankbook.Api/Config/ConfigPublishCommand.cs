namespace Tankbook.Api.Config;

/// <summary>
/// The operator's publish path for config documents (docs/CONFIG.md -> Delivery):
/// <c>dotnet Tankbook.Api.dll --publish-config &lt;file&gt;</c>, run on the host
/// that holds <c>Config:SigningKey</c>. It reads the document, hands it to
/// <see cref="ConfigPublishService"/> - schema, version monotonicity, signing,
/// insert - prints the outcome and returns the process exit code. There is no
/// HTTP route: publishing stays an operator action on the host.
/// </summary>
public static class ConfigPublishCommand
{
    public const string Flag = "--publish-config";

    /// <summary>The exit code for a usage error: no file named, or it cannot be read.</summary>
    public const int UsageError = 2;

    /// <summary>
    /// Whether <see cref="Flag"/> is on the command line; <paramref name="path"/> is
    /// the argument after it, null when none follows.
    /// </summary>
    public static bool IsRequested(string[] args, out string? path)
    {
        var index = Array.IndexOf(args, Flag);
        path = index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
        return index >= 0;
    }

    /// <summary>
    /// Publishes the document at <paramref name="path"/>: 0 when it is published,
    /// 1 when the service refuses it (the refusal kind and detail are printed),
    /// <see cref="UsageError"/> when there is no readable file.
    /// </summary>
    public static async Task<int> RunAsync(
        IServiceProvider services, string? path, TextWriter output, TextWriter error,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            await error.WriteLineAsync(
                $"{Flag} needs the document's path: dotnet Tankbook.Api.dll {Flag} <file.json>");
            return UsageError;
        }

        string document;
        try
        {
            document = await File.ReadAllTextAsync(path, cancellationToken);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            await error.WriteLineAsync($"{Flag}: cannot read {path} ({exception.GetType().Name}); check the path and its permissions.");
            return UsageError;
        }

        await using var scope = services.CreateAsyncScope();
        var publisher = scope.ServiceProvider.GetRequiredService<ConfigPublishService>();
        var result = await publisher.PublishAsync(document, cancellationToken);
        if (result.IsSuccess)
        {
            await output.WriteLineAsync(
                $"published config version {result.Version}; devices pick it up on their next config poll.");
            return 0;
        }

        await error.WriteLineAsync($"refused ({result.Error.Kind}): {result.Error.Detail}");
        return 1;
    }
}
