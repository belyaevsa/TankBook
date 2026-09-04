using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Logging;
using Tankbook.Api.Outbox;

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
    /// <summary>The answer was computed but could not be handed back - the client vanished - so it was queued in the delivery outbox (RV.44).</summary>
    DeliveredViaOutbox,
}

/// <summary>POST /extract outcome with the response body when extraction succeeded.</summary>
public sealed record ExtractOutcome(ExtractStatus Status, ExtractResponse? Response, int RetryAfterSeconds = 0);

/// <summary>
/// The LLM gateway service (docs/API.md "LLM gateway (Pro)",
/// docs/EXTRACTION.md "The P4.12 measurement"). It enforces the envelope before
/// any paid call (a cap enforced after the provider has run has already paid for
/// it), checks the per-period quota, resolves the model for the kind (migration
/// 014), calls the provider through the seam, meters a successful call against
/// the llm_usage ledger, and records every provider call in the llm_calls ledger
/// (migration 015) - the spend record that survives account deletion.
///
/// The audit write is OFF the critical path of the answer (RV.53). The ledger
/// row is written synchronously and never fails the request: if the row insert
/// itself cannot land, the row is queued (llm_ledger_pending, migration 021) for
/// a bounded retry instead of thrown. The prompt rendition in blob storage is
/// best-effort - a blob store outage costs the rendition (the row then records
/// the call WITHOUT one, and the device still holds the photo), never the answer
/// or the row. This was a regression RV.33 introduced (an audit write on the
/// path of a paid answer); before the ledger existed an S3 outage could not
/// touch /extract at all. docs/SECURITY.md "The ledger write queue".
///
/// Two quota conditions, two codes, never collapsed: a tier with no allowance
/// answers 402 ("the tier lacks quota at all"), a tier whose current-period
/// allowance is spent answers 429. The billing rule: <b>only a successful provider
/// call is metered</b> - a provider failure must not bill the user for a result
/// they never got, so the increment happens only after a successful answer.
///
/// The call ledger records a row for a successful call AND for a provider
/// failure - a ledger that only records successes cannot answer the question it
/// exists for. Rejections before the provider (missing/oversize/undecodable
/// image, no quota, spent quota) are not calls to the model: nothing was sent,
/// nothing was spent, so they write no row. The prompt rendition (the image,
/// the prompt for /extract) is stored in blob storage and referenced by sha256,
/// never in a column (docs/SECURITY.md "LLM call ledger").
///
/// Delivery (RV.44): the paid call runs to completion against a SERVER-side
/// token, not the request's abort token - the whole point of the outbox is that
/// an answer survives the client vanishing mid-request, which production shows
/// as nginx 499. When the answer is ready, the request's own token is consulted:
/// if the client is gone, the result is queued in the delivery outbox (opaque
/// bytes addressed to the device) instead of being handed back into a void. The
/// outbox never reads the payload's fields (hard rule 9).
/// </summary>
public sealed class LlmService
{
    /// <summary>The pipeline id in the response and the client's accuracy ratchet (docs/LOGGING.md capture.pipeline).</summary>
    public const string Pipeline = "cloud-fallback v1";

    private const string OutcomeOk = "ok";
    private const string OutcomeProviderFailed = "provider_failed";
    private const string OutcomeOutboxed = "outboxed";
    private const string CategorySuccess = "success";
    private const string CategoryError = "error";

    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    private readonly LlmRepository _repository;
    private readonly LlmModelResolver _modelResolver;
    private readonly LlmCallRepository _callRepository;
    private readonly LlmLedgerPendingRepository _ledgerPending;
    private readonly IBlobStorage _storage;
    private readonly ILlmProvider _provider;
    private readonly OutboxService _outbox;
    private readonly LlmGatewayOptions _options;
    private readonly ILogger<LlmService> _logger;
    private readonly TimeProvider _time;

