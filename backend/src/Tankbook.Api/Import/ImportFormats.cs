namespace Tankbook.Api.Import;

/// <summary>
/// One supported import source (docs/API.md "Import parsing": GET /import/formats).
/// <c>UnsupportedColumns</c> is the format's complement - the columns the parser
/// has no home for (docs/SCHEMA.md "Import mapping"). It is declared here, in
/// data, so a new importer cannot forget it and the copy does not rot in the
/// client (RV.116). Only the NAMES live here; how many rows carried a value is a
/// property of one uploaded file and rides the parse response instead.
/// </summary>
public sealed record ImportFormatInfo(
    string Id,
    string DisplayName,
    string[] FileKinds,
    string? HelpUrl,
    int AddedInPackVersion,
    string[] UnsupportedColumns);

/// <summary>
/// The server-side registry of import parsers. The endpoint serves whatever is
/// listed here, so the client renders this list and an older client simply shows
/// fewer options - adding a parser is a server change, never an App Store
/// release (docs/API.md "Import parsing").
/// </summary>
public static class ImportFormats
{
    public static readonly IReadOnlyList<ImportFormatInfo> All =
    [
        // PJ.33: HelpUrl points at the site's per-source export guide (site/content/import-guide.md).
        // A link that 404s is worse than no link (hard rule 7), so the page must exist before the
        // URL ships - the guide page and this value land in the same change.
        //
        // RV.116: MFM's unmapped columns are the vehicles.csv ones (docs/SCHEMA.md
        // "Import mapping"). fuel.csv and costs.csv map every column; incomes.csv
        // and reminders.csv are whole-file out of scope, which the `outOfScope`
        // ambiguity already reports. The names are the export's own header text,
        // so the notice matches what the user sees in the file.
        new("mfm", "My Fuel Manager", ["csv"], HelpUrl: "https://tankbook.live/import-guide/",
            AddedInPackVersion: 1,
            UnsupportedColumns:
            [
                "Vehicle price",
                "Initial tank status",
                "LPG tank volume",
                "Initial LPG tank status",
                "Color",
            ]),
        // RV.116: Drivvo's 29-column refuelling row carries a whole fleet feature
        // set Tankbook does not model - the driver (Drivvo's positioning),
        // payment method, discount, second/third fuel blocks, the derived
        // consumption/distance figures and the EV columns a liquid fill leaves
        // blank. The Expense/Service sections repeat driver/payment/discount and
        // Expense adds its local-cost column. The parser reports the count only
        // for the columns that actually carried a value (the empty ones are
        // omitted from the parse response).
        new("drivvo", "Drivvo", ["csv"], HelpUrl: "https://tankbook.live/import-guide/",
            AddedInPackVersion: 1,
            UnsupportedColumns:
            [
                "Second fuel",
                "Third fuel",
                "Charge type",
                "Charge start %",
                "Charge end %",
                "Charge duration",
                "Driver",
                "Expense type",
                "Payment method",
                "Discount",
                "Local cost",
            ]),
    ];

    public static bool TryGet(string id, out ImportFormatInfo format)
    {
        format = All.FirstOrDefault(f => string.Equals(f.Id, id, StringComparison.OrdinalIgnoreCase))!;
        return format is not null;
    }
}
