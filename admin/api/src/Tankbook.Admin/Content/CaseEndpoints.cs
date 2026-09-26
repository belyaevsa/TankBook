using System.Text.Json;
using System.Text.RegularExpressions;
using Dapper;
using Tankbook.Admin.Access;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Content;

/// <summary>
/// Debug cases (<c>debug_cases</c>, API migration 026) read by id - the only way in (hard
/// rule 9's debug-cases amendment: no list, no search). One case's envelope, then each
/// part's bytes from the bucket. Reachable with a passkey session or the owner's read key;
/// every look writes its access row. A purged case is simply not found.
/// </summary>
public static partial class CaseEndpoints
{
    public const string RateLimitPolicy = "case-read";

    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    public sealed record Part(string Name, string ContentType, long Bytes);

    public sealed record Case(string Id, DateTimeOffset CreatedAt, string? App, Guid? AccountId, Guid DeviceId,
        long TotalBytes, IReadOnlyList<Part> Parts);

    private sealed record StoredPart(string Name, string ContentType, long Bytes, string Key);

    private sealed class Row
    {
        public string Id { get; init; } = "";
        public Guid? AccountId { get; init; }
        public Guid DeviceId { get; init; }
        public string? App { get; init; }
        public string Parts { get; init; } = "[]";
        public long TotalBytes { get; init; }
        public DateTime CreatedAt { get; init; }

        public IReadOnlyList<StoredPart> StoredParts =>
            JsonSerializer.Deserialize<List<StoredPart>>(Parts, WireJson) ?? [];
    }

    public static void Map(RouteGroupBuilder cases)
    {
        cases.MapGet("/{id}", GetCase).AccessLogged("case", "id");
        cases.MapGet("/{id}/parts/{name}", GetPart).AccessLogged("case-part", "id");
    }

    private static async Task<IResult> GetCase(string id, Db db)
    {
        var row = await FindAsync(db, id);
        if (row is null)
        {
            return Results.NotFound();
        }
        return Results.Ok(new Case(row.Id, new DateTimeOffset(DateTime.SpecifyKind(row.CreatedAt, DateTimeKind.Utc)),
            row.App, row.AccountId, row.DeviceId, row.TotalBytes,
            row.StoredParts.Select(p => new Part(p.Name, p.ContentType, p.Bytes)).ToList()));
    }

    private static async Task<IResult> GetPart(string id, string name, Db db, IBlobReader blobs, CancellationToken ct)
    {
        var part = (await FindAsync(db, id))?.StoredParts.FirstOrDefault(p => p.Name == name);
        if (part is null)
        {
            return Results.NotFound();
        }
        var bytes = await blobs.ReadAsync(part.Key, ct);
        return bytes is null ? Results.NotFound() : Results.File(bytes, part.ContentType, part.Name);
    }

    private static async Task<Row?> FindAsync(Db db, string id)
    {
        var normalized = Normalize(id);
        if (normalized is null)
        {
            return null;
        }
        await using var c = db.ApiRead();
        return await c.QuerySingleOrDefaultAsync<Row>(
            "SELECT id, account_id AS AccountId, device_id AS DeviceId, app, parts::text AS Parts, " +
            "total_bytes AS TotalBytes, created_at AS CreatedAt FROM debug_cases WHERE id = @normalized",
            new { normalized });
    }

    /// <summary>A pasted id as the API stores it: upper case, the dash after five characters.</summary>
    public static string? Normalize(string text)
    {
        var compact = text.Trim().Replace("-", "", StringComparison.Ordinal).ToUpperInvariant();
        return Compact().IsMatch(compact) ? $"{compact[..5]}-{compact[5..]}" : null;
    }

    [GeneratedRegex("^[0-9A-HJKMNP-TV-Z]{10}$")]
    private static partial Regex Compact();
}