    public LlmService(
        LlmRepository repository,
        LlmModelResolver modelResolver,
        LlmCallRepository callRepository,
        LlmLedgerPendingRepository ledgerPending,
        IBlobStorage storage,
        ILlmProvider provider,
        OutboxService outbox,
        IOptions<LlmGatewayOptions> options,
        ILogger<LlmService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _modelResolver = modelResolver;
        _callRepository = callRepository;
        _ledgerPending = ledgerPending;
        _storage = storage;
        _provider = provider;
        _outbox = outbox;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    public async Task<ExtractOutcome> ExtractAsync(
        Guid accountId,
        Guid deviceId,
        string kind,
        string? imageBase64,
        ExtractHints hints,
        string? captureId,
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

        var stopwatch = Stopwatch.StartNew();

        // Everything from the model resolution down runs against a server-side
        // token, never the request's abort token: once the quota gate passes the
        // call is going to be paid for, and the answer must exist to deliver -
        // inline when the client is still there, or in the outbox when it is
        // not (RV.44). The request token is consulted only at the end, for the
        // delivery decision.
        var serverToken = CancellationToken.None;

        // Resolve the model for this kind (migration 014). A missing or unknown
        // setting falls back to the compiled default and logs at Warning; it
        // never throws, so one bad row cannot take extraction down.
        var model = await _modelResolver.ResolveAsync(kind, serverToken);

        // Quota: read the tier (what allowance, if any) and the period's usage.
        var tier = await _repository.GetTierAsync(accountId, serverToken);
        var allowance = _options.AllowanceFor(tier);
        if (allowance is null)
        {
            TankbookLog.LlmExtract(_logger, LogLevel.Warning, kind, 0, 0, string.Empty, stopwatch.Elapsed, "no_quota");
            return new ExtractOutcome(ExtractStatus.TierLacksQuota, null);
        }

        var period = DateOnly.FromDateTime(_time.GetUtcNow().UtcDateTime);
        var usedBefore = (await _repository.GetUsageAsync(accountId, period, serverToken))?.Requests ?? 0;
        if (usedBefore >= allowance.Value)
        {
            TankbookLog.LlmExtract(_logger, LogLevel.Warning, kind, usedBefore, usedBefore, string.Empty, stopwatch.Elapsed, "quota_spent");
            return new ExtractOutcome(ExtractStatus.QuotaSpent, null, SecondsUntilNextPeriod(_time.GetUtcNow()));
        }

        // The paid call. A provider failure resolves to a 502 in the endpoint and
        // is NOT metered - the user is billed only for a result they received -
        // but it IS recorded in the ledger (a ledger of successes only cannot
        // answer what it exists for). RecordCallAsync cannot throw for an
        // unavailable blob store or ledger row insert (RV.53), so a storage
        // outage coinciding with the provider outage can no longer mask the
        // real failure - the operator sees provider_failed, not a storage
        // stack trace.
        LlmExtraction extraction;
        try
        {
            extraction = await _provider.ExtractAsync(kind, imageBytes, hints, model, serverToken);
        }
        catch
        {
            await RecordCallAsync(accountId, deviceId, kind, model, extraction: null, imageBytes, OutcomeProviderFailed, CategoryError, stopwatch.Elapsed, serverToken);
            TankbookLog.LlmExtract(_logger, LogLevel.Error, kind, usedBefore, usedBefore, string.Empty, stopwatch.Elapsed, "provider_failed");
            return new ExtractOutcome(ExtractStatus.ProviderFailed, null);
        }

        // Meter the successful call, then record it. Both run on the server
        // token, so a client that vanished mid-call still gets a metered,
        // recorded, deliverable answer (the ledger is the audit of a call that
        // really happened; the outbox is the delivery). Metering is a real
        // Postgres write and stays on the path; the record that follows is the
        // audit, written so it can no longer fail this request (RV.53).
        var usedAfter = await _repository.IncrementUsageAsync(accountId, period, extraction.TotalTokens, serverToken);
        await RecordCallAsync(accountId, deviceId, kind, model, extraction, imageBytes, OutcomeOk, CategorySuccess, stopwatch.Elapsed, serverToken);

        var fields = extraction.Fields.ToDictionary(
            pair => pair.Key,
            pair => new ExtractFieldResponse(pair.Value.Value, pair.Value.Confidence),
            StringComparer.Ordinal);
        var response = new ExtractResponse(fields, Pipeline);

        // Delivery decision (RV.44). The answer is ready; if the client is gone
        // (the request was aborted), hand it to the outbox instead of a void.
        if (cancellationToken.IsCancellationRequested)
        {
            var payload = BuildOutboxPayload(captureId, response);
            await _outbox.EnqueueAsync(accountId, deviceId, payload, serverToken);
            TankbookLog.LlmExtract(_logger, LogLevel.Information, kind, usedBefore, usedAfter.Requests, extraction.Model, stopwatch.Elapsed, OutcomeOutboxed);
            return new ExtractOutcome(ExtractStatus.DeliveredViaOutbox, null);
        }

        TankbookLog.LlmExtract(
            _logger,
            LogLevel.Information,
            kind,
            usedBefore,
            usedAfter.Requests,
            extraction.Model,
            stopwatch.Elapsed,
            "ok");

        return new ExtractOutcome(ExtractStatus.Ok, response);
    }

    /// <summary>
    /// The opaque outbox payload: the extract response plus the device's
    /// correlation token, serialized as JSON bytes. The server reads
    /// <paramref name="captureId"/> only to echo it (an opaque token, never a
    /// domain value) and never reads a field of the response - the bytes are
    /// stored and returned as-is (hard rule 9).
    /// </summary>
    private static byte[] BuildOutboxPayload(string? captureId, ExtractResponse response)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteString("captureId", captureId);
            writer.WritePropertyName("fields");
            JsonSerializer.Serialize(writer, response.Fields, WireJson);
            writer.WriteString("pipeline", response.Pipeline);
            writer.WriteEndObject();
        }

