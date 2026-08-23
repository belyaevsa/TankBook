using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>
/// docs/LOGGING.md §7: feed a fully populated entity through the real log
/// pipeline and assert no Sensitive/Never value appears in the emitted output.
/// </summary>
public class RedactionTests
{
    [Fact]
    public void PopulatedEntity_LoggedThroughPipeline_LeaksNoSensitiveOrNeverValue()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("RedactionTests");

        var entity = new
        {
            Id = Guid.Parse("6f1e4d7a-2b3c-4d5e-8f9a-0b1c2d3e4f5a"),
            EntityType = "fillup",
            SchemaVersion = 3,
            StationName = "Shell Station Berlin West",
            Note = "refuel before the weekend trip",
            Amount = 289.50m,
            HomeAmount = 67.79m,
            VolumeL = 42.3,
            Odometer = 119486,
            Coordinates = "52.5200,13.4050",
            Plate = "B-AB 1234",
            Email = "driver@example.com",
            Token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake-token",
            Payload = new { Field = "a secret payload value", Nested = new { Amount = 999.99m } },
            CreatedAt = new DateTimeOffset(2026, 8, 23, 9, 30, 0, TimeSpan.Zero),
        };

        logger.LogInformation("populated entity {@Entity}", entity);

        var output = string.Join('\n', writer.Lines);

        // Sensitive values must not appear anywhere.
        Assert.DoesNotContain("Shell Station Berlin West", output);
        Assert.DoesNotContain("refuel before the weekend trip", output);
        Assert.DoesNotContain("289.50", output);
        Assert.DoesNotContain("67.79", output);
        Assert.DoesNotContain("42.3", output);
        Assert.DoesNotContain("119486", output);
        Assert.DoesNotContain("52.5200", output);
        Assert.DoesNotContain("13.4050", output);
        Assert.DoesNotContain("B-AB 1234", output);

        // Never values must not appear, not even as a field name.
        Assert.DoesNotContain("eyJhbGciOi", output);
        Assert.DoesNotContain("a secret payload value", output);
        Assert.DoesNotContain("999.99", output);
        Assert.DoesNotContain("driver@example.com", output);

        // The email must be replaced by a salted accountHash, not kept or dropped.
        Assert.Contains("accountHash", output);
        Assert.Contains("acct_", output);

        // Safe identity fields survive.
        Assert.Contains("fillup", output);
        Assert.Contains("6f1e4d7a", output);
    }

    [Fact]
    public void NamedFields_LoggedByValue_MaskEverySensitiveAndDropEveryNeverField()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("RedactionTests");

        logger.LogWarning(
            "payment of {Amount} at {StationName} for {Email}; payload {Payload}",
            12.34m,
            "Shell",
            "driver@example.com",
            new { secret = "do-not-leak" });

        var line = writer.Lines.ShouldHaveSingleLine();
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;

        // Masked, not absent: the field name stays, the value is the sentinel.
        Assert.Equal(TankbookRedactor.Masked, root.Prop("Amount"));
        Assert.Equal(TankbookRedactor.Masked, root.Prop("StationName"));

        // Email becomes the correlation hash under its own name.
        Assert.Equal("acct_", root.Prop("accountHash")![..5]);
        Assert.False(root.TryGetProperty("Email", out _));
        Assert.False(root.TryGetProperty("email", out _));

        // Never fields are dropped entirely.
        Assert.False(root.TryGetProperty("Payload", out _));
        Assert.False(root.TryGetProperty("payload", out _));
        Assert.DoesNotContain("do-not-leak", line);

        // The raw values never reached the message either.
        Assert.DoesNotContain("12.34", line);
        Assert.DoesNotContain("Shell", line);
        Assert.DoesNotContain("driver@example.com", line);
    }

    [Fact]
    public void AuthSessionProvider_EnumToken_SurvivesButChargeProvider_IsMasked()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("RedactionTests");

        TankbookLog.AuthSession(logger, "apple", "created");
        TankbookLog.AuthSession(logger, "Ionity", "matched");

        var lines = writer.Lines;
        var first = JsonDocument.Parse(lines[0]).RootElement;
        var second = JsonDocument.Parse(lines[1]).RootElement;

        // auth.session provider is a Safe enum token.
        Assert.Equal("apple", first.Prop("Provider"));
        // A vendor-style provider value is Sensitive and masked.
        Assert.Equal(TankbookRedactor.Masked, second.Prop("Provider"));
    }

    [Fact]
    public void EmailHash_IsStableAndSalted()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("RedactionTests");

        logger.LogInformation("first {Email}", "driver@example.com");
        logger.LogInformation("second {Email}", "driver@example.com");
        logger.LogInformation("other {Email}", "someone@example.com");

        var hashes = writer.Lines.Select(l => JsonDocument.Parse(l).RootElement.Prop("accountHash")).ToArray();

        // Same email, same hash; different email, different hash; salted, not the email.
        Assert.Equal(hashes[0], hashes[1]);
        Assert.NotEqual(hashes[0], hashes[2]);
        Assert.All(hashes, h => Assert.StartsWith("acct_", h, StringComparison.Ordinal));
        Assert.All(hashes, h => Assert.DoesNotContain("@", h, StringComparison.Ordinal));
    }

    [Fact]
    public void AccountHash_IsTheStableHash_NotTheEmail()
    {
        var salt = "test-salt";
        var email = "driver@example.com";
        var hash = AccountHash.Compute(email, salt);
        Assert.StartsWith("acct_", hash, StringComparison.Ordinal);
        Assert.NotEqual(email, hash);
        Assert.Equal(hash, AccountHash.Compute(email, salt));
        Assert.NotEqual(hash, AccountHash.Compute(email, "other-salt"));
    }
}

internal static class RedactionTestExtensions
{
    public static string ShouldHaveSingleLine(this IReadOnlyList<string> lines)
    {
        Assert.Single(lines);
        return lines[0];
    }
}
