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
/// A column the parser has no home for, and how many rows of the uploaded file
/// carried a value in it (RV.116). The column NAME is the format's declared
/// name (see <see cref="ImportFormatInfo.UnsupportedColumns"/>); the count is a
/// property of THIS file, which is why it cannot live in GET /import/formats.
/// Counting non-empty cells in a column the parser already reads is inside hard
/// rule 9's import exception; the value itself is never read or logged.
/// </summary>
public sealed record ImportUnsupportedColumn(string Column, int RowCount);

/// <summary>
/// Reads one raw cell only far enough to say whether it carried a value
/// (RV.116). An unset cell is empty; a numeric column additionally treats a
/// zero-only cell as unset, because the formats write "0" there for "not
/// recorded" (Drivvo's discount is "0" on every row, and counting it would bury
/// the driver column that matters). Text columns pass <paramref name="zeroIsEmpty"/>
/// as false - a hex colour of "000000" is black, not absence. The content
/// itself is never returned or logged (hard rule 12).
/// </summary>
public static class ImportCell
{
    public static bool HasValue(string cell, bool zeroIsEmpty)
    {
        var trimmed = cell.Trim();
        if (trimmed.Length == 0)
        {
            return false;
        }

        if (!zeroIsEmpty)
        {
            return true;
        }

        var normalized = trimmed.Replace(',', '.');
        return !decimal.TryParse(
                   normalized,
                   System.Globalization.NumberStyles.Number,
                   System.Globalization.CultureInfo.InvariantCulture,
                   out var value)
               || value != 0m;
    }
}

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

    /// <summary>
    /// The format's unsupported columns that carried a value in at least one row
    /// of THIS file, with the count each (RV.116). A column empty in every row
    /// is omitted - a notice about nothing is noise.
    /// </summary>
    public required IReadOnlyList<ImportUnsupportedColumn> Unsupported { get; init; }

    /// <summary>
    /// The candidates grouped by the source file's vehicle-name column
    /// (RV.86). Ordered by first appearance of each name in the file; a
    /// single-name file yields one group covering every candidate. Each group
    /// lists the 1-based data-row numbers of its members, so the device can
    /// present "this file holds five cars, which do you want and into which
    /// garage car does each go" without re-deriving the parser's grouping.
    /// </summary>
    public required IReadOnlyList<MfmVehicleGroup> VehicleGroups { get; init; }
}

/// <summary>One distinct source vehicle in a parsed file (RV.86).</summary>
public sealed record MfmVehicleGroup(string Name, IReadOnlyList<int> SourceRows);

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

/// <summary>
/// The file's dates cannot be read as one order (RV.85): some rows only parse
/// as M/D/YYYY and others only as D/M/YYYY. One export has one format, so no
/// single answer exists - this is not the F6 <c>dateFormat</c> ambiguity (a
/// question the user could answer correctly), it is an inconsistent file, and
/// it surfaces as its own 422 (docs/API.md, docs/ERRORS.md) rather than a
/// guess. The parser is still a pure function - it commits nothing, and a file
/// that cannot be trusted is refused whole rather than half-read.
/// </summary>
public sealed class InconsistentDateOrderException : Exception
{
    public InconsistentDateOrderException(string detail)
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
    JsonNode? Ambiguities,
    JsonNode? VehicleGroups,
    JsonNode? Unsupported);
