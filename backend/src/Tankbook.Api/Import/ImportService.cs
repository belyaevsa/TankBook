using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Import;

/// <summary>Thrown when the uploaded file exceeds the import size cap (docs/API.md: 413).</summary>
public sealed class ImportFileTooLargeException : Exception
{
    public ImportFileTooLargeException(long maxBytes)
        : base($"The import file exceeds the {maxBytes} byte limit.")
    {
        MaxBytes = maxBytes;
    }

    public long MaxBytes { get; }
}

/// <summary>
/// The import parsing surface (docs/API.md "Import parsing", hard rule 9's named
/// exception). It parses a third-party export into candidate proposals, stores
/// the file and its result in blob storage so a review can be resumed, and
/// commits nothing to any account (hard rules 1 and 9). Works signed out: the
/// file is stored under the device identity when there is no account
/// (docs/SECURITY.md "Import files at rest").
/// </summary>
public sealed class ImportService
{
    private readonly ImportRepository _repository;
    private readonly IBlobStorage _storage;
    private readonly ImportOptions _options;
    private readonly ILogger<ImportService> _logger;

    public ImportService(
        ImportRepository repository,
        IBlobStorage storage,
        IOptions<ImportOptions> options,
        ILogger<ImportService> logger)
    {
        _repository = repository;
        _storage = storage;
        _options = options.Value;
        _logger = logger;
    }

    /// <summary>Scope of every import today: an MFM export lands as one car.</summary>
    public const string Scope = "vehicle";

    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    /// <summary>
    /// Parses one uploaded file and stores it. The result envelope is returned
    /// and kept for <c>GET /import/{importId}</c>. Nothing is committed to any
    /// account (hard rule 9) - these are proposals the device reviews.
    /// </summary>
    public async Task<ImportParseResponse> ParseAsync(
        string formatId,
        string? contentType,
        Stream upload,
        Guid? accountId,
        Guid deviceId,
        CancellationToken cancellationToken)
    {
        // The format id was validated at the endpoint (415); the parser is the
        // single MFM implementation behind the one supported format id.
        var format = ImportFormats.All.Single(f => string.Equals(f.Id, formatId, StringComparison.OrdinalIgnoreCase));

        var bytes = await ReadWithLimitAsync(upload, _options.MaxFileBytes, cancellationToken);
        using var csvStream = new MemoryStream(bytes, writable: false);

        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        var result = MfmParser.Parse(csvStream, cancellationToken);
        stopwatch.Stop();

        var importId = Guid.NewGuid();
        var owner = accountId ?? deviceId;
        var fileKey = ImportKeys.FileKey(owner, importId);
        var resultKey = ImportKeys.ResultKey(owner, importId);

        var response = BuildResponse(importId, format.Id, result);

        // The stored file lets a bad parse be re-examined, and the stored result
        // lets the row-by-row review be resumed on another device or after a
        // crash (docs/SECURITY.md "Import files at rest" - the deliberate
        // asymmetry with /extract, which stores nothing).
        await _storage.PutObjectAsync(fileKey, bytes, contentType ?? "application/octet-stream", cancellationToken);
        await _storage.PutObjectAsync(resultKey, ToJsonBytes(response), "application/json", cancellationToken);

        await _repository.InsertAsync(
            importId,
            accountId,
            deviceId,
            format.Id,
            result.FileKind,
            fileKey,
            resultKey,
            result.DataRowCount,
            result.Candidates.Count,
            result.Unparsed.Count,
            cancellationToken);

        TankbookLog.ImportParse(
            _logger,
            format.Id,
            result.FileKind,
            result.DataRowCount,
            result.Candidates.Count,
            result.Unparsed.Count,
            result.Ambiguities.Count,
            stopwatch.Elapsed,
            "accepted");

        return response;
    }

    /// <summary>
    /// Re-reads a stored parse. Returns null when the id is unknown or belongs
    /// to another account (cross-account access is indistinguishable from
    /// absence, like the blob 404).
    /// </summary>
    public async Task<ImportParseResponse?> GetAsync(Guid importId, Guid? accountId, CancellationToken cancellationToken)
    {
        var row = await _repository.GetAsync(importId, cancellationToken);
        if (row is null || !CanAccess(row, accountId))
        {
            return null;
        }

        var resultBytes = await _storage.GetObjectAsync(row.ResultKey, cancellationToken);
        if (resultBytes is null)
        {
            return null;
        }

        return DeserializeResponse(resultBytes);
    }

