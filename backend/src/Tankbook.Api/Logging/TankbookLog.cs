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

        Emit(logger, level, "http.request", fields.ToArray());
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

    /// <summary>Refresh rotation; replay of a rotated token is a security event.</summary>
    public static void AuthRefresh(
        ILogger logger,
        string outcome,
        string? rotationId = null,
        bool reuseDetected = false,
        string? deviceId = null)
        => Emit(logger, reuseDetected ? LogLevel.Warning : LogLevel.Information, "auth.refresh",
            ("Outcome", outcome),
            ("RotationId", rotationId),
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
    {
        var state = new Dictionary<string, object?> { ["Event"] = eventName };
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
                return map.GetValueOrDefault("Event") as string ?? "log";
            });
    }
}
