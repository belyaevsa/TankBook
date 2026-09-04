using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Auth;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>
/// PR.8: the log scope carries the client's version, platform, schema version
/// and authenticated identity on every line. Built as in-process units per
/// docs/TESTING.md - trace + enrichment middleware over a DefaultHttpContext,
/// never a full host. The identity is placed in AuthContext.Items directly
/// (the bearer middleware's job in the real pipeline), so no JWT is needed.
/// The assertions read the RENDERED log lines, never the scope dictionary
/// (the vacuous-trap shape the brief warns about).
/// </summary>
public class LogScopeEnrichmentTests
{
    private const string TraceHeader = "X-Tankbook-Trace";
    private const string TestSalt = "test-salt";

    private sealed record Pipeline(RequestDelegate Delegate, IServiceProvider Services, InMemoryLogWriter Writer);

    private static Pipeline BuildPipeline(Action<ApplicationBuilder>? terminal = null)
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var app = new ApplicationBuilder(services);
        app.UseMiddleware<TraceCorrelationMiddleware>();
        app.UseMiddleware<LogScopeEnrichmentMiddleware>();
        if (terminal is null)
        {
            app.Run(ctx => Task.CompletedTask);
        }
        else
        {
            terminal(app);
        }

        return new Pipeline(app.Build(), services, writer);
    }

    private static DefaultHttpContext AuthenticatedContext(
        IServiceProvider services,
        string path,
        string traceId,
        Guid accountId,
        Guid deviceId)
    {
        var context = LoggingTestHelpers.NewContext(services, method: "GET", path: path, traceId: traceId);
        context.Request.Headers[LogScopeEnrichmentMiddleware.AppVersionHeader] = "1.0.0+1";
        context.Request.Headers[LogScopeEnrichmentMiddleware.PlatformHeader] = "ios";
        context.Request.Headers[LogScopeEnrichmentMiddleware.SchemaVersionHeader] = "1";
        context.Items[AuthContext.AccountIdKey] = accountId;
        context.Items[AuthContext.DeviceIdKey] = deviceId;
        LoggingTestHelpers.SetRoute(context, path);
        return context;
    }

    [Fact]
    public async Task RequestLine_CarriesClientVersionAccountHashDeviceIdSchemaVersion_AndServerVersionNotAppVersion()
    {
        var pipeline = BuildPipeline();
        var accountId = Guid.NewGuid();
        var deviceId = Guid.NewGuid();
        var context = AuthenticatedContext(pipeline.Services, "/v1/sync/pull", "7f3a5b1e-cd42-4f09-9a2b-1c2d3e4f5a6b", accountId, deviceId);

        await pipeline.Delegate(context);

        var line = pipeline.Writer.JsonLines().RequestLine("/v1/sync/pull");
        Assert.Equal("1.0.0+1", line.Prop("clientVersion"));
        Assert.Equal("ios", line.Prop("clientPlatform"));
        Assert.Equal("1", line.Prop("schemaVersion"));
        Assert.Equal(deviceId.ToString(), line.Prop("deviceId"));
        Assert.Equal(AccountHash.ForAccount(accountId, TestSalt), line.Prop("accountHash"));
        Assert.Equal("0.1.0-test", line.Prop("serverVersion"));
        Assert.True(line.Prop("appVersion") is null, "the server's own version field was renamed to serverVersion");
        Assert.Equal("7f3a5b1e-cd42-4f09-9a2b-1c2d3e4f5a6b", line.Prop("traceId"));
    }

    [Fact]
    public async Task OperationLine_InsideTheRequest_CarriesTheSameEnrichedFields()
    {
        var pipeline = BuildPipeline(app =>
        {
            app.Run(ctx =>
            {
                var logger = ctx.RequestServices.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("Tankbook.Api.Tests");
                TankbookLog.SyncPull(logger, sinceScn: 0, returned: 3, nextSince: 3, more: false, TimeSpan.FromMilliseconds(12));
                ctx.Response.StatusCode = 200;
                return Task.CompletedTask;
            });
        });
        var accountId = Guid.NewGuid();
        var deviceId = Guid.NewGuid();
        var context = AuthenticatedContext(pipeline.Services, "/v1/sync/pull", "a1b2c3d4-1111-2222-3333-444455556666", accountId, deviceId);

        await pipeline.Delegate(context);

        var line = pipeline.Writer.JsonLines().Single(l => l.Prop("event") == "sync.pull");
        Assert.Equal("1.0.0+1", line.Prop("clientVersion"));
        Assert.Equal("ios", line.Prop("clientPlatform"));
        Assert.Equal(deviceId.ToString(), line.Prop("deviceId"));
        Assert.Equal(AccountHash.ForAccount(accountId, TestSalt), line.Prop("accountHash"));
        Assert.Equal("1", line.Prop("schemaVersion"));
    }

    [Fact]
    public async Task PublicRequest_LeavesAccountHashAndDeviceIdNull_ButKeepsClientVersion()
    {
        var pipeline = BuildPipeline();
        var context = LoggingTestHelpers.NewContext(
            pipeline.Services, path: "/v1/rates/pack", traceId: "b2c3d4e5-2222-3333-4444-555566667777");
        context.Request.Headers[LogScopeEnrichmentMiddleware.AppVersionHeader] = "1.0.0+1";
        LoggingTestHelpers.SetRoute(context, "/v1/rates/pack");

        await pipeline.Delegate(context);

        var line = pipeline.Writer.JsonLines().RequestLine("/v1/rates/pack");
        Assert.Equal("1.0.0+1", line.Prop("clientVersion"));
        Assert.Null(line.Prop("accountHash"));
        Assert.Null(line.Prop("deviceId"));
    }

    [Fact]
    public async Task MissingClientTraceHeader_FallsBackToAUUIDv7()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var app = new ApplicationBuilder(services);
        app.UseMiddleware<TraceCorrelationMiddleware>();
        app.Run(_ => Task.CompletedTask);
        var pipeline = app.Build();

        var context = LoggingTestHelpers.NewContext(services, path: "/health");
        LoggingTestHelpers.SetRoute(context, "/health");

        await pipeline(context);

        var echoed = context.Response.Headers[TraceHeader].ToString();
        Assert.False(string.IsNullOrWhiteSpace(echoed));
        Assert.True(Guid.TryParse(echoed, out _), "the fallback must still be a UUID");
        Assert.True(echoed[14] == '7', "the fallback must be a UUIDv7 (version nibble 7)");
    }

    [Fact]
    public async Task EnrichedScope_NeverLogsTheEmail_AccountHashIsOverTheAccountId()
    {
        var pipeline = BuildPipeline(app =>
        {
            app.Run(ctx =>
            {
                var logger = ctx.RequestServices.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("Tankbook.Api.Tests");
                TankbookLog.AuthSession(logger, "apple", "created", accountHash: "acct_12345678");
                ctx.Response.StatusCode = 200;
                return Task.CompletedTask;
            });
        });
        var accountId = Guid.NewGuid();
        var deviceId = Guid.NewGuid();
        var context = AuthenticatedContext(pipeline.Services, "/v1/sync/pull", "c3d4e5f6-3333-4444-5555-666677778888", accountId, deviceId);
        context.Request.Headers.Remove(LogScopeEnrichmentMiddleware.AppVersionHeader);

        await pipeline.Delegate(context);

        var all = string.Join('\n', pipeline.Writer.Lines);
        Assert.DoesNotContain("someone@example.com", all, StringComparison.Ordinal);
        Assert.DoesNotContain(accountId.ToString(), all, StringComparison.Ordinal);
        Assert.False(all.Contains(accountId.ToString(), StringComparison.Ordinal),
            "the raw account id must never appear - the scope carries its salted hash");
    }

    /// <summary>
    /// RV.63 L1 guard, in-request: when an email reaches the pipeline inside an
    /// authenticated request, its mask lands under the distinct emailHash key
    /// and the correlation accountHash stays the ACCOUNT-ID hash. Before RV.63
    /// the redactor renamed the email to accountHash too, so one line could
    /// carry two values under one key and two lines about one account could not
    /// be joined.
    /// </summary>
    [Fact]
    public async Task EmailInsideAnAuthenticatedRequest_IsMaskedAsEmailHash_WhileAccountHashStaysTheAccountIdHash()
    {
        var pipeline = BuildPipeline(app =>
        {
            app.Run(ctx =>
            {
                var logger = ctx.RequestServices.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("Tankbook.Api.Tests");
                logger.LogInformation("reach {Email}", "driver@example.com");
                ctx.Response.StatusCode = 200;
                return Task.CompletedTask;
            });
        });
        var accountId = Guid.NewGuid();
        var deviceId = Guid.NewGuid();
        var context = AuthenticatedContext(pipeline.Services, "/v1/sync/pull", "d4e5f6a7-4444-5555-6666-777788889999", accountId, deviceId);

        await pipeline.Delegate(context);

        var line = pipeline.Writer.JsonLines().Single(l => l.Prop("event") != "http.request");

        // accountHash is the account-id hash, unchanged by the email on the line.
        Assert.Equal(AccountHash.ForAccount(accountId, TestSalt), line.Prop("accountHash"));
        // The email's mask rides under its own key, with its own value.
        Assert.Equal(AccountHash.ForEmail("driver@example.com", TestSalt), line.Prop("emailHash"));
        // The email value never appears under the account key and never plaintext.
        Assert.NotEqual(AccountHash.ForEmail("driver@example.com", TestSalt), line.Prop("accountHash"));
        var all = string.Join('\n', pipeline.Writer.Lines);
        Assert.DoesNotContain("driver@example.com", all, StringComparison.Ordinal);
    }
}
