using Tankbook.Api.Sync;

namespace Tankbook.Api.Tests.Sync;

/// <summary>
/// Fixture conformance (docs/TESTING.md "Payload contract"): every fixture in
/// docs/fixtures/payloads/v1/ must validate against its own version's schema.
/// The fixture corpus and schemas are located by walking up from the test
/// assembly location to the repo docs/ directory - the tests read the exact
/// files the server and the iOS client share.
/// </summary>
public class PayloadFixtureConformanceTests
{
    private readonly DirectorySchemaProvider _schemas = DirectorySchemaProvider.FromV1(DocPaths.SchemasV1);

    [Fact]
    public void EveryV1Fixture_ValidatesAgainstItsOwnSchema()
    {
        var validator = new PayloadValidator(_schemas, minSupportedVersion: 1);
        var failures = new List<string>();

        foreach (var fixturePath in Directory.EnumerateFiles(DocPaths.FixturesV1, "*.json").OrderBy(f => f, StringComparer.Ordinal))
        {
            var entityType = Path.GetFileNameWithoutExtension(fixturePath);
            var payload = File.ReadAllText(fixturePath);
            var result = validator.Validate(entityType, 1, payload);

            if (!result.IsAccepted)
            {
                failures.Add($"{entityType}: {result.WireCode} at {result.Pointer}");
            }
        }

        Assert.True(failures.Count == 0, "Fixtures failing conformance:\n" + string.Join("\n", failures));
    }

    [Fact]
    public void FixtureCorpus_CoversEveryRegisteredEntity()
    {
        var fixtureEntities = Directory.EnumerateFiles(DocPaths.FixturesV1, "*.json")
            .Select(Path.GetFileNameWithoutExtension)
            .ToHashSet(StringComparer.Ordinal);

        var schemaEntities = new List<string>();
        foreach (var schemaPath in Directory.EnumerateFiles(DocPaths.SchemasV1, "*.schema.json"))
        {
            schemaEntities.Add(Path.GetFileName(schemaPath)[..^".schema.json".Length]);
        }

        var missingFixtures = schemaEntities.Where(e => !fixtureEntities.Contains(e)).ToList();
        Assert.True(
            missingFixtures.Count == 0,
            "Registered entities without a v1 fixture: " + string.Join(", ", missingFixtures));
    }
}
