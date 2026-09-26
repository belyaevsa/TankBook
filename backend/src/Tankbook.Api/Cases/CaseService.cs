using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Cases;

/// <summary>Why an upload was refused, with the HTTP status and code it maps to.</summary>
public sealed class CaseRejectedException : Exception
{
    public CaseRejectedException(int status, string code, string detail)
        : base(detail)
    {
        Status = status;
        Code = code;
    }

    public int Status { get; }

    public string Code { get; }
}

/// <summary>One part as received, before it is stored.</summary>
public sealed record CaseUpload(string Name, string ContentType, byte[] Bytes);

/// <summary>
/// Debug cases (hard rule 9's debug-cases amendment): a bundle the user chose to
/// send - the app's log, recent scan photos and their pipeline traces - stored
/// so the owner can read it by the id the phone shows. The server enforces the
/// envelope (part count, names, content types, sizes) and never reads a part
/// (hard rule 9). Works signed out: the case is then stored under the device
/// identity. Logs carry shape only (hard rule 12).
/// </summary>
public sealed partial class CaseService
{
    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "text/plain", "application/json", "image/jpeg", "image/png", "image/heic",
    };

    private readonly CaseRepository _repository;
    private readonly IBlobStorage _storage;
    private readonly CaseOptions _options;
    private readonly TimeProvider _time;
    private readonly ILogger<CaseService> _logger;

    public CaseService(CaseRepository repository, IBlobStorage storage, IOptions<CaseOptions> options,
                       TimeProvider time, ILogger<CaseService> logger)
    {
        _repository = repository;
        _storage = storage;
        _options = options.Value;
        _time = time;
        _logger = logger;
    }

    /// <summary>Validates the envelope, stores every part, then the index row; returns the new case.</summary>
    public async Task<CaseRow> AcceptAsync(IReadOnlyList<CaseUpload> uploads, Guid? accountId, Guid deviceId,
                                           string? app, CancellationToken cancellationToken)
    {
        Validate(uploads);
        var id = CaseIds.New();
        var owner = accountId ?? deviceId;
        var parts = new List<CasePart>(uploads.Count);
        foreach (var upload in uploads)
        {
            var key = CaseKeys.PartKey(owner, id, upload.Name);
            await _storage.PutObjectAsync(key, upload.Bytes, upload.ContentType, cancellationToken);
            parts.Add(new CasePart(upload.Name, upload.ContentType, upload.Bytes.LongLength, key));
        }

        var row = new CaseRow(id, accountId, deviceId, app, parts, parts.Sum(p => p.Bytes), _time.GetUtcNow());
        await _repository.InsertAsync(row, cancellationToken);
        TankbookLog.CaseAccepted(_logger, id, parts.Count, row.TotalBytes, accountId is not null);
        return row;
    }

    /// <summary>
    /// When a case stops being kept, in whole seconds UTC: the wire carries it as plain
    /// ISO 8601, which every client's decoder reads without fractional-second support.
    /// </summary>
    public DateTimeOffset ExpiresAt(CaseRow row)
    {
        var expires = (row.CreatedAt + _options.RetentionPeriod).ToUniversalTime();
        return new DateTimeOffset(expires.Ticks - (expires.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }

    /// <summary>Purges cases older than the cutoff: the objects, then the rows.</summary>
    public async Task<int> PurgeDueAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var purged = await PurgeRowsAsync(await _repository.ListDueAsync(cutoff, cancellationToken), cancellationToken);
        if (purged > 0)
        {
            TankbookLog.CasePurge(_logger, purged);
        }

        return purged;
    }

    /// <summary>Deletes every case an account sent (docs/SECURITY.md: account deletion deletes these too).</summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
        => await PurgeRowsAsync(await _repository.ListForAccountAsync(accountId, cancellationToken), cancellationToken);

    private async Task<int> PurgeRowsAsync(IReadOnlyList<CaseRow> rows, CancellationToken cancellationToken)
    {
        if (rows.Count == 0)
        {
            return 0;
        }

        await _storage.DeleteManyAsync(rows.SelectMany(r => r.Parts.Select(p => p.Key)).ToList(), cancellationToken);
        await _repository.DeleteManyAsync(rows.Select(r => r.Id).ToList(), cancellationToken);
        return rows.Count;
    }

    private static void Validate(IReadOnlyList<CaseUpload> uploads)
    {
        if (uploads.Count == 0)
        {
            throw new CaseRejectedException(StatusCodes.Status400BadRequest, TankbookErrorCodes.PayloadInvalid,
                "A case carries at least one part.");
        }

        if (uploads.Count > CaseOptions.MaxParts)
        {
            throw new CaseRejectedException(StatusCodes.Status413PayloadTooLarge, TankbookErrorCodes.PayloadTooLarge,
                $"A case carries at most {CaseOptions.MaxParts} parts.");
        }

        var names = new HashSet<string>(StringComparer.Ordinal);
        long total = 0;
        foreach (var upload in uploads)
        {
            if (!PartName().IsMatch(upload.Name) || !names.Add(upload.Name))
            {
                throw new CaseRejectedException(StatusCodes.Status400BadRequest, TankbookErrorCodes.PayloadInvalid,
                    "Each part needs a unique name of lower-case letters, digits, dots, dashes or underscores.");
            }

            if (!AllowedContentTypes.Contains(upload.ContentType))
            {
                throw new CaseRejectedException(StatusCodes.Status415UnsupportedMediaType,
                    TankbookErrorCodes.PayloadInvalid,
                    "A part is text, JSON or an image (JPEG, PNG, HEIC).");
            }

            if (upload.Bytes.LongLength > CaseOptions.MaxPartBytes)
            {
                throw new CaseRejectedException(StatusCodes.Status413PayloadTooLarge, TankbookErrorCodes.PayloadTooLarge,
                    $"A part is at most {CaseOptions.MaxPartBytes} bytes.");
            }

            total += upload.Bytes.LongLength;
        }

        if (total > CaseOptions.MaxTotalBytes)
        {
            throw new CaseRejectedException(StatusCodes.Status413PayloadTooLarge, TankbookErrorCodes.PayloadTooLarge,
                $"A case is at most {CaseOptions.MaxTotalBytes} bytes.");
        }
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]{0,63}$")]
    private static partial Regex PartName();
}

/// <summary>Storage keys for case parts, under the owner's prefix like every other stored object.</summary>
public static class CaseKeys
{
    public static string PartKey(Guid owner, string caseId, string partName)
        => $"{owner.ToString("N")}/cases/{caseId}/{partName}";
}
