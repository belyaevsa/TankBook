using System.Text.Json;
using Dapper;
using Tankbook.Admin.Access;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Content;

/// <summary>
/// An account's synced attachments (hard rule 9's admin-viewer amendment): the attachment
/// records' payloads (<c>records</c>, entity type <c>attachment</c>) and their files from
/// the bucket through <c>blobs.storage_ref</c>. By account id only - an attachment of another
/// account cannot be reached without that account's id.
/// </summary>
public static class AttachmentEndpoints
{
    public sealed record AttachmentSummary(Guid Id, string Kind, DateTimeOffset? CreatedAt, string? Sha256,
        long? SizeBytes, string? ThumbnailBase64, bool HasOcrText);

    public sealed record Attachment(Guid Id, string Kind, DateTimeOffset? CreatedAt, string? Sha256, long? SizeBytes,
        bool FileStored, string? ExtractedTimestamp, string? OcrText, JsonElement? ExtractionMeta);

    private sealed record Row(Guid Id, string Payload, long? SizeBytes, string? StorageRef);

    public static void Map(RouteGroupBuilder api)
    {
        api.MapGet("/accounts/{id}/attachments", List).AccessLogged("attachments", "id");
        api.MapGet("/accounts/{id}/attachments/{attachmentId}", Get).AccessLogged("attachment", "attachmentId");
        api.MapGet("/accounts/{id}/attachments/{attachmentId}/file", GetFile).AccessLogged("attachment-file", "attachmentId");
    }

    private static async Task<IResult> List(string id, Db db)
    {
        if (!Guid.TryParse(id, out var accountId))
        {
            return Results.NotFound();
        }
        await using var c = db.ApiRead();
        var rows = await c.QueryAsync<Row>(Select("r.account_id = @accountId") + " ORDER BY r.client_updated_at DESC", new { accountId });
        return Results.Ok(rows.Select(r =>
        {
            using var payload = JsonDocument.Parse(r.Payload);
            var p = payload.RootElement;
            return new AttachmentSummary(r.Id, Str(p, "kind") ?? "photo", Date(p, "createdAt"), FileSha(p), r.SizeBytes,
                Str(p, "thumbnailBase64"), !string.IsNullOrEmpty(Str(p, "ocrText")));
        }).ToList());
    }

    private static async Task<IResult> Get(string id, string attachmentId, Db db)
    {
        var row = await FindAsync(db, id, attachmentId);
        if (row is null)
        {
            return Results.NotFound();
        }
        using var payload = JsonDocument.Parse(row.Payload);
        var p = payload.RootElement;
        JsonElement? meta = p.TryGetProperty("extractionMeta", out var m) && m.ValueKind != JsonValueKind.Null ? m.Clone() : null;
        return Results.Ok(new Attachment(row.Id, Str(p, "kind") ?? "photo", Date(p, "createdAt"), FileSha(p), row.SizeBytes,
            row.StorageRef is not null, Str(p, "extractedTimestamp"), Str(p, "ocrText"), meta));
    }

    private static async Task<IResult> GetFile(string id, string attachmentId, Db db, IBlobReader blobs, CancellationToken ct)
    {
        var row = await FindAsync(db, id, attachmentId);
        if (row?.StorageRef is null)
        {
            return Results.NotFound();
        }
        var bytes = await blobs.ReadAsync(row.StorageRef, ct);
        if (bytes is null)
        {
            return Results.NotFound();
        }
        using var payload = JsonDocument.Parse(row.Payload);
        var pdf = Str(payload.RootElement, "kind") == "pdf";
        return Results.File(bytes, pdf ? "application/pdf" : "image/jpeg");
    }

    private static async Task<Row?> FindAsync(Db db, string id, string attachmentId)
    {
        if (!Guid.TryParse(id, out var accountId) || !Guid.TryParse(attachmentId, out var recordId))
        {
            return null;
        }
        await using var c = db.ApiRead();
        return await c.QuerySingleOrDefaultAsync<Row>(Select("r.account_id = @accountId AND r.id = @recordId"),
            new { accountId, recordId });
    }

    // The blob is the one the attachment's file names, in the same account.
    private static string Select(string where) =>
        "SELECT r.id, r.payload::text AS Payload, b.size_bytes AS SizeBytes, b.storage_ref AS StorageRef " +
        "FROM records r LEFT JOIN blobs b ON b.account_id = r.account_id AND b.sha256 = r.payload->'file'->>'sha256' " +
        $"WHERE r.entity_type = 'attachment' AND NOT r.deleted AND {where}";

    private static string? Str(JsonElement p, string name) =>
        p.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static string? FileSha(JsonElement p) =>
        p.TryGetProperty("file", out var f) && f.ValueKind == JsonValueKind.Object ? Str(f, "sha256") : null;

    private static DateTimeOffset? Date(JsonElement p, string name) =>
        DateTimeOffset.TryParse(Str(p, name), out var d) ? d : null;
}
