namespace Tankbook.Api.Logging;

/// <summary>
/// Typed, named events instead of ad-hoc message strings (docs/LOGGING.md §3).
/// Each method logs one line whose event field is the stable name and whose
/// fields are exactly the Safe set the spec tables list. Values never enter
/// here: call sites pass ids, counts and outcomes. Wire the ones with live call
/// sites today; the rest are the signatures the P4 sync/auth/blob/LLM code will
/// call.
/// </summary>
public static class TankbookLog
{
    /// <summary>The per-request line (docs/LOGGING.md §3 "Always, per request").
    /// <paramref name="correlation"/> carries the scope-enrichment fields
    /// (clientVersion, accountHash, deviceId, schemaVersion) that the outer
    /// trace middleware reads from context.Items after the enrichment scope is
    /// disposed, so this one line carries the same correlation as the rest.</summary>
    public static void HttpRequest(
        ILogger logger,
        LogLevel level,
        string method,
        string routeTemplate,
        int status,
        double durationMs,
        long requestBytes,
        long responseBytes,
        IReadOnlyDictionary<string, object?>? correlation = null)
    {
        var fields = new List<(string Key, object? Value)>
        {
            ("Method", method),
            ("Path", routeTemplate),
            ("Status", status),
            ("DurationMs", durationMs),
            ("RequestBytes", requestBytes),
            ("ResponseBytes", responseBytes),
        };
        if (correlation is not null)
        {
            foreach (var (key, value) in correlation)
            {
                fields.Add((key, value));
            }
        }

        // A readable summary rather than the bare event name: "GET /v1/sync/pull
        // -> 200 in 693ms" says at a glance what a wall of key=value pairs does
        // not. The structured fields are unchanged underneath, so a parser sees
        // exactly what it saw before.
        Emit(logger, level, "http.request",
             $"{method} {routeTemplate} -> {status} in {durationMs:F0}ms",
             fields.ToArray());
    }

    public static void AuthSession(
        ILogger logger,
        string provider,
        string outcome,
        string? failureReason = null,
        string? accountHash = null)
        => Emit(logger, LogLevel.Information, "auth.session",
            ("Provider", provider),
            ("Outcome", outcome),
            ("FailureReason", failureReason),
            ("AccountHash", accountHash));

    /// <summary>
    /// Refresh rotation; replay of a rotated token is a security event.
    ///
    /// <c>chainId</c> identifies the token FAMILY, not the individual rotation,
    /// and is therefore **stable across every refresh of the same chain** - that
    /// stability is what makes reuse detection possible, because a replayed
    /// token has to resolve to the chain it came from. The field was called
    /// <c>RotationId</c> until 2026-09-03, which read in production as "the
    /// rotation id is not rotating" and cost a round of investigation: three
    /// refreshes hours apart logged the same value, which looks exactly like a
    /// broken security control and is in fact the correct one working.
    /// </summary>
    public static void AuthRefresh(
        ILogger logger,
        string outcome,
        string? chainId = null,
        bool reuseDetected = false,
        string? deviceId = null)
        => Emit(logger, reuseDetected ? LogLevel.Warning : LogLevel.Information, "auth.refresh",
            ("Outcome", outcome),
            ("ChainId", chainId),
            ("ReuseDetected", reuseDetected),
            ("DeviceId", deviceId));

    public static void SyncPush(
        ILogger logger,
        int batchSize,
        int accepted,
        int conflicts,
        int rejected,
        (long From, long To)? assignedScnRange,
        TimeSpan duration,
        IEnumerable<object>? items = null)
        => Emit(logger, LogLevel.Information, "sync.push",
            ("BatchSize", batchSize),
            ("Accepted", accepted),
            ("Conflicts", conflicts),
            ("Rejected", rejected),
            ("AssignedScnRange", assignedScnRange is null ? null : new[] { assignedScnRange.Value.From, assignedScnRange.Value.To }),
            ("DurationMs", duration.TotalMilliseconds),
            ("Items", items));

