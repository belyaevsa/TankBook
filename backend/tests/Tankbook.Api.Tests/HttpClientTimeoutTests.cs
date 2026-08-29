using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Tankbook.Api.Http;

namespace Tankbook.Api.Tests;

/// <summary>
/// PR.6 (docs/PRACTICES.md U6): each outbound HTTP role has a named client whose
/// timeout is the compiled value, not the 100 s default. A slow feed must stop
/// pinning a job thread, a slow JWKS must stop stalling every sign-in behind it,
/// and APNs must stop riding the default. The test reads the actual clients the
/// factory builds, so it asserts the wired numbers - not a constant next to a
/// different constant.
/// </summary>
public class HttpClientTimeoutTests
{
    [Fact]
    public void NamedClientsCarryTheConfiguredTimeouts()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseEnvironment("Testing"));

        var httpFactory = factory.Services.GetRequiredService<IHttpClientFactory>();

        Assert.Equal(HttpClientTimeouts.RateFeed, httpFactory.CreateClient("rates").Timeout);
        Assert.Equal(HttpClientTimeouts.Jwks, httpFactory.CreateClient("jwks").Timeout);
        Assert.Equal(HttpClientTimeouts.Apns, httpFactory.CreateClient("apns").Timeout);
    }
}
