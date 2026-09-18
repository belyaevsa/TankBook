import Foundation

// MARK: - The held vocabulary: bundled seed, disk cache, remote refresh

/// The device's copy of the brand pack. Starts from the bundled seed, is
/// replaced by the cache when one holds a newer version, and refreshes from
/// `GET /reference/station-brands` with `since_version` - a full pack replaces,
/// a delta overlays, a version not above the held one is ignored. The matcher
/// reads `current` at station creation; nothing here ever rewrites a saved
/// station (hard rule 13).
public final class StationBrandStore: @unchecked Sendable {
    public static let cacheFileName = "station-brands.cache.json"

    private let lock = NSLock()
    private var pack: StationBrandPack
    private let cacheDirectory: URL?
    private let fetcher: (any StationBrandFetcher)?

    public init(seed: StationBrandPack, cacheDirectory: URL? = nil, fetcher: (any StationBrandFetcher)? = nil) {
        self.cacheDirectory = cacheDirectory
        self.fetcher = fetcher
        var held = seed
        if let cacheDirectory, let cached = Self.readCache(directory: cacheDirectory),
           cached.packVersion > seed.packVersion {
            held = cached
        }
        self.pack = held
    }

    public var current: StationBrandPack {
        lock.withLock { pack }
    }

    public var brands: [StationBrand] { current.brands }

    /// One refresh: asks for what changed above the held version and applies
    /// it. Every failure is silent and leaves the held pack standing - the
    /// vocabulary is a convenience, never a gate (hard rule 1). Returns
    /// whether the held pack changed.
    @discardableResult
    public func refresh() async -> Bool {
        guard let fetcher else { return false }
        let held = current
        guard let served = try? await fetcher.fetchPack(sinceVersion: held.packVersion) else { return false }
        let applied = held.applying(served)
        guard applied != held else { return false }
        lock.withLock { pack = applied }
        if let cacheDirectory { Self.writeCache(applied, directory: cacheDirectory) }
        return true
    }

    /// Test seam: replaces the held pack (a served pack applied through the
    /// same rule the refresh uses).
    public func apply(_ served: StationBrandPack) {
        lock.withLock { pack = pack.applying(served) }
    }

    static func readCache(directory: URL) -> StationBrandPack? {
        let url = directory.appendingPathComponent(cacheFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StationBrandPack.self, from: data)
    }

    static func writeCache(_ pack: StationBrandPack, directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(cacheFileName)
            let data = try JSONEncoder().encode(pack)
            try data.write(to: url, options: [.atomic])
            var resource = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resource.setResourceValues(values)
            FileProtection.protect(url)
        } catch {
            // A cache that fails to write costs one refetch next launch.
        }
    }
}

/// The fetch seam, so the store tests without a network.
public protocol StationBrandFetcher: Sendable {
    /// A pack above `sinceVersion`, or nil when the server answered 304.
    func fetchPack(sinceVersion: Int) async throws -> StationBrandPack?
}

/// The production fetcher (docs/API.md "GET /reference/station-brands"):
/// public, no bearer, `since_version`, ETag-revalidated by the transport.
public struct RemoteStationBrandFetcher: StationBrandFetcher, Sendable {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider)
        self.director = director
    }

    public func fetchPack(sinceVersion: Int) async throws -> StationBrandPack? {
        var components = URLComponents(
            url: director.baseURL().appendingPathComponent("v1/reference/station-brands"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "since_version", value: String(sinceVersion))]
        guard let url = components?.url else { throw CatalogFetchError.invalidResponse }
        let response: TankbookHTTPResponse
        do {
            response = try await client.send(TankbookHTTPRequest(url: url, method: "GET"))
            await director.report(.response(status: response.status))
        } catch TankbookHTTPClientError.httpError(let status, _, _, _, _) {
            await director.report(.response(status: status))
            throw CatalogFetchError.badStatus(status)
        } catch {
            await director.report(.transportFailure)
            throw CatalogFetchError.transportUnavailable
        }
        switch response.status {
        case 304:
            return nil
        case 200...299:
            guard let body = response.body,
                  let pack = try? JSONDecoder().decode(StationBrandPack.self, from: body) else {
                throw CatalogFetchError.invalidResponse
            }
            return pack
        default:
            throw CatalogFetchError.badStatus(response.status)
        }
    }
}