    public static void SyncPull(
        ILogger logger,
        long sinceScn,
        int returned,
        long nextSince,
        bool more,
        TimeSpan duration)
        => Emit(logger, LogLevel.Information, "sync.pull",
            ("SinceScn", sinceScn),
            ("Returned", returned),
            ("NextSince", nextSince),
            ("More", more),
            ("DurationMs", duration.TotalMilliseconds));

    /// <summary>The silent sync nudge (docs/NOTIFICATIONS.md): counts and outcome only - device ids and counts are Safe, the push token is a Never credential and stays out (hard rule 12).</summary>
    public static void SyncNudge(
        ILogger logger,
        Guid accountId,
        int candidates,
        int delivered,
        int invalidToken,
        int transient,
        int throttled,
        bool config,
        TimeSpan duration)
        => Emit(logger, LogLevel.Information, "sync.nudge",
            ("AccountId", accountId),
            ("Candidates", candidates),
            ("Delivered", delivered),
            ("InvalidToken", invalidToken),
            ("Transient", transient),
            ("Throttled", throttled),
            ("Config", config),
            ("DurationMs", duration.TotalMilliseconds));

    public static void BlobBegin(
        ILogger logger,
        string sha256,
        long sizeBytes,
        string contentType,
        string dedupe,
        int? quotaUsedPct)
        => Emit(logger, LogLevel.Information, "blob.begin",
            ("Sha256", sha256),
            ("SizeBytes", sizeBytes),
            ("ContentType", contentType),
            ("Dedupe", dedupe),
            ("QuotaUsedPct", quotaUsedPct));

    public static void BlobCommit(
        ILogger logger,
        string sha256,
        long sizeBytes,
        string contentType,
        int? quotaUsedPct)
        => Emit(logger, LogLevel.Information, "blob.commit",
            ("Sha256", sha256),
            ("SizeBytes", sizeBytes),
            ("ContentType", contentType),
            ("QuotaUsedPct", quotaUsedPct));

    public static void BlobGet(ILogger logger, string sha256, int presignTtlSec)
        => Emit(logger, LogLevel.Information, "blob.get",
            ("Sha256", sha256),
            ("PresignTtlSec", presignTtlSec));

    /// <summary>Orphan sweep removed some blobs (docs/LOGGING.md §3 hygiene). Counts and account id only.</summary>
    public static void BlobSweep(ILogger logger, Guid accountId, int deleted)
        => Emit(logger, LogLevel.Information, "blob.sweep",
            ("AccountId", accountId),
            ("Deleted", deleted));

    /// <summary>Account blob prefix was purged (docs/LOGGING.md §3 hygiene). Counts and account id only.</summary>
    public static void BlobPurge(ILogger logger, Guid accountId, int deleted)
        => Emit(logger, LogLevel.Information, "blob.purge",
            ("AccountId", accountId),
            ("Deleted", deleted));

    public static void LlmExtract(
        ILogger logger,
        LogLevel level,
        string kind,
        long quotaBefore,
        long quotaAfter,
        string model,
        TimeSpan duration,
        string outcome)
        => Emit(logger, level, "llm.extract",
            ("Kind", kind),
            ("QuotaBefore", quotaBefore),
            ("QuotaAfter", quotaAfter),
            ("Model", model),
            ("DurationMs", duration.TotalMilliseconds),
            ("Outcome", outcome));

    /// <summary>
    /// Model resolution fell back to a compiled default (migration 014,
    /// docs/API.md "LLM gateway"). Warning, because a missing or unknown setting
    /// must be visible without breaking extraction. Shape only - kind and model
    /// ids are codes, never content (hard rule 12).
    /// </summary>
    public static void LlmModelFallback(
        ILogger logger,
        string kind,
        string requestedModelId,
        string resolvedModelId,
        string reason)
        => Emit(logger, LogLevel.Warning, "llm.model_fallback",
            ("Kind", kind),
            ("RequestedModelId", requestedModelId),
            ("ResolvedModelId", resolvedModelId),
            ("Reason", reason));

