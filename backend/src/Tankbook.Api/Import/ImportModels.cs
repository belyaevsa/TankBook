using System.Text.Json.Nodes;

namespace Tankbook.Api.Import;

/// <summary>
/// One row the parser could not map, with a stable reason code. The row number
/// counts data rows only, starting at 1 for the first row under the header - the
/// number a person reading the export would recognise (docs/API.md "Import
/// parsing": <c>unparsed: [ { row, reason } ]</c>).
/// </summary>
public sealed record UnparsedRow(int Row, string Reason);

/// <summary>
/// A once-per-file question the client must ask, never answer (F6, hard rule 13).
/// <c>options</c> are the candidate readings; the parser does not pick one
/// (docs/API.md "Import parsing": ambiguity is returned, never guessed).
/// </summary>
public sealed record ImportAmbiguity(string Kind, IReadOnlyList<string> Options, int RowCount);

/// <summary>
/// The result of parsing one file: entity-shaped candidate payloads, the rows
/// that failed with their reasons, and the ambiguities the client must resolve
/// once per file. Pure function output - it commits nothing (hard rule 9).
/// </summary>
public sealed class MfmParseResult
{
    public required string FileKind { get; init; }

    public required IReadOnlyList<JsonObject> Candidates { get; init; }

    public required IReadOnlyList<UnparsedRow> Unparsed { get; init; }

    public required IReadOnlyList<ImportAmbiguity> Ambiguities { get; init; }

    public required int DataRowCount { get; init; }
}

/// <summary>
/// The file does not look like the format the user declared (docs/API.md:
/// 422 "this does not look like a My Fuel Manager export"). Carries a detail
/// the client can surface verbatim.
/// </summary>
public sealed class NotMfmExportException : Exception
{
    public NotMfmExportException(string detail)
        : base(detail)
    {
        Detail = detail;
    }

    public string Detail { get; }
}

/// <summary>The stored-parse metadata row (migration 012). Counts only - never values (hard rule 12).</summary>
public sealed record ImportParseRow(
    Guid Id,
    Guid? AccountId,
    Guid DeviceId,
    string Format,
    string FileKind,
    string FileKey,
    string ResultKey,
    int RowsRead,
    int CandidateCount,
    int UnparsedCount,
    DateTime CreatedAt);

/// <summary>The wire envelope for a stored parse (docs/API.md "Import parsing").</summary>
public sealed record ImportParseResponse(
    Guid ImportId,
    string Format,
    string Scope,
    JsonNode? Candidates,
    JsonNode? Unparsed,
    JsonNode? Ambiguities);
