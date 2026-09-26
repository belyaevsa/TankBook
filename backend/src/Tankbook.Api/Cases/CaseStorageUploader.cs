using System.Diagnostics;
using System.Threading.Channels;
using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Cases;

/// <summary>Wakes the uploader when a case was just accepted, so it does not wait out its interval.</summary>
public sealed class CaseUploadSignal
{
    private readonly Channel<bool> _channel = Channel.CreateBounded<bool>(
        new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropWrite });

    public void Wake() => _channel.Writer.TryWrite(true);

    /// <summary>Waits for a wake or the interval, whichever comes first.</summary>
    public async Task WaitAsync(TimeSpan interval, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(interval);
        try
        {
            await _channel.Reader.ReadAsync(timeout.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
        }
    }
}

/// <summary>
/// Moves accepted cases from the spool to blob storage (docs/API.md "Debug cases").
/// One pass claims a few pending cases, puts every part, marks the case stored and
/// deletes its spool folder. A failed attempt releases the claim and keeps the
/// files; after <see cref="CaseOptions.MaxUploadAttempts"/> the case is recorded
/// as failed with a Warning, never retried forever and never dropped silently.
/// Logs carry the case id, counts, a duration and a reason code only (hard rule 12).
/// </summary>
public sealed class CaseStorageUploader
{
    private const int ClaimBatch = 4;
    private readonly CaseRepository _repository;
    private readonly CaseService _cases;
    private readonly IBlobStorage _storage;
    private readonly CaseOptions _options;
    private readonly ILogger<CaseStorageUploader> _logger;

    public CaseStorageUploader(CaseRepository repository, CaseService cases, IBlobStorage storage,
                               IOptions<CaseOptions> options, ILogger<CaseStorageUploader> logger)
    {
        _repository = repository;
        _cases = cases;
        _storage = storage;
        _options = options.Value;
        _logger = logger;
    }

    /// <summary>
    /// Uploads the pending cases it can claim; returns how many were stored. A pass
    /// claims again only after a full batch that stored completely, so a case that
    /// just failed waits for the next pass instead of spending its attempts at once.
    /// </summary>
    public async Task<int> RunPassAsync(CancellationToken cancellationToken)
    {
        var stored = 0;
        while (true)
        {
            var claimed = await _repository.ClaimPendingAsync(ClaimBatch, _options.UploadClaim, cancellationToken);
            var batchStored = 0;
            foreach (var row in claimed)
            {
                if (await UploadAsync(row, cancellationToken))
                {
                    batchStored++;
                }
            }

            stored += batchStored;
            if (claimed.Count < ClaimBatch || batchStored < claimed.Count)
            {
                return stored;
            }
        }
    }

    private async Task<bool> UploadAsync(CaseRow row, CancellationToken cancellationToken)
    {
        var clock = Stopwatch.StartNew();
        var folder = _cases.SpoolFolder(row.Id);
        string reason;
        try
        {
            foreach (var part in row.Parts)
            {
                var path = Path.Combine(folder, part.Name);
                if (!File.Exists(path))
                {
                    throw new FileNotFoundException("spooled part missing");
                }

                var bytes = await File.ReadAllBytesAsync(path, cancellationToken);
                await _storage.PutObjectAsync(part.Key, bytes, part.ContentType, cancellationToken);
            }

            await _repository.MarkStoredAsync(row.Id, cancellationToken);
            _cases.DeleteSpool(row.Id);
            TankbookLog.CaseStored(_logger, row.Id, row.Parts.Count, row.TotalBytes, (long)clock.Elapsed.TotalMilliseconds);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (FileNotFoundException)
        {
            reason = "spoolMissing";
        }
        catch (Exception)
        {
            reason = "storageError";
        }

        var attempts = await _repository.ReleaseAfterFailureAsync(row.Id, _options.MaxUploadAttempts, CancellationToken.None);
        TankbookLog.CaseStoreFailed(_logger, row.Id, attempts, _options.MaxUploadAttempts, reason);
        return false;
    }
}

/// <summary>The uploader's clock: a pass on every wake and every interval, registered outside test hosts only.</summary>
public sealed class CaseUploadHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly CaseUploadSignal _signal;
    private readonly CaseOptions _options;
    private readonly ILogger<CaseUploadHostedService> _logger;

    public CaseUploadHostedService(IServiceScopeFactory scopeFactory, CaseUploadSignal signal,
                                   IOptions<CaseOptions> options, ILogger<CaseUploadHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _signal = signal;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                await scope.ServiceProvider.GetRequiredService<CaseStorageUploader>().RunPassAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Case upload pass failed.");
            }

            await _signal.WaitAsync(_options.UploadInterval, stoppingToken);
        }
    }
}