    /// <summary>The call-ledger content purge dropped some bodies (docs/SECURITY.md). Count only (hard rule 12).</summary>
    public static void LlmCallPurge(ILogger logger, int purged)
        => Emit(logger, LogLevel.Information, "llm.call_purge",
            ("Purged", purged));

    /// <summary>
    /// The prompt rendition could not be written to blob storage (RV.53). The
    /// ledger row still records the call - WITHOUT the rendition - and the
    /// request still answers, so this is handled degradation (Warning). Shape
    /// only: the account id and an outcome code, never the image (hard rule 12).
    /// </summary>
    public static void LlmCallRenditionFailed(ILogger logger, Guid accountId, string outcome)
        => Emit(logger, LogLevel.Warning, "llm.rendition_failed",
            ("AccountId", accountId),
            ("Outcome", outcome));

    /// <summary>
    /// The ledger row insert failed and the row was queued for a bounded retry
    /// (RV.53, llm_ledger_pending). Handled degradation - the audit will land
    /// if the retry succeeds. Shape only (hard rule 12).
    /// </summary>
    public static void LlmCallQueued(ILogger logger, Guid accountId, string outcome)
        => Emit(logger, LogLevel.Warning, "llm.call_queued",
            ("AccountId", accountId),
            ("Outcome", outcome));

    /// <summary>
    /// A paid call's audit record could not be written anywhere - the row insert
    /// failed AND the queue write failed, so the ledger row is lost. Data
    /// integrity is at risk (the spend of a real call has no record), so this is
    /// Error. Shape only (hard rule 12).
    /// </summary>
    public static void LlmCallUnrecorded(ILogger logger, Guid accountId, string outcome)
        => Emit(logger, LogLevel.Error, "llm.call_unrecorded",
            ("AccountId", accountId),
            ("Outcome", outcome));

    /// <summary>
    /// A queued ledger row exhausted its retry bound and was dropped (RV.53,
    /// the defined give-up outcome). The row is gone; this Warning is what makes
    /// the loss visible rather than silent. Shape only (hard rule 12).
    /// </summary>
    public static void LlmCallRetryDropped(ILogger logger, Guid accountId, string outcome, int attempts)
        => Emit(logger, LogLevel.Warning, "llm.call_retry_dropped",
            ("AccountId", accountId),
            ("Outcome", outcome),
            ("Attempts", attempts));

    /// <summary>The retry pass wrote queued ledger rows into llm_calls. Count only (hard rule 12).</summary>
    public static void LlmCallRetryLanded(ILogger logger, int landed)
        => Emit(logger, LogLevel.Information, "llm.call_retry_landed",
            ("Landed", landed));

    /// <summary>The ledger-write queue's retention pass dropped some pending rows that never landed (docs/SECURITY.md). Count only (hard rule 12).</summary>
    public static void LlmPendingPurge(ILogger logger, int purged)
        => Emit(logger, LogLevel.Information, "llm.pending_purge",
            ("Purged", purged));

    /// <summary>A gateway result could not be delivered and was queued for the device (docs/SECURITY.md "The delivery outbox"). Ids and a byte count only - never a payload (hard rule 12).</summary>
    public static void OutboxEnqueue(ILogger logger, Guid accountId, Guid deviceId, int payloadBytes)
        => Emit(logger, LogLevel.Information, "outbox.enqueue",
            ("AccountId", accountId),
            ("DeviceId", deviceId),
            ("PayloadBytes", payloadBytes));

    /// <summary>A device drained its pending outbox rows. Counts only - never a payload (hard rule 12).</summary>
    public static void OutboxDrain(ILogger logger, Guid accountId, Guid deviceId, int returned)
        => Emit(logger, LogLevel.Information, "outbox.drain",
            ("AccountId", accountId),
            ("DeviceId", deviceId),
            ("Returned", returned));

    /// <summary>The outbox retention/account purge dropped some rows. Count only (hard rule 12).</summary>
    public static void OutboxPurge(ILogger logger, int purged)
        => Emit(logger, LogLevel.Information, "outbox.purge",
            ("Purged", purged));

