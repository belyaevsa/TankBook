using Dapper;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Content;

/// <summary>The owner reading his own audit trail, newest first, paged by id.</summary>
public static class AccessLogEndpoints
{
    public sealed record Entry(long Id, DateTimeOffset At, string Actor, string Kind, string? TargetId, string Route, int Status);

    public static void Map(RouteGroupBuilder api)
    {
        api.MapGet("/access-log", async (long? before, int? limit, Db db) =>
        {
            var take = Math.Clamp(limit ?? 50, 1, 200);
            await using var c = db.AdminWrite();
            var rows = await c.QueryAsync<(long Id, DateTime At, string Actor, string Kind, string? TargetId, string Route, int Status)>(
                "SELECT id, at, actor, kind, target_id, route, status FROM admin.access_log " +
                "WHERE (@before IS NULL OR id < @before) ORDER BY id DESC LIMIT @take",
                new { before, take });
            return Results.Ok(rows.Select(r => new Entry(r.Id, new DateTimeOffset(DateTime.SpecifyKind(r.At, DateTimeKind.Utc)),
                r.Actor, r.Kind, r.TargetId, r.Route, r.Status)));
        });
    }
}
