namespace Tankbook.Api.Tests;

/// <summary>
/// Locates the repository <c>docs/</c> directory by walking up from the test
/// assembly location (docs/TESTING.md fixture corpus). The repo layout is fixed,
/// so the walk is deterministic: BaseDirectory -&gt; bin -&gt; project -&gt; ... -&gt; root.
/// </summary>
internal static class DocPaths
{
    public static readonly string RepositoryRoot = FindRepositoryRoot();

    public static readonly string SchemasV1 = Path.Combine(RepositoryRoot, "docs", "schemas", "v1");

    public static readonly string FixturesV1 = Path.Combine(RepositoryRoot, "docs", "fixtures", "payloads", "v1");

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "docs", "schemas", "v1")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException(
            "Could not locate the repository docs/ directory by walking up from the test assembly location.");
    }
}
