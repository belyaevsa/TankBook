using System.Text;
using Tankbook.Api.Sync;

namespace Tankbook.Api.Tests.Sync;

/// <summary>
/// Validation matrix per docs/TESTING.md "Payload contract" and docs/SYNC.md
/// "What the server enforces". Plain unit tests - the validator is constructed
/// directly against an in-memory schema provider; no host, no database.
/// </summary>
public class PayloadValidatorTests
{
    private const string EntityType = "vehicle";

    private static readonly PayloadValidator Validator =
        new(EmbeddedPayloadSchemaProvider(), minSupportedVersion: 1);

    private static EmbeddedPayloadSchemaProvider EmbeddedPayloadSchemaProvider()
        => new(typeof(Tankbook.Api.Sync.EmbeddedPayloadSchemaProvider).Assembly);

    private const string ValidVehiclePayload =
        """
        {
          "id": "11111111-1111-7111-8111-111111111111",
          "createdAt": "2026-01-10T09:30:00.000Z",
          "updatedAt": "2026-08-22T12:10:00.000Z",
          "name": "Volvo V60",
          "powertrain": "hybrid",
          "fuelKinds": ["petrol95", "electricity"],
          "homeCurrency": "EUR",
          "units": { "distance": "km", "volume": "l", "consumption": "lPer100", "energy": "kWhPer100" },
          "archived": false,
          "paceLimitKmPerDay": 1500
        }
        """;

    [Fact]
    public void Validate_WellFormedPayload_ForKnownEntity_Accepts()
    {
        var result = Validator.Validate(EntityType, 1, ValidVehiclePayload);

        Assert.True(result.IsAccepted);
        Assert.Equal(PayloadRejectionCode.None, result.Code);
    }

    [Theory]
    [InlineData("[1,2,3]")]
    [InlineData("\"just a string\"")]
    [InlineData("42")]
    [InlineData("null")]
    [InlineData("")]
    [InlineData("not json at all")]
    [InlineData("{\"unterminated\": true")]
    public void Validate_PayloadNotAJsonObject_RejectsPayloadInvalid(string payload)
    {
        var result = Validator.Validate(EntityType, 1, payload);

        Assert.Equal(PayloadRejectionCode.PayloadInvalid, result.Code);
        Assert.Equal("payload_invalid", result.WireCode);
        Assert.False(result.IsAccepted);
    }

    [Fact]
    public void Validate_PayloadLargerThan256Kb_RejectsPayloadInvalid()
    {
        var oversized = "{\"name\": \"" + new string('a', 256 * 1024) + "\"}";
        Assert.True(Encoding.UTF8.GetByteCount(oversized) > PayloadValidator.MaxPayloadBytes);

        var result = Validator.Validate(EntityType, 1, oversized);

        Assert.Equal(PayloadRejectionCode.PayloadInvalid, result.Code);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Validate_EmptyEntityType_RejectsPayloadInvalid(string entityType)
    {
        var result = Validator.Validate(entityType, 1, ValidVehiclePayload);

        Assert.Equal(PayloadRejectionCode.PayloadInvalid, result.Code);
    }

    [Fact]
    public void Validate_EntityTypeLongerThan64Chars_RejectsPayloadInvalid()
    {
        var longEntityType = new string('e', PayloadValidator.MaxEntityTypeLength + 1);

        var result = Validator.Validate(longEntityType, 1, ValidVehiclePayload);

        Assert.Equal(PayloadRejectionCode.PayloadInvalid, result.Code);
    }

    [Fact]
    public void Validate_EntityTypeAt64Chars_IsAccepted()
    {
        var entityType = new string('e', PayloadValidator.MaxEntityTypeLength);

        // 64-char entity type is structurally valid; it is simply unknown.
        var result = Validator.Validate(entityType, 1, "{\"anything\": \"goes\"}");

        Assert.True(result.IsAccepted, $"Expected a well-formed unknown entity to be accepted; got {result.WireCode}.");
    }

    [Fact]
    public void Validate_VersionNewerThanServerKnows_RejectsSchemaVersionUnsupported()
    {
        var result = Validator.Validate(EntityType, schemaVersion: 2, ValidVehiclePayload);

        Assert.Equal(PayloadRejectionCode.SchemaVersionUnsupported, result.Code);
        Assert.Equal("schema_version_unsupported", result.WireCode);
    }

    [Fact]
    public void Validate_VersionBelowMinSupported_RejectsUpgradeRequired()
    {
        var result = Validator.Validate(EntityType, schemaVersion: 0, ValidVehiclePayload);

        Assert.Equal(PayloadRejectionCode.UpgradeRequired, result.Code);
        Assert.Equal("upgrade_required", result.WireCode);
    }

    [Fact]
    public void Validate_SchemaViolation_PointerNamesTheOffendingField()
    {
        var badUuid = ValidVehiclePayload.Replace(
            "\"id\": \"11111111-1111-7111-8111-111111111111\"",
            "\"id\": \"not-a-uuid\"",
            StringComparison.Ordinal);

        var result = Validator.Validate(EntityType, 1, badUuid);

        Assert.Equal(PayloadRejectionCode.PayloadSchemaViolation, result.Code);
        Assert.Equal("payload_schema_violation", result.WireCode);
        Assert.Equal("/id", result.Pointer);
    }

    [Fact]
    public void Validate_SchemaViolation_MissingRequiredField_PointerNamesIt()
    {
        const string missingEverything = """{ "id": "11111111-1111-7111-8111-111111111111" }""";

        var result = Validator.Validate(EntityType, 1, missingEverything);

        Assert.Equal(PayloadRejectionCode.PayloadSchemaViolation, result.Code);
        Assert.Equal("/createdAt", result.Pointer);
    }

    [Fact]
    public void Validate_SchemaViolation_NestedField_PointerIsNested()
    {
        var badUnits = ValidVehiclePayload.Replace(
            "\"distance\": \"km\"",
            "\"distance\": 123",
            StringComparison.Ordinal);

        var result = Validator.Validate(EntityType, 1, badUnits);

        Assert.Equal(PayloadRejectionCode.PayloadSchemaViolation, result.Code);
        Assert.Equal("/units/distance", result.Pointer);
    }

    [Fact]
    public void Validate_UnknownEntityType_WithWellFormedEnvelope_IsAcceptedUnvalidated()
    {
        // A future entity (e.g. tireset on a newer client) must survive an older
        // server: well-formed envelope, no registered schema, accepted as-is.
        const string unknownPayload = """{ "treadDepthMm": 7, "season": "winter" }""";

        var result = Validator.Validate("tireset", 99, unknownPayload);

        Assert.True(result.IsAccepted);
        Assert.Equal(PayloadRejectionCode.None, result.Code);
    }

    [Fact]
    public void Validate_UnknownEntityType_WithMalformedEnvelope_StillRejects()
    {
        // Unknown does NOT mean unchecked: the envelope itself is still enforced.
        var result = Validator.Validate("tireset", 1, """[1,2,3]""");

        Assert.Equal(PayloadRejectionCode.PayloadInvalid, result.Code);
    }

    [Fact]
    public void WireCode_MatchesApiContractStrings()
    {
        Assert.Equal("payload_invalid", PayloadRejectionCode.PayloadInvalid.ToWireCode());
        Assert.Equal("schema_version_unsupported", PayloadRejectionCode.SchemaVersionUnsupported.ToWireCode());
        Assert.Equal("payload_schema_violation", PayloadRejectionCode.PayloadSchemaViolation.ToWireCode());
        Assert.Equal("upgrade_required", PayloadRejectionCode.UpgradeRequired.ToWireCode());
    }
}
