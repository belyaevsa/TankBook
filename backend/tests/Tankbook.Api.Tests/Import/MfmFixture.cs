namespace Tankbook.Api.Tests.Import;

/// <summary>
/// Locates the committed real My Fuel Manager export (docs/TESTING.md fixture
/// corpus: Spike/ImportFixtures/mfm/). Tests must parse the genuine export, not
/// a synthetic CSV - a file the parser's author invented cannot disagree with
/// the parser.
/// </summary>
internal static class MfmFixture
{
    public static readonly string Directory = Path.Combine(DocPaths.RepositoryRoot, "Spike", "ImportFixtures", "mfm");

    public static string FuelCsv => Path.Combine(Directory, "fuel.csv");

    public static string CostsCsv => Path.Combine(Directory, "costs.csv");

    public static string VehiclesCsv => Path.Combine(Directory, "vehicles.csv");

    public static string IncomesCsv => Path.Combine(Directory, "incomes.csv");

    public static string RemindersCsv => Path.Combine(Directory, "reminders.csv");

    public static Stream Open(string path) => File.OpenRead(path);

    public static byte[] ReadAllBytes(string path) => File.ReadAllBytes(path);

    /// <summary>All data rows of a fixture file as raw strings (title + header skipped), for independent recounts in tests.</summary>
    public static List<string[]> ReadDataRows(string path)
    {
        using var parser = new Microsoft.VisualBasic.FileIO.TextFieldParser(Open(path), System.Text.Encoding.UTF8, detectEncoding: true)
        {
            Delimiters = new[] { ";" },
            HasFieldsEnclosedInQuotes = true,
            TextFieldType = Microsoft.VisualBasic.FileIO.FieldType.Delimited,
            TrimWhiteSpace = false,
        };
        parser.ReadFields();
        parser.ReadFields();

        var rows = new List<string[]>();
        while (!parser.EndOfData)
        {
            rows.Add(parser.ReadFields()!);
        }

        return rows;
    }
}
