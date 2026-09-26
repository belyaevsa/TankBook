using Microsoft.AspNetCore.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests.Logging;

/// <summary>
/// A client that hangs up mid-upload: the request line records 499, not the
/// 400 the binder set after it left, and Kestrel's "Reading is already in
/// progress" line - what the framework itself logs for that socket close - is
/// not rendered as a server fault. Reproduced on a live Kestrel with a half-sent
/// body before these were written; the in-memory test host cannot close a socket.
/// </summary>
public class ClientAbortTests
{
    private static DefaultHttpContext Context(int status, bool aborted)
    {
        var context = new DefaultHttpContext();
        context.Response.StatusCode = status;
        if (aborted)
        {
            using var source = new CancellationTokenSource();
            source.Cancel();
            context.RequestAborted = source.Token;
        }

        return context;
    }

    [Theory]
    [InlineData(400, true, 499)]
    [InlineData(200, true, 499)]
    [InlineData(400, false, 400)]
    [InlineData(500, true, 500)]
    [InlineData(502, false, 502)]
    public void TheRequestLineRecordsAClientThatLeftAs499(int status, bool aborted, int logged)
        => Assert.Equal(logged, TraceCorrelationMiddleware.LoggedStatus(Context(status, aborted)));

    [Fact]
    public void KestrelsAbortedReadLineIsDropped_AndNothingElseIs()
    {
        const string kestrel = "Microsoft.AspNetCore.Server.Kestrel";
        Assert.True(TankbookLoggerProvider.IsClientAbortNoise(
            kestrel, new InvalidOperationException("Reading is already in progress.")));
        Assert.False(TankbookLoggerProvider.IsClientAbortNoise(
            kestrel, new InvalidOperationException("Something else went wrong.")));
        Assert.False(TankbookLoggerProvider.IsClientAbortNoise(
            kestrel, new IOException("Reading is already in progress.")));
        Assert.False(TankbookLoggerProvider.IsClientAbortNoise(
            "Tankbook.Api", new InvalidOperationException("Reading is already in progress.")));
        Assert.False(TankbookLoggerProvider.IsClientAbortNoise(kestrel, null));
    }
}
