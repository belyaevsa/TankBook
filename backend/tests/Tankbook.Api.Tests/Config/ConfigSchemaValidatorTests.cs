using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// The config document JSON Schema is enforced at PUBLISH TIME (docs/CONFIG.md),
/// so a malformed document never reaches a device. Pure unit tests against the
/// embedded schema - no host, no database.
/// </summary>
public class ConfigSchemaValidatorTests
{
    private static readonly ConfigSchemaValidator Validator = new();

    [Fact]
    public void ValidBaselineDocument_IsAccepted()
    {
        Assert.Empty(Validator.Validate(ConfigTestData.Document()));
    }

    [Fact]
    public void MissingRequiredField_IsRejected()
    {
        var missing = ConfigTestData.Document()
            .Replace("\"tier2OnDeviceLLM\":true,", "", StringComparison.Ordinal);

        var errors = Validator.Validate(missing);
        Assert.NotEmpty(errors);
        Assert.Contains(errors, e => e.Contains("tier2OnDeviceLLM", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData("\"tier3CloudFallback\":\"yes\"")]
    [InlineData("\"minSchemaVersion\":\"1\"")]
    public void WrongTypedField_IsRejected(string replacement)
    {
        var doc = ConfigTestData.Document().Replace("\"tier3CloudFallback\":true", replacement, StringComparison.Ordinal);

        Assert.NotEmpty(Validator.Validate(doc));
    }

    [Fact]
    public void NotJson_IsRejected()
    {
        Assert.NotEmpty(Validator.Validate("this is not json"));
    }

    [Fact]
    public void NonObjectRoot_IsRejected()
    {
        Assert.NotEmpty(Validator.Validate("[1,2,3]"));
    }

    [Fact]
    public void VersionZeroOrNegative_IsRejected()
    {
        var zero = ConfigTestData.Document(version: 0);
        Assert.Contains(Validator.Validate(zero), e => e.Contains("version", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void ApiBaseUrl_HttpScheme_IsRejected()
    {
        var http = ConfigTestData.Document(apiBaseUrl: "http://api.tankbook.app");

        Assert.NotEmpty(Validator.Validate(http));
    }

    [Fact]
    public void ApiBaseUrl_Https_IsAccepted()
    {
        var https = ConfigTestData.Document(apiBaseUrl: "https://api.tankbook.app");

        Assert.Empty(Validator.Validate(https));
    }

    [Theory]
    [InlineData(1.5)]
    [InlineData(-0.1)]
    public void OcrConfidenceThreshold_OutsideZeroToOne_IsRejected(double threshold)
    {
        var doc = ConfigTestData.Document().Replace(
            "\"ocrConfidenceThreshold\":0.75",
            "\"ocrConfidenceThreshold\":" + threshold.ToString(System.Globalization.CultureInfo.InvariantCulture),
            StringComparison.Ordinal);

        Assert.NotEmpty(Validator.Validate(doc));
    }

    [Fact]
    public void FlagRolloutPercent_OverOneHundred_IsRejected()
    {
        var doc = ConfigTestData.Document().Replace(
            "\"rolloutSalt\":\"test-rollout-salt\"",
            "\"rolloutSalt\":\"test-rollout-salt\",\"flags\":{\"newHome\":{\"enabled\":true,\"rolloutPercent\":150}}",
            StringComparison.Ordinal);

        Assert.NotEmpty(Validator.Validate(doc));
    }

    [Fact]
    public void ValidFlag_IsAccepted()
    {
        var doc = ConfigTestData.Document().Replace(
            "\"rolloutSalt\":\"test-rollout-salt\"",
            "\"rolloutSalt\":\"test-rollout-salt\",\"flags\":{\"newHome\":{\"enabled\":false,\"rolloutPercent\":10}}",
            StringComparison.Ordinal);

        Assert.Empty(Validator.Validate(doc));
    }

    [Fact]
    public void UnknownTopLevelKey_IsIgnored_ForwardCompatibility()
    {
        // docs/CONFIG.md: one unknown key in an otherwise valid document is
        // ignored client-side; the schema must stay open so future keys publish.
        var doc = ConfigTestData.Document().Replace(
            "\"rolloutSalt\":\"test-rollout-salt\"",
            "\"rolloutSalt\":\"test-rollout-salt\",\"futureThing\":{\"x\":1}",
            StringComparison.Ordinal);

        Assert.Empty(Validator.Validate(doc));
    }
}
