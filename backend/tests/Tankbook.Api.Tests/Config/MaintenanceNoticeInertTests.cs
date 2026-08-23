using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// The maintenance notice is inert (docs/CONFIG.md "Defence in depth"): a
/// signed-but-attacker-authored notice would otherwise be an in-app phishing
/// surface, so plain text only. The stricter rule is implemented: a notice
/// containing HTML or markup is REJECTED at publish time, so it can never reach
/// a device, let alone render.
/// </summary>
public class MaintenanceNoticeInertTests
{
    private static readonly ConfigSchemaValidator Validator = new();

    [Theory]
    [InlineData("Planned downtime <b>tomorrow</b>")]
    [InlineData("Click <a href=\"https://evil.example\">here</a>")]
    [InlineData("50% &amp; 100%")]
    [InlineData("Use &lt;script&gt;")]
    public void MaintenanceTextWithMarkup_IsRejected(string markup)
    {
        var doc = ConfigTestData.Document(maintenanceText: markup);

        var errors = Validator.Validate(doc);
        Assert.NotEmpty(errors);
        Assert.Contains(errors, e => e.Contains("maintenance", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void MaintenancePlainText_IsAccepted()
    {
        var doc = ConfigTestData.Document(maintenanceText: "Planned maintenance on Sunday 06:00-08:00 UTC.");

        Assert.Empty(Validator.Validate(doc));
    }

    [Fact]
    public void Maintenance_UnknownExtraKey_IsRejected()
    {
        // additionalProperties: false on maintenance - a notice carries exactly
        // text/severity/until, nothing a phisher could hide a link in.
        var doc = ConfigTestData.Document().Replace(
            "\"rolloutSalt\":\"test-rollout-salt\"",
            "\"rolloutSalt\":\"test-rollout-salt\",\"maintenance\":{\"text\":\"Hi\",\"severity\":\"info\",\"until\":\"2026-12-31T00:00:00Z\",\"url\":\"https://evil.example\"}",
            StringComparison.Ordinal);

        Assert.NotEmpty(Validator.Validate(doc));
    }

    [Theory]
    [InlineData("critical")]
    [InlineData("")]
    public void Maintenance_UnknownSeverity_IsRejected(string severity)
    {
        var doc = ConfigTestData.Document().Replace(
            "\"rolloutSalt\":\"test-rollout-salt\"",
            $"\"rolloutSalt\":\"test-rollout-salt\",\"maintenance\":{{\"text\":\"Hi\",\"severity\":\"{severity}\",\"until\":\"2026-12-31T00:00:00Z\"}}",
            StringComparison.Ordinal);

        Assert.NotEmpty(Validator.Validate(doc));
    }

    [Fact]
    public void Maintenance_MissingField_IsRejected()
    {
        var doc = ConfigTestData.Document().Replace(
            "\"rolloutSalt\":\"test-rollout-salt\"",
            "\"rolloutSalt\":\"test-rollout-salt\",\"maintenance\":{\"text\":\"Hi\",\"severity\":\"info\"}",
            StringComparison.Ordinal);

        Assert.NotEmpty(Validator.Validate(doc));
    }

    [Fact]
    public async Task PublishRefusesDocumentWithMarkupInNotice()
    {
        // End-to-end at the publish seam: the notice is rejected BEFORE any
        // signing can happen (the schema gate is the first publish check).
        var service = new ConfigPublishService(
            new ConfigRepository(new Npgsql.NpgsqlConnection("Host=localhost")),
            Validator,
            ConfigTestData.Signer,
            Microsoft.Extensions.Logging.Abstractions.NullLogger<ConfigPublishService>.Instance);

        var result = await service.PublishAsync(
            ConfigTestData.Document(maintenanceText: "<b>downtime</b>"),
            CancellationToken.None);

        Assert.False(result.IsSuccess);
        Assert.Equal(ConfigPublishErrorKind.SchemaValidationFailed, result.Error.Kind);
    }
}
