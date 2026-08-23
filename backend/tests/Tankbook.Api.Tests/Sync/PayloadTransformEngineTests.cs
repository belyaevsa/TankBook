using Tankbook.Api.Sync;

namespace Tankbook.Api.Tests.Sync;

/// <summary>
/// Declarative transform engine (docs/SYNC.md "Migrating payloads"): mechanical
/// JSON surgery with no domain knowledge. Each operation is idempotent, and an
/// unknown operation is refused rather than silently skipped.
/// </summary>
public class PayloadTransformEngineTests
{
    private readonly PayloadTransformEngine _engine = new();

    [Fact]
    public void Rename_MovesTheField()
    {
        const string transform = """[ { "op": "rename", "from": "oldName", "to": "newName" } ]""";

        var output = _engine.Apply("""{ "oldName": "value", "keep": 1 }""", transform);

        Assert.Equal("""{"keep":1,"newName":"value"}""", output);
    }

    [Fact]
    public void Rename_AtNestedObject_MovesTheFieldThere()
    {
        const string transform = """[ { "op": "rename", "at": "/inner", "from": "oldName", "to": "newName" } ]""";

        var output = _engine.Apply("""{ "inner": { "oldName": "v" } }""", transform);

        Assert.Equal("""{"inner":{"newName":"v"}}""", output);
    }

    [Fact]
    public void Rename_WhenSourceAbsent_IsANoOp()
    {
        const string transform = """[ { "op": "rename", "from": "missing", "to": "newName" } ]""";

        var output = _engine.Apply("""{ "keep": 1 }""", transform);

        Assert.Equal("""{"keep":1}""", output);
    }

    [Fact]
    public void AddDefault_AddsWhenAbsent_AndDoesNotOverwrite()
    {
        const string transform = """[ { "op": "addDefault", "name": "country", "value": "DE" } ]""";

        Assert.Equal(
            """{"keep":1,"country":"DE"}""",
            _engine.Apply("""{ "keep": 1 }""", transform));

        // Present value wins - the transform must never clobber user data.
        Assert.Equal(
            """{"country":"RU","keep":1}""",
            _engine.Apply("""{ "country": "RU", "keep": 1 }""", transform));
    }

    [Fact]
    public void AddDefault_SupportsObjectValues()
    {
        const string transform = """[ { "op": "addDefault", "name": "units", "value": { "distance": "km" } } ]""";

        var output = _engine.Apply("""{ "keep": 1 }""", transform);

        Assert.Equal("""{"keep":1,"units":{"distance":"km"}}""", output);
    }

    [Fact]
    public void Wrap_MovesFieldIntoANestedObject()
    {
        const string transform = """[ { "op": "wrap", "name": "price", "into": "money", "as": "amount" } ]""";

        var output = _engine.Apply("""{ "price": 5, "keep": 1 }""", transform);

        Assert.Equal("""{"keep":1,"money":{"amount":5}}""", output);
    }

    [Fact]
    public void Wrap_WithoutAs_UsesTheSameInnerName()
    {
        const string transform = """[ { "op": "wrap", "name": "odometer", "into": "reading" } ]""";

        var output = _engine.Apply("""{ "odometer": 12345 }""", transform);

        Assert.Equal("""{"reading":{"odometer":12345}}""", output);
    }

    [Fact]
    public void Wrap_WhenSourceAbsent_IsANoOp()
    {
        const string transform = """[ { "op": "wrap", "name": "missing", "into": "wrapper" } ]""";

        var output = _engine.Apply("""{ "keep": 1 }""", transform);

        Assert.Equal("""{"keep":1}""", output);
    }

    [Fact]
    public void RemoveDeprecated_DeletesTheField()
    {
        const string transform = """[ { "op": "removeDeprecated", "name": "legacyField" } ]""";

        var output = _engine.Apply("""{ "legacyField": true, "keep": 1 }""", transform);

        Assert.Equal("""{"keep":1}""", output);
    }

    [Fact]
    public void OrderedOperations_ApplyInSequence()
    {
        const string transform = """
            [
              { "op": "rename", "from": "price", "to": "amount" },
              { "op": "wrap", "name": "amount", "into": "money", "as": "amount" },
              { "op": "addDefault", "name": "currency", "value": "EUR", "at": "/money" },
              { "op": "removeDeprecated", "name": "obsolete" }
            ]
            """;

        var output = _engine.Apply("""{ "price": 12.5, "obsolete": "gone" }""", transform);

        Assert.Equal("""{"money":{"amount":12.5,"currency":"EUR"}}""", output);
    }

    [Fact]
    public void ApplyingTheSameTransformTwice_IsIdempotent()
    {
        const string transform = """
            [
              { "op": "rename", "from": "oldName", "to": "newName" },
              { "op": "addDefault", "name": "country", "value": "DE" },
              { "op": "wrap", "name": "price", "into": "money", "as": "amount" },
              { "op": "removeDeprecated", "name": "legacyField" }
            ]
            """;
        const string payload = """{ "oldName": "x", "price": 5, "legacyField": true, "keep": 1 }""";

        var once = _engine.Apply(payload, transform);
        var twice = _engine.Apply(once, transform);

        Assert.Equal(once, twice);
    }

    [Fact]
    public void UnknownOperation_IsRefusedNotSilentlySkipped()
    {
        const string transform = """[ { "op": "teleport", "name": "x" } ]""";

        var ex = Assert.Throws<InvalidOperationException>(() => _engine.Apply("""{ "keep": 1 }""", transform));
        Assert.Contains("teleport", ex.Message);
    }

    [Fact]
    public void MalformedOperation_MissingRequiredField_IsRefused()
    {
        const string transform = """[ { "op": "rename", "to": "newName" } ]""";

        Assert.Throws<InvalidOperationException>(() => _engine.Apply("""{ "keep": 1 }""", transform));
    }

    [Fact]
    public void NonArrayTransform_IsRefused()
    {
        const string transform = """{ "op": "rename" }""";

        Assert.Throws<ArgumentException>(() => _engine.Apply("""{ "keep": 1 }""", transform));
    }
}
