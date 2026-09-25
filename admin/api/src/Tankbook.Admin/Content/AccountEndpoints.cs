using Dapper;
using Tankbook.Admin.Access;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Content;

/// <summary>
/// An account by its exact id, and the lookup box. There is deliberately no list of
/// accounts and no search: the viewer answers a known id and nothing else.
/// </summary>
public static class AccountEndpoints
{
    public sealed record Device(Guid Id, string Name, string Platform, DateTimeOffset LastSeenAt);
    public sealed record Account(Guid Id, DateTimeOffset CreatedAt, DateTimeOffset? DeletedAt, string Provider,
        string Email, IReadOnlyList<Device> Devices);
    public sealed record LookupHit(string Kind, string Id);

    public static void Map(RouteGroupBuilder api)
    {
        api.MapGet("/accounts/{id}", GetAccount).AccessLogged("account", "id");
        api.MapGet("/lookup", Lookup).AccessLogged("lookup", "q");
    }

    private static async Task<IResult> GetAccount(string id, Db db)
    {
        if (!Guid.TryParse(id, out var accountId))
        {
            return Results.NotFound();
        }
        await using var c = db.ApiRead();
        var row = await c.QuerySingleOrDefaultAsync<(Guid Id, DateTime CreatedAt, DateTime? DeletedAt, string? AppleSub, string Email)>(
            "SELECT id, created_at, deleted_at, apple_sub, email FROM accounts WHERE id = @accountId", new { accountId });
        if (row.Id == Guid.Empty)
        {
            return Results.NotFound();
        }
        var devices = (await c.QueryAsync<(Guid Id, string Name, string Platform, DateTime LastSeenAt)>(
                "SELECT id, name, platform, last_seen_at FROM devices WHERE account_id = @accountId ORDER BY last_seen_at DESC",
                new { accountId }))
            .Select(d => new Device(d.Id, d.Name, d.Platform, new DateTimeOffset(DateTime.SpecifyKind(d.LastSeenAt, DateTimeKind.Utc))))
            .ToList();
        return Results.Ok(new Account(row.Id,
            new DateTimeOffset(DateTime.SpecifyKind(row.CreatedAt, DateTimeKind.Utc)),
            row.DeletedAt is { } deleted ? new DateTimeOffset(DateTime.SpecifyKind(deleted, DateTimeKind.Utc)) : null,
            row.AppleSub is null ? "google" : "apple", row.Email, devices));
    }

    private static async Task<IResult> Lookup(string? q, Db db)
    {
        var query = q?.Trim() ?? "";
        // An exact id only - a prefix of an id is not a lookup, it is a search.
        if (Guid.TryParse(query, out var id))
        {
            await using var c = db.ApiRead();
            if (await c.ExecuteScalarAsync<bool>("SELECT EXISTS (SELECT 1 FROM accounts WHERE id = @id)", new { id }))
            {
                return Results.Ok(new LookupHit("account", id.ToString()));
            }
        }
        return Results.NotFound();
    }
}
