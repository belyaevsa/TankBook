namespace Tankbook.Api.Config;

/// <summary>The document selected to be served to a device.</summary>
public sealed record ConfigServeResult(int Version, string DocumentJson, string Signature);

/// <summary>
/// The read seam for GET /v1/config (docs/API.md). Public endpoint, no auth:
/// guests and signed-out users need config too (docs/CONFIG.md "Delivery").
/// Mocked at the host boundary in endpoint tests (docs/TESTING.md standing rule).
/// </summary>
public interface IConfigReadService
{
    Task<ConfigServeResult?> GetForServingAsync(CancellationToken cancellationToken);
}