    public static void MigrationDdl(ILogger logger, string version, string direction, TimeSpan duration)
        => Emit(logger, LogLevel.Information, "migration.ddl",
            ("Version", version),
            ("Direction", direction),
            ("DurationMs", duration.TotalMilliseconds));

    public static void MigrationPayload(
        ILogger logger,
        string entityType,
        int fromVersion,
        int toVersion,
        long rowsScanned,
        long rowsRewritten,
        int batches,
        TimeSpan duration)
        => Emit(logger, LogLevel.Information, "migration.payload",
            ("EntityType", entityType),
            ("FromVersion", fromVersion),
            ("ToVersion", toVersion),
            ("RowsScanned", rowsScanned),
            ("RowsRewritten", rowsRewritten),
            ("Batches", batches),
            ("DurationMs", duration.TotalMilliseconds));

    /// <summary>A config document was published (docs/CONFIG.md). Version and
    /// outcome only - never the document (values are Never class, docs/LOGGING.md).</summary>
    public static void ConfigPublish(ILogger logger, int version, string outcome, string? reason = null)
        => Emit(logger, LogLevel.Information, "config.publish",
            ("Version", version),
            ("Outcome", outcome),
            ("Reason", reason));

    /// <summary>The migration-seeded baseline document was signed at startup.</summary>
    public static void ConfigSeed(ILogger logger, int version, string outcome)
        => Emit(logger, LogLevel.Information, "config.seed",
            ("Version", version),
            ("Outcome", outcome));

    /// <summary>A catalog pack was published or refused (docs/API.md "Vehicle
    /// catalog"). Version, an entry count and an outcome are Safe; the pack's
    /// contents are never logged - the curation feedback loop records model
    /// strings as counts only, and that discipline holds here too (hard rule 12).</summary>
    public static void CatalogPublish(ILogger logger, int version, int entries, string outcome, string? reason = null)
        => Emit(logger, LogLevel.Information, "catalog.publish",
            ("Version", version),
            ("Entries", entries),
            ("Outcome", outcome),
            ("Reason", reason));

    /// <summary>No document is valid (all expired/unpublished); the latest was served anyway.</summary>
    public static void ConfigExpiredFallback(ILogger logger, int version)
        => Emit(logger, LogLevel.Warning, "config.expired.fallback",
            ("Version", version));

    /// <summary>The daily rates pass (docs/SCHEMA.md): a date, currency-agnostic counts. A date and a count are Safe; a user's amount never enters here (hard rule 12).</summary>
    public static void RatesFetch(
        ILogger logger,
        string date,
        int published,
        int carriedForward,
        int sourcesFailed)
        => Emit(logger, LogLevel.Information, "rates.fetch",
            ("Date", date),
            ("Published", published),
            ("CarriedForward", carriedForward),
            ("SourcesFailed", sourcesFailed));

    /// <summary>The demand-driven rates backfill (docs/SCHEMA.md): counts only - how many queued dates were attempted, and how they resolved. SourcesFailed stays visible even while gaps are carried, so a broken feed cannot hide again (RV.15). Answered counts the gaps recorded unfillable (RV.50) - it is what lets a healthy drain read differently from a wedged one.</summary>
    public static void RatesBackfill(
        ILogger logger,
        int processed,
        int published,
        int carriedForward,
        int sourcesFailed,
        int answered)
        => Emit(logger, LogLevel.Information, "rates.backfill",
            ("Processed", processed),
            ("Published", published),
            ("CarriedForward", carriedForward),
            ("SourcesFailed", sourcesFailed),
            ("Answered", answered));

    public static void AccountDelete(
        ILogger logger,
        string accountHash,
        long recordsPurged,
        long blobsPurged,
        DateTimeOffset? graceEndsAt)
        => Emit(logger, LogLevel.Information, "account.delete",
            ("AccountHash", accountHash),
            ("RecordsPurged", recordsPurged),
            ("BlobsPurged", blobsPurged),
            ("GraceEndsAt", graceEndsAt));

