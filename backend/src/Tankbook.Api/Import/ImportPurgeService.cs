using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Import;

/// <summary>
/// The 30-day import purge (docs/SECURITY.md "Import files at rest": "Purge is a
/// job, not a hope"). Deletes stored parses past the retention cutoff - file,
/// result and index row - and everything inside the window survives. The hosted
/// timer that calls it lives in <see cref="ImportPurgeHostedService"/>, which is
/// not registered in test hosts; L2 tests drive <see cref="PurgeDueAsync"/>
/// directly and assert both sides of the cutoff (docs/TESTING.md).
/// </summary>
public sealed class ImportPurgeService
{
    private readonly ImportService _service;
    private readonly ImportOptions _options;
    private readonly TimeProvider _time;

    public ImportPurgeService(
        ImportService service,
        IOptions<ImportOptions> options,
        TimeProvider time)
    {
        _service = service;
        _options = options.Value;
        _time = time;
    }

    /// <summary>One purge pass: deletes every parse stored longer ago than the retention window, and nothing else.</summary>
    public async Task<int> PurgeDueImportsAsync(CancellationToken cancellationToken)
    {
        var cutoff = _time.GetUtcNow() - _options.RetentionPeriod;
        return await _service.PurgeDueAsync(cutoff, cancellationToken);
    }
}
