import Foundation

/// The real health prober, over `TankbookHTTPClient` (docs/CONFIG.md ->
/// "Health gate before adoption"). Probes `GET {base}/health` and returns true
/// only on a 2xx - the gate a newly received `apiBaseUrl` must pass before it
/// is promoted to active. Any transport error or non-2xx is a failed probe.
///
/// The base URL is a parameter rather than a fixed field, because the prober is
/// asked about *candidate* URLs the store is considering adopting, which change
/// from one document to the next.
public struct RemoteHealthProber: HealthProber {
    private let client: TankbookHTTPClient

    public init(client: TankbookHTTPClient) {
        self.client = client
    }

    public func probe(baseURL: URL) async -> Bool {
        // `/health` is unversioned and public (docs/API.md -> "Ops").
        let url = baseURL.appendingPathComponent("health")
        do {
            let response = try await client.send(TankbookHTTPRequest(url: url))
            return (200...299).contains(response.status)
        } catch {
            return false
        }
    }
}