    /// <summary>A file was parsed (docs/API.md "Import parsing"). Shape only -
    /// format, file kind and counts - never a station, note, amount or coordinate
    /// (hard rule 12).</summary>
    public static void ImportParse(
        ILogger logger,
        string format,
        string fileKind,
        int rowsRead,
        int candidates,
        int unparsed,
        int ambiguities,
        TimeSpan duration,
        string outcome)
        => Emit(logger, LogLevel.Information, "import.parse",
            ("Format", format),
            ("FileKind", fileKind),
            ("RowsRead", rowsRead),
            ("Candidates", candidates),
            ("Unparsed", unparsed),
            ("Ambiguities", ambiguities),
            ("DurationMs", duration.TotalMilliseconds),
            ("Outcome", outcome));

    /// <summary>A stored parse was dropped early (DELETE /import/{importId}). Shape only.</summary>
    public static void ImportDelete(ILogger logger, string format, string fileKind, string outcome)
        => Emit(logger, LogLevel.Information, "import.delete",
            ("Format", format),
            ("FileKind", fileKind),
            ("Outcome", outcome));

    /// <summary>The 30-day import purge dropped some stored parses. Count only (hard rule 12).</summary>
    public static void ImportPurge(ILogger logger, int purged)
        => Emit(logger, LogLevel.Information, "import.purge",
            ("Purged", purged));

    /// <summary>
    /// A feedback case was accepted (docs/API.md "Feedback", docs/LOGGING.md
    /// hard rule 12). Shape only: the category code, the text length (a count),
    /// the presence flags for the optional fields and the account. The feedback
    /// text, a replyTo address and a device-model string have no route into this
    /// event by construction - never the text, never a contact address, never a
    /// model string (docs/LOGGING.md -> Feedback).
    /// </summary>
    public static void FeedbackAccepted(
        ILogger logger,
        Guid id,
        string category,
        int textLength,
        bool hasReplyTo,
        bool hasDeviceModel,
        bool hasAccount)
        => Emit(logger, LogLevel.Information, "feedback.accepted",
            ("Id", id),
            ("Category", category),
            ("TextLength", textLength),
            ("HasReplyTo", hasReplyTo),
            ("HasDeviceModel", hasDeviceModel),
            ("HasAccount", hasAccount));

    /// <summary>Unhandled-exception ERROR line from the exception handler.</summary>
    public static void UnhandledException(ILogger logger, Exception exception, string? endpoint)
        => logger.Log(
            LogLevel.Error,
            new EventId(0, "error.unhandled"),
            new Dictionary<string, object?>
            {
                ["Event"] = "error.unhandled",
                ["ErrorCode"] = "internal_error",
                ["Endpoint"] = endpoint,
            },
            exception,
            static (state, _) =>
            {
                var map = (IReadOnlyDictionary<string, object?>)state;
                return $"error.unhandled endpoint={map.GetValueOrDefault("Endpoint")}";
            });

    private static void Emit(ILogger logger, LogLevel level, string eventName, params (string Key, object? Value)[] fields)
        => Emit(logger, level, eventName, null, fields);

    /// <summary>
    /// As above, with a human-readable summary. The summary is what a person
    /// reads; the fields are what a parser reads. Both are emitted, so making
    /// the line legible costs a machine consumer nothing.
    /// </summary>
    private static void Emit(ILogger logger, LogLevel level, string eventName, string? summary, params (string Key, object? Value)[] fields)
    {
        var state = new Dictionary<string, object?> { ["Event"] = eventName };
        if (summary is not null)
        {
            state["Summary"] = summary;
        }

        foreach (var (key, value) in fields)
        {
            state[key] = value;
        }

        logger.Log(
            level,
            new EventId(0, eventName),
            state,
            null,
            static (s, _) =>
            {
                var map = (IReadOnlyDictionary<string, object?>)s;
                return map.GetValueOrDefault("Summary") as string
                    ?? map.GetValueOrDefault("Event") as string
                    ?? "log";
            });
    }
}