        return stream.ToArray();
    }

    /// <summary>
    /// Writes one llm_calls row for a provider call (success or failure): stores
    /// the prompt rendition in blob storage by content address, snapshots the
    /// unit prices onto the row, and computes the cost from the snapshot - never
    /// from the dictionary at read time, so a later price change cannot rewrite
    /// what an earlier call cost (hard rule 3's rate-snapshot logic).
    ///
    /// Neither half may fail the user's request (RV.53): this runs after the
    /// call was paid for and metered, so an AUDIT write failing here would hand
    /// the user nothing for money already spent. The rendition is best-effort -
    /// a blob store outage is caught, logged (llm.rendition_failed) and the row
    /// is written WITHOUT the rendition (prompt_sha256 null), the degradation
    /// docs/SECURITY.md names; it is never retried later, because the server
    /// retains no image bytes to retry with. The row insert is the audit the
    /// ledger exists for, so on failure the row is queued
    /// (llm_ledger_pending) for a bounded retry instead of thrown; only if even
    /// the queue cannot be written (the database itself is down) is the record
    /// lost, and that loss is an Error event (llm.call_unrecorded), never a
    /// thrown request.
    /// </summary>
    private async Task RecordCallAsync(
        Guid accountId,
        Guid deviceId,
        string kind,
        LlmModelChoice model,
        LlmExtraction? extraction,
        byte[] imageBytes,
        string outcome,
        string category,
        TimeSpan duration,
        CancellationToken cancellationToken)
    {
        var sha256 = Convert.ToHexString(SHA256.HashData(imageBytes)).ToLowerInvariant();
        var key = LlmCallKeys.PromptKey(accountId, sha256);

        string? storedSha = null;
        try
        {
            await _storage.PutObjectAsync(key, imageBytes, "image/jpeg", cancellationToken);
            storedSha = sha256;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            // Shape only - account id and an outcome code, never the image
            // (hard rule 12). The row below still records the call; only the
            // rendition is lost, and the device still holds the original.
            TankbookLog.LlmCallRenditionFailed(_logger, accountId, outcome);
        }

        long promptTokens = extraction?.PromptTokens ?? 0;
        long completionTokens = extraction?.CompletionTokens ?? 0;
        var cost = promptTokens * model.InputPricePerToken + completionTokens * model.OutputPricePerToken;

        var call = new LlmCallInsert(
            Id: Guid.NewGuid(),
            AccountId: accountId,
            DeviceId: deviceId,
            Kind: kind,
            ModelId: model.ModelId,
            Vendor: model.Vendor,
            Outcome: outcome,
            Category: category,
            PromptTokens: promptTokens,
            CompletionTokens: completionTokens,
            ThinkingEnabled: model.SupportsThinking,
            InputPricePerToken: model.InputPricePerToken,
            OutputPricePerToken: model.OutputPricePerToken,
            Cost: cost,
            Currency: model.Currency,
            PromptSha256: storedSha,
            PromptBody: null,
            ResponseBody: extraction?.ResponseBody,
            ThinkingBody: extraction?.ThinkingBody,
            DurationMs: (long)duration.TotalMilliseconds);

        try
        {
            await _callRepository.InsertAsync(call, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            // The row insert failed. Queue the row for a bounded retry rather
            // than drop it - the audit of a paid call is exactly what RV.33
            // exists to keep. If even the queue cannot be written the record is
            // lost, and the Error names that loss (shape only).
            try
            {
                await _ledgerPending.EnqueueAsync(call, cancellationToken);
                TankbookLog.LlmCallQueued(_logger, accountId, outcome);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                TankbookLog.LlmCallUnrecorded(_logger, accountId, outcome);
            }
        }
    }

    /// <summary>Whole seconds until the next quota period (midnight UTC, the boundary the daily period uses).</summary>
    private static int SecondsUntilNextPeriod(DateTimeOffset now)
    {
        var next = new DateTimeOffset(now.UtcDateTime.Date.AddDays(1), TimeSpan.Zero);
        return (int)Math.Ceiling((next - now).TotalSeconds);
    }
}
