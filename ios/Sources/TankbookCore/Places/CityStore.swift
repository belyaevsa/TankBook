import Foundation

/// The device's copy of the city dictionary: the bundled seed, replaced by the
/// cached download when that holds a higher version, refreshed from
/// `GET /reference/cities`. A served pack is kept only when its version is
/// higher. A car's saved home city is its own copy and is never touched by a
/// dictionary change (hard rule 13).
public final class CityStore: @unchecked Sendable {
    public static let cacheFileName = "cities.cache.json"

    private let lock = NSLock()
    private var dictionary: CityDictionary
    private let cacheDirectory: URL?
    private let fetcher: (any CityPackFetcher)?

    public init(seed: CityPack, cacheDirectory: URL? = nil, fetcher: (any CityPackFetcher)? = nil) {
        self.cacheDirectory = cacheDirectory
        self.fetcher = fetcher
        var held = seed
        if let cacheDirectory, let cached = Self.readCache(directory: cacheDirectory), cached.version > seed.version {
            held = cached
        }
        dictionary = CityDictionary(pack: held)
    }

    public var current: CityDictionary {
        lock.withLock { dictionary }
    }

    /// One refresh; every failure is silent and leaves the held pack standing
    /// (hard rule 1). Returns whether the held pack changed.
    @discardableResult
    public func refresh() async -> Bool {
        guard let fetcher else { return false }
        guard let served = try? await fetcher.fetchPack(), served.version > current.pack.version else { return false }
        lock.withLock { dictionary = CityDictionary(pack: served) }
        if let cacheDirectory { Self.writeCache(served, directory: cacheDirectory) }
        return true
    }

    static func readCache(directory: URL) -> CityPack? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(cacheFileName)) else { return nil }
        return try? JSONDecoder().decode(CityPack.self, from: data)
    }

    static func writeCache(_ pack: CityPack, directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(cacheFileName)
            try JSONEncoder().encode(pack).write(to: url, options: [.atomic])
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
public protocol CityPackFetcher: Sendable {
    /// The served pack, or nil when the server answered 304.
    func fetchPack() async throws -> CityPack?
}

/// The production fetcher: public, no bearer, ETag-revalidated by the transport.
public struct RemoteCityPackFetcher: CityPackFetcher, Sendable {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider)
        self.director = director
    }

    public func fetchPack() async throws -> CityPack? {
        let url = director.baseURL().appendingPathComponent("v1/reference/cities")
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
            guard let body = response.body, let pack = try? JSONDecoder().decode(CityPack.self, from: body) else {
                throw CatalogFetchError.invalidResponse
            }
            return pack
        default:
            throw CatalogFetchError.badStatus(response.status)
        }
    }
}
