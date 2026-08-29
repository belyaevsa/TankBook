using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Llm;

/// <summary>POST /extract outcome.</summary>
public enum ExtractStatus
{
    Ok,
    ImageMissing,
    ImageInvalid,
    ImageTooLarge,
    TierLacksQuota,
    QuotaSpent,
    ProviderFailed,
}

/// <summary>POST /extract outcome with the response body when extraction succeeded.</summary>
public sealed record ExtractOutcome(ExtractStatus Status, ExtractResponse? Response, int RetryAfterSeconds = 0);

/// <summary>
/// The LLM gateway service (docs/API.md "LLM gateway (Pro)",
/// docs/EXTRACTION.md "The P4.12 measurement"). It enforces the envelope before
/// any paid call (a cap enforced after the provider has run has already paid for
/// it), checks the per-period quota, calls the provider through the seam, and
/// meters a successful call against the llm_usage ledger.
///
/// Two quota conditions, two codes, never collapsed: a tier with no allowance
/// answers 402 ("the tier lacks quota at all"), a tier whose current-period
/// allowance is spent answers 429. The billing rule: <b>only a successful provider
/// call is metered</b> - a provider failure must not bill the user for a result
/// they never got, so the increment happens only after a successful answer.
///
/// The image bytes exist only for the duration of this call: decoded from the
/// base64 envelope, handed to the provider, then released. Nothing is written to
/// disk, blob storage, or a log line (hard rule 12).
/// </summary>
public sealed class LlmService
{
    /// <summary>The pipeline id in the response and the client's accuracy ratchet (docs/LOGGING.md capture.pipeline).</summary>
    public const string Pipeline = "cloud-fallback v1";

    private readonly LlmRepository _repository;
    private readonly ILlmProvider _provider;
    private readonly LlmGatewayOptions _options;
    private readonly ILogger<LlmService> _logger;
    private readonly TimeProvider _time;

    public LlmService(
        LlmRepository repository,
        ILlmProvider provider,
        IOptions<LlmGatewayOptions> options,
        ILogger<LlmService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _provider = provider;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    public async Task<ExtractOutcome> ExtractAsync(
        Guid accountId,
        string kind,
        string? imageBase64,
        ExtractHints hints,
        CancellationToken cancellationToken)
    {
        // Envelope first, before any paid call. The 4 MB cap is on the base64
        // body (docs/API.md); checking it here, before decode, means an oversize
        // image never reaches the provider.
        if (string.IsNullOrWhiteSpace(imageBase64))
        {
            return new ExtractOutcome(ExtractStatus.ImageMissing, null);
        }

        if (Encoding.UTF8.GetByteCount(imageBase64) > _options.MaxImageBytes)
        {
            return new ExtractOutcome(ExtractStatus.ImageTooLarge, null);
        }

        byte[] imageBytes;
        try
        {
            imageBytes = Convert.FromBase64String(imageBase64);
        }
        catch (FormatException)
        {
            return new ExtractOutcome(ExtractStatus.ImageInvalid, null);
        }

        // Quota: read the tier (what allowance, if any) and the period's usage.
        var stopwatch = Stopwatch.StartNew();
        var tier = await _repository.GetTierAsync(accountId, cancellationToken);
        var allowance = _options.AllowanceFor(tier);
        if (allowance is null)
        {
            TankbookLog.LlmExtract(_logger, LogLevel.Warning, kind, 0, 0, string.Empty, stopwatch.Elapsed, "no_quota");
            return new ExtractOutcome(ExtractStatus.TierLacksQuota, null);
        }

        var period = DateOnly.FromDateTime(_time.GetUtcNow().UtcDateTime);
        var usedBefore = (await _repository.GetUsageAsync(accountId, period, cancellationToken))?.Requests ?? 0;
        if (usedBefore >= allowance.Value)
        {
            TankbookLog.LlmExtract(_logger, LogLevel.Warning, kind, usedBefore, usedBefore, string.Empty, stopwatch.Elapsed, "quota_spent");
            return new ExtractOutcome(ExtractStatus.QuotaSpent, null, SecondsUntilNextPeriod(_time.GetUtcNow()));
        }

        // The paid call. A provider failure resolves to a 502 in the endpoint and
        // is NOT metered - the user is billed only for a result they received.
        LlmExtraction extraction;
        try
        {
            extraction = await _provider.ExtractAsync(kind, imageBytes, hints, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            TankbookLog.LlmExtract(_logger, LogLevel.Error, kind, usedBefore, usedBefore, string.Empty, stopwatch.Elapsed, "provider_failed");
            return new ExtractOutcome(ExtractStatus.ProviderFailed, null);
        }

        // Meter the successful call, then answer.
        var usedAfter = await _repository.IncrementUsageAsync(accountId, period, extraction.TotalTokens, cancellationToken);

        TankbookLog.LlmExtract(
            _logger,
            LogLevel.Information,
            kind,
            usedBefore,
            usedAfter.Requests,
            extraction.Model,
            stopwatch.Elapsed,
            "ok");

        var fields = extraction.Fields.ToDictionary(
            pair => pair.Key,
            pair => new ExtractFieldResponse(pair.Value.Value, pair.Value.Confidence),
            StringComparer.Ordinal);
        return new ExtractOutcome(ExtractStatus.Ok, new ExtractResponse(fields, Pipeline));
    }

    /// <summary>Whole seconds until the next quota period (midnight UTC, the boundary the daily period uses).</summary>
    private static int SecondsUntilNextPeriod(DateTimeOffset now)
    {
        var next = new DateTimeOffset(now.UtcDateTime.Date.AddDays(1), TimeSpan.Zero);
        return (int)Math.Ceiling((next - now).TotalSeconds);
    }
}
