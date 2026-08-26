using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tankbook.Api.Sync;

/// <summary>POST /sync/push request body (docs/API.md Sync).</summary>
public sealed record PushRequest(IReadOnlyList<PushChange>? Changes);

/// <summary>
/// One change in a push batch. <c>BaseScn</c> is 0 for a new record, otherwise
/// the last SCN the client saw for that id (optimistic-concurrency base).
/// </summary>
public sealed class PushChange
{
    public Guid Id { get; init; }

    public string? EntityType { get; init; }

    public int SchemaVersion { get; init; }

    public long BaseScn { get; init; }

    public JsonElement Payload { get; init; }

    public DateTimeOffset ClientUpdatedAt { get; init; }

    public bool Deleted { get; init; }
}

/// <summary>
/// A record as it travels on the wire (pull records and push conflicts share the
/// shape docs/API.md specifies): the payload is embedded as a JSON object, never
/// as a string.
/// </summary>
public sealed record SyncRecord(
    Guid Id,
    string EntityType,
    int SchemaVersion,
    long Scn,
    JsonElement Payload,
    DateTimeOffset ClientUpdatedAt,
    bool Deleted);

/// <summary>The schema policy clients read from GET /sync/pull (docs/API.md).</summary>
public sealed record SchemaPolicy(int MinSupported, int Current);

/// <summary>GET /sync/pull response body (docs/API.md).</summary>
public sealed record PullResponse(
    IReadOnlyList<SyncRecord> Records,
    long NextSince,
    bool More,
    SchemaPolicy SchemaPolicy);

/// <summary>POST /sync/push response body: one result per change.</summary>
public sealed record PushResponse(IReadOnlyList<object> Results);

/// <summary>A change the server accepted; <c>Clamped</c> marks a clientUpdatedAt pushed into the past.</summary>
public sealed record AcceptedPushResult(
    Guid Id,
    string Status,
    long NewScn,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] bool? Clamped = null);

/// <summary>A stale baseScn; carries the server's current record for the client's merge (S1/S6).</summary>
public sealed record ConflictPushResult(Guid Id, string Status, SyncRecord Current);

/// <summary>A structurally invalid change; <c>Error</c> and <c>Pointer</c> name the reason (never the value).</summary>
public sealed record RejectedPushResult(
    Guid Id,
    string Status,
    string Error,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Pointer = null);

/// <summary>The outcome of a push: an HTTP 200 body, or a whole-batch refusal.</summary>
public sealed record PushOutcome(PushStatus Status, IReadOnlyList<object>? Results);

public enum PushStatus
{
    Ok,
    DeviceRevoked,
    UpgradeRequired,
}

/// <summary>The outcome of a pull: an HTTP 200 body, or 410.</summary>
public sealed record PullOutcome(PullStatus Status, PullResponse? Response);

public enum PullStatus
{
    Ok,
    DeviceRevoked,
}
