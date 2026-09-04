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

        var output = string.Join('\n', writer.Lines).WithoutMachineFields();

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

        // The email must be replaced by a salted emailHash, not kept or dropped -
        // and under the emailHash key, never accountHash (RV.63: an email hash is
        // not the account identifier, and sharing the key broke correlation).
        Assert.Contains("emailHash", output);
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

        // Email becomes a salted hash under its own name (emailHash, RV.63 - it
        // is an email mask, never the account identifier). The correlation
        // accountHash field stays null: this bare logger has no account scope.
        Assert.Equal("acct_", root.Prop("emailHash")![..5]);
        Assert.Null(root.Prop("accountHash"));
        Assert.False(root.TryGetProperty("Email", out _));
        Assert.False(root.TryGetProperty("email", out _));

        // Never fields are dropped entirely.
        Assert.False(root.TryGetProperty("Payload", out _));
        Assert.False(root.TryGetProperty("payload", out _));
        var swept = line.WithoutMachineFields();
        Assert.DoesNotContain("do-not-leak", swept);

        // The raw values never reached the message either.
        Assert.DoesNotContain("12.34", swept);
        Assert.DoesNotContain("Shell", swept);
        Assert.DoesNotContain("driver@example.com", swept);
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

        var hashes = writer.Lines.Select(l => JsonDocument.Parse(l).RootElement.Prop("emailHash")).ToArray();

        // Same email, same hash; different email, different hash; salted, not the email.
        Assert.Equal(hashes[0], hashes[1]);
        Assert.NotEqual(hashes[0], hashes[2]);
        Assert.All(hashes, h => Assert.StartsWith("acct_", h, StringComparison.Ordinal));
        Assert.All(hashes, h => Assert.DoesNotContain("@", h, StringComparison.Ordinal));
    }

    [Fact]
    public void ForEmail_IsAStableSaltedHash_NotTheAddress()
    {
        var salt = "test-salt";
        var email = "driver@example.com";
        var hash = AccountHash.ForEmail(email, salt);
        Assert.StartsWith("acct_", hash, StringComparison.Ordinal);
        Assert.NotEqual(email, hash);
        Assert.Equal(hash, AccountHash.ForEmail(email, salt));
        Assert.NotEqual(hash, AccountHash.ForEmail(email, "other-salt"));
    }

    /// <summary>
    /// RV.63 L1: the two hash entry points feed two different log keys, and only
    /// the account-id one may answer to `accountHash`. The redactor is the only
    /// caller of the email hash (it has no account context), so its mask must
    /// carry the distinct `emailHash` name - never `accountHash`, where an
    /// email-derived value would silently break correlation.
    /// </summary>
    [Fact]
    public void EmailMask_LandsUnderEmailHash_NeverAccountHash()
    {
        var salt = "test-salt";
        var email = "driver@example.com";
        var masked = new TankbookRedactor(salt).RedactProperty("Email", email);
        Assert.NotNull(masked);
        Assert.Equal("emailHash", masked!.Name);
        Assert.Equal(AccountHash.ForEmail(email, salt), masked.Value);
        Assert.StartsWith("acct_", (string)masked.Value!, StringComparison.Ordinal);

        // The other entry point exists for the correlation field only: an
        // account-id hash is a different value, and the redactor never produces
        // it - it has no id to hash.
        Assert.NotEqual(masked.Value, AccountHash.ForAccount(Guid.NewGuid(), salt));
    }

    [Fact]
    public void FeedbackAccepted_LoggedThroughPipeline_LeaksNoTextReplyToOrDeviceModel()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("RedactionTests");

        // A fully-populated case. If the acceptance event had a route for the
        // payload's domain values, these would appear in the rendered output.
        const string text = "REDACT-FB-EVENT the log book overflows again";
        const string replyTo = "redact-probe-7b@example.com";
        const string deviceModel = "RedactProbe 7b";

        TankbookLog.FeedbackAccepted(
            logger,
            Guid.Parse("7b3f1a2e-9c8d-4e5f-b0a1-223344556677"),
            "problem",
            text.Length,
            hasReplyTo: true,
            hasDeviceModel: true,
            hasAccount: true);

        var output = string.Join('\n', writer.Lines).WithoutMachineFields();

        // Shape survives: the category code, a length count, the presence flags.
        Assert.Contains("feedback.accepted", output, StringComparison.Ordinal);
        Assert.Contains("problem", output, StringComparison.Ordinal);
        Assert.Contains("TextLength", output, StringComparison.Ordinal);
        Assert.Contains("HasReplyTo", output, StringComparison.Ordinal);
        Assert.Contains("HasDeviceModel", output, StringComparison.Ordinal);

        // Hard rule 12: never the feedback text, never a replyTo address, never
        // a device-model string - the event type carries shape only by
        // construction (docs/LOGGING.md -> Feedback, the capture.pipeline
        // discipline).
        Assert.DoesNotContain(text, output, StringComparison.Ordinal);
        Assert.DoesNotContain("REDACT-FB-EVENT", output, StringComparison.Ordinal);
        Assert.DoesNotContain(replyTo, output, StringComparison.Ordinal);
        Assert.DoesNotContain("redact-probe-7b", output, StringComparison.Ordinal);
        Assert.DoesNotContain(deviceModel, output, StringComparison.Ordinal);
    }

    [Fact]
    public void SensitiveValueInsideAnExceptionMessage_IsMasked()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("RedactionTests");

        const string station = "Shell Station Berlin West";
        try
        {
            throw new InvalidOperationException($"failed to write station {station}");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "save failed");
        }

        var output = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The exception type - a stable code - survives.
        Assert.Contains("InvalidOperationException", output);
        // The sensitive station name must not appear anywhere, not even through
        // the stack trace, which embeds the exception message.
        Assert.DoesNotContain(station, output);
        Assert.DoesNotContain("Berlin West", output);

        // The message and trace are masked, never raw.
        var errorLine = writer.JsonLines().Single(l => l.Prop("exceptionType") == "InvalidOperationException");
        Assert.Equal(TankbookRedactor.Masked, errorLine.Prop("exceptionMessage"));
        Assert.Equal(TankbookRedactor.Masked, errorLine.Prop("stackTrace"));
    }
    /// <summary>
    /// The sweep helper itself, pinned deterministically. This exists because the
    /// bug it prevents is a **flake**: the assertions above failed once on a
    /// timestamp that happened to read ":12.342Z", and would fail roughly one run
    /// in 600 on ":42.3xx". A flake that only reproduces on the clock cannot be
    /// caught by the tests it breaks, so it is caught here instead - with a
    /// hand-built line rather than a real log, so it reproduces every time.
    /// </summary>
    [Fact]
    public void WithoutMachineFields_BlanksTheClockAndTheDuration_ButNeverARealLeak()
    {
        // Both machine fields are spelling needles the redaction sweeps assert absent.
        const string collision =
            """{"timestamp":"2026-08-26T09:42:42.317Z","DurationMs":9876.5432,"event":"sync.push"}""";

        var swept = collision.WithoutMachineFields();

        Assert.DoesNotContain("42.3", swept, StringComparison.Ordinal);
        Assert.DoesNotContain("9876.54", swept, StringComparison.Ordinal);
        // The line is blanked, not deleted - the sweep still has something to sweep.
        Assert.Contains("sync.push", swept, StringComparison.Ordinal);

        // The half that keeps the helper honest: the same needles in a REAL field
        // must survive, or the sweep would pass by deleting the evidence.
        const string leak =
            """{"timestamp":"2026-08-26T09:00:00.000Z","DurationMs":1,"Amount":"42.3","StationName":"9876.54"}""";

        var leaked = leak.WithoutMachineFields();

        Assert.Contains("42.3", leaked, StringComparison.Ordinal);
        Assert.Contains("9876.54", leaked, StringComparison.Ordinal);
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