    /// <summary>
    /// Drops a stored parse early (docs/API.md: cancel deletes the stored file).
    /// Idempotent: deleting a parse that is already gone - or that belongs to
    /// another account - is a no-op, never an error, and leaks no existence
    /// information to a non-owner.
    /// </summary>
    public async Task DeleteAsync(Guid importId, Guid? accountId, CancellationToken cancellationToken)
    {
        var row = await _repository.GetAsync(importId, cancellationToken);
        if (row is null || !CanAccess(row, accountId))
        {
            return;
        }

        await _storage.DeleteAsync(row.FileKey, cancellationToken);
        await _storage.DeleteAsync(row.ResultKey, cancellationToken);
        await _repository.DeleteAsync(importId, cancellationToken);

        TankbookLog.ImportDelete(_logger, row.Format, row.FileKind, "deleted");
    }

    /// <summary>Purges stored parses older than the cutoff, deleting the objects and the rows.</summary>
    public async Task<int> PurgeDueAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var due = await _repository.ListDueAsync(cutoff, cancellationToken);
        var deleted = await PurgeRowsAsync(due, cancellationToken);

        if (deleted > 0)
        {
            TankbookLog.ImportPurge(_logger, deleted);
        }

        return deleted;
    }

    /// <summary>Deletes every parse an account owns (docs/SECURITY.md: account deletion deletes these too).</summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var rows = await _repository.ListForAccountAsync(accountId, cancellationToken);
        return await PurgeRowsAsync(rows, cancellationToken);
    }

    private async Task<int> PurgeRowsAsync(IReadOnlyList<ImportParseRow> rows, CancellationToken cancellationToken)
    {
        if (rows.Count == 0)
        {
            return 0;
        }

        var keys = new List<string>(rows.Count * 2);
        foreach (var row in rows)
        {
            keys.Add(row.FileKey);
            keys.Add(row.ResultKey);
        }

        await _storage.DeleteManyAsync(keys, cancellationToken);
        await _repository.DeleteManyAsync(rows.Select(r => r.Id).ToList(), cancellationToken);
        return rows.Count;
    }

    private bool CanAccess(ImportParseRow row, Guid? accountId)
    {
        // An account-owned parse belongs to that account alone; a device-owned
        // parse (signed out) is governed by the importId capability.
        return row.AccountId is null || row.AccountId == accountId;
    }

    private static ImportParseResponse BuildResponse(Guid importId, string format, MfmParseResult result)
    {
        var candidates = new JsonArray(result.Candidates.Select(c => (JsonNode)c).ToArray());
        var unparsed = new JsonArray(result.Unparsed.Select(u => (JsonNode)new JsonObject
        {
            ["row"] = u.Row,
            ["reason"] = u.Reason,
        }).ToArray());
        var ambiguities = new JsonArray(result.Ambiguities.Select(a => (JsonNode)new JsonObject
        {
            ["kind"] = a.Kind,
            ["options"] = new JsonArray(a.Options.Select(o => (JsonNode)o).ToArray()),
            ["rowCount"] = a.RowCount,
        }).ToArray());

        return new ImportParseResponse(importId, format, Scope, candidates, unparsed, ambiguities);
    }

    private static byte[] ToJsonBytes(ImportParseResponse response)
        => JsonSerializer.SerializeToUtf8Bytes(response, WireJson);

    private static ImportParseResponse DeserializeResponse(byte[] bytes)
    {
        using var doc = JsonDocument.Parse(bytes);
        var root = doc.RootElement;
        var candidates = JsonSerializer.Deserialize<JsonNode>(root.GetProperty("candidates").GetRawText(), WireJson);
        var unparsed = JsonSerializer.Deserialize<JsonNode>(root.GetProperty("unparsed").GetRawText(), WireJson);
        var ambiguities = JsonSerializer.Deserialize<JsonNode>(root.GetProperty("ambiguities").GetRawText(), WireJson);
        return new ImportParseResponse(
            root.GetProperty("importId").GetGuid(),
            root.GetProperty("format").GetString()!,
            root.GetProperty("scope").GetString()!,
            candidates,
            unparsed,
            ambiguities);
    }

    private static async Task<byte[]> ReadWithLimitAsync(Stream stream, long maxBytes, CancellationToken cancellationToken)
    {
        using var buffer = new MemoryStream();
        var chunk = new byte[81920];
        long total = 0;
        int read;
        while ((read = await stream.ReadAsync(chunk, cancellationToken)) > 0)
        {
            total += read;
            if (total > maxBytes)
            {
                throw new ImportFileTooLargeException(maxBytes);
            }

            await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }

        return buffer.ToArray();
    }
}

/// <summary>The storage-key layout for import files (one subtree per owner, so the account blob-prefix purge covers them too).</summary>
public static class ImportKeys
{
    public static string FileKey(Guid owner, Guid importId) => $"{owner.ToString("N")}/imports/{importId.ToString("N")}/original";

    public static string ResultKey(Guid owner, Guid importId) => $"{owner.ToString("N")}/imports/{importId.ToString("N")}/result.json";
}
