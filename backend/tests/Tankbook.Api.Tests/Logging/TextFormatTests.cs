using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>
/// The human-readable line's shape (docs/LOGGING.md, changed 2026-09-03):
///
///   2026-09-03 07:36:39 | INFORMATION | [Category] [traceId] message · field=value
///
/// The deploy host is read by eye with `docker logs`, so this format is the
/// product, not an implementation detail - which is why it is pinned rather
/// than left to whatever the renderer happens to emit.
///
/// The JSON rendering is asserted elsewhere and is deliberately UNCHANGED: a
/// collector still gets every field, including the ones text drops.
/// </summary>
public class TextFormatTests
{
    private static (ILoggerFactory Factory, InMemoryLogWriter Writer) BuildText()
    {
        var writer = new InMemoryLogWriter([]);
        var provider = new TankbookLoggerProvider(
            new LogRenderer(new TankbookRedactor("test-salt"), "0.1.0-test", json: false),
            writer);
        var factory = LoggerFactory.Create(builder =>
        {
            builder.ClearProviders();
            builder.SetMinimumLevel(LogLevel.Debug);
            builder.AddProvider(provider);
        });
        return (factory, writer);
    }

    /// <summary>
    /// The head is fixed and in this order: timestamp, level, category, trace.
    /// Asserted as ONE regex rather than four substring checks, because the
    /// order and the separators are the whole point - four independent
    /// `Contains` calls pass against a line with the fields in any arrangement.
    /// </summary>
    [Fact]
    public void TheHeadIsTimestampLevelCategoryAndTrace()
    {
        var (factory, writer) = BuildText();
        var logger = factory.CreateLogger("Tankbook.Api.Sync.SyncEndpoints");

        using (logger.BeginScope(new List<KeyValuePair<string, object?>>
        {
            new("TraceId", "01a06427-efe2-735c-bf0c-02cc1f77ed2e"),
        }))
        {
            logger.LogInformation("pulled {Returned} records", 2);
        }

        var line = Assert.Single(writer.Lines);
        Assert.Matches(
            new Regex(@"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| INFORMATION \| "
                    + @"\[Sync\.SyncEndpoints\] \[01a06427-efe2-735c-bf0c-02cc1f77ed2e\] pulled 2 records"),
            line);
    }

    /// <summary>
    /// The category is what the app threw away until 2026-09-03:
    /// `CreateLogger(categoryName)` discarded the name, so no line could say who
    /// wrote it. This asserts a FOREIGN category survives whole - only this
    /// app's own `Tankbook.Api.` prefix is trimmed, because a shortened
    /// framework category is harder to search for, not easier.
    /// </summary>
    [Fact]
    public void AForeignCategoryIsPrintedInFull()
    {
        var (factory, writer) = BuildText();

        factory.CreateLogger("Microsoft.AspNetCore.Hosting.Diagnostics")
            .LogInformation("Request finished");

        Assert.Contains("[Microsoft.AspNetCore.Hosting.Diagnostics]", Assert.Single(writer.Lines));
    }

    /// <summary>
    /// Null correlation fields are DROPPED, not printed as `=null`.
    ///
    /// This is the readability half of the change: every line used to carry
    /// `traceId=null accountHash=null deviceId=null clientVersion=null
    /// clientPlatform=null schemaVersion=null` whether or not it had them - six
    /// dead fields, most of a startup line's width.
    ///
    /// Both halves are asserted together: the nulls are gone AND a field that
    /// has a value is still there. Asserting only the first passes against a
    /// renderer that drops every field.
    /// </summary>
    [Fact]
    public void NullFieldsAreDroppedButRealOnesSurvive()
    {
        var (factory, writer) = BuildText();
        var logger = factory.CreateLogger("Tankbook.Api.Rates.RatesJobService");

        using (logger.BeginScope(new List<KeyValuePair<string, object?>>
        {
            new("AccountHash", "acct_c876a1fa"),
            new("DeviceId", null),
        }))
        {
            logger.LogInformation("published {Published} rates", 23);
        }

        var line = Assert.Single(writer.Lines);
        Assert.DoesNotContain("=null", line, StringComparison.Ordinal);
        Assert.DoesNotContain("deviceId", line, StringComparison.Ordinal);
        Assert.Contains("accountHash=acct_c876a1fa", line, StringComparison.Ordinal);
        Assert.Contains("Published=23", line, StringComparison.Ordinal);
    }

    /// <summary>
    /// The per-process constants stay out of the text line and stay IN the JSON.
    /// Asserting both in one test is deliberate - dropping them from text is
    /// only correct while a collector can still read them, and a test that
    /// checked the text alone would pass against a change that lost them
    /// everywhere.
    /// </summary>
    [Fact]
    public void ConstantsAreDroppedFromTextAndKeptInJson()
    {
        var (factory, textWriter) = BuildText();
        factory.CreateLogger("Tankbook.Api.Health").LogInformation("ready");

        var textLine = Assert.Single(textWriter.Lines);
        Assert.DoesNotContain("serverVersion", textLine, StringComparison.Ordinal);
        Assert.DoesNotContain("platform=server", textLine, StringComparison.Ordinal);

        var jsonWriter = new InMemoryLogWriter([]);
        var jsonFactory = LoggerFactory.Create(builder =>
        {
            builder.ClearProviders();
            builder.SetMinimumLevel(LogLevel.Debug);
            builder.AddProvider(new TankbookLoggerProvider(
                new LogRenderer(new TankbookRedactor("test-salt"), "0.1.0-test", json: true),
                jsonWriter));
        });
        jsonFactory.CreateLogger("Tankbook.Api.Health").LogInformation("ready");

        var jsonLine = Assert.Single(jsonWriter.Lines);
        Assert.Contains("\"serverVersion\":\"0.1.0-test\"", jsonLine, StringComparison.Ordinal);
        Assert.Contains("\"platform\":\"server\"", jsonLine, StringComparison.Ordinal);
    }
}
