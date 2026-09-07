namespace Tankbook.Api.Tests.Import;

/// <summary>
/// Locates the committed real Drivvo export (docs/TESTING.md fixture corpus:
/// Spike/ImportFixtures/drivvo/). Tests must parse the genuine export, not a
/// synthetic CSV - a file the parser's author invented cannot disagree with the
/// parser.
/// </summary>
internal static class DrivvoFixture
{
    public static readonly string Directory = Path.Combine(DocPaths.RepositoryRoot, "Spike", "ImportFixtures", "drivvo");

    public static string ThreeSectionsCsv => Path.Combine(Directory, "drivvo-ru-3sections.csv");

    public static Stream Open(string path) => File.OpenRead(path);

    public static byte[] ReadAllBytes(string path) => File.ReadAllBytes(path);
}
