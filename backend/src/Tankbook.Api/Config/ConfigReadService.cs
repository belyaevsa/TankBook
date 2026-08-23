using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Config;

/// <summary>
/// Selects the config document to serve (docs/CONFIG.md "Delivery", docs/API.md
/// GET /config): the highest published version whose validity window is still
/// open (published_at in the past, not_after in the future). If no document is
/// valid - everything is expired, or nothing is published yet - the latest is
/// served anyway with a WARN, because the designed client behaviour is to reject
/// an expired document and fall back to bundled defaults (docs/CONFIG.md
/// "Failure behaviour"), and a fallback-to-bundled-defaults is safer than a hard
/// failure for every client.
/// </summary>
public sealed class ConfigReadService : IConfigReadService
{
    private readonly ConfigRepository _repository;
    private readonly ILogger<ConfigReadService> _logger;
    private readonly TimeProvider _time;

    public ConfigReadService(ConfigRepository repository, ILogger<ConfigReadService> logger)
        : this(repository, logger, TimeProvider.System)
    {
    }

    internal ConfigReadService(ConfigRepository repository, ILogger<ConfigReadService> logger, TimeProvider time)
    {
        _repository = repository;
        _logger = logger;
        _time = time;
    }

    public async Task<ConfigServeResult?> GetForServingAsync(CancellationToken cancellationToken)
    {
        var rows = await _repository.GetAllDescendingAsync(cancellationToken);
        if (rows.Count == 0)
        {
            return null;
        }

        var now = _time.GetUtcNow();
        var best = rows.FirstOrDefault(r => r.PublishedAt <= now && r.NotAfter > now);

        if (best is null)
        {
            // Every document is expired or unpublished. Serve the latest anyway
            // and say so; the client will reject an expired document and fall
            // back to bundled defaults, which is the designed behaviour.
            best = rows[0];
            TankbookLog.ConfigExpiredFallback(_logger, best.Version);
        }

        return new ConfigServeResult(best.Version, best.Document, best.Signature);
    }
}
