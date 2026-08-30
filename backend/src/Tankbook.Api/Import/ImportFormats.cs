namespace Tankbook.Api.Import;

/// <summary>One supported import source (docs/API.md "Import parsing": GET /import/formats).</summary>
public sealed record ImportFormatInfo(string Id, string DisplayName, string[] FileKinds, string? HelpUrl, int AddedInPackVersion);

/// <summary>
/// The server-side registry of import parsers. The endpoint serves whatever is
/// listed here, so the client renders this list and an older client simply shows
/// fewer options - adding a parser is a server change, never an App Store
/// release (docs/API.md "Import parsing"). Today there is exactly one format.
/// </summary>
public static class ImportFormats
{
    public static readonly IReadOnlyList<ImportFormatInfo> All =
    [
        // PJ.33: HelpUrl points at the site's per-source export guide (site/content/import-guide.md).
        // A link that 404s is worse than no link (hard rule 7), so the page must exist before the
        // URL ships - the guide page and this value land in the same change.
        new("mfm", "My Fuel Manager", ["csv"], HelpUrl: "https://tankbook.live/import-guide/", AddedInPackVersion: 1),
    ];

    public static bool TryGet(string id, out ImportFormatInfo format)
    {
        format = All.FirstOrDefault(f => string.Equals(f.Id, id, StringComparison.OrdinalIgnoreCase))!;
        return format is not null;
    }
}
