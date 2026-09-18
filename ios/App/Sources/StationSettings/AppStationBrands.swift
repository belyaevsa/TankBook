import Foundation
import TankbookCore

/// The app's station brand vocabulary (RV.115, docs/API.md "GET
/// /reference/station-brands"): the bundled seed, the disk cache and the
/// public since_version refresh. The store installs itself into
/// `StationBrandRegistry` when first built - the launch pass's refresh builds
/// it - so the ONE station-creation seam (`ImportStationResolver`) matches
/// against the cached pack; until then the registry serves the bundled seed,
/// which is the same vocabulary minus any correction served since. A
/// screenshot or UI-test launch (`-freezeSyncState`) refreshes nothing, so
/// the bundled vocabulary is what the seeds match against.
enum AppStationBrands {
    static let store: StationBrandStore = {
        let seed = (try? StationBrandSeed.bundledPack()) ?? StationBrandPack(packVersion: 0, brands: [])
        let store = StationBrandStore(seed: seed, cacheDirectory: cacheDirectory(), fetcher: makeFetcher())
        StationBrandRegistry.install(store)
        return store
    }()

    static func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-freezeSyncState") { return }
        #endif
        await store.refresh()
    }

    private static func makeFetcher() -> RemoteStationBrandFetcher {
        RemoteStationBrandFetcher(director: AppConfigStore.shared.director,
                                  transport: makeTransport(),
                                  tokenProvider: NoTokenProvider())
    }

    private static func makeTransport() -> any TankbookHTTPTransport {
        #if DEBUG
        return appTransport(SeededLaunch.transport())
        #else
        return appTransport(URLSessionTransport())
        #endif
    }

    private static func cacheDirectory() -> URL {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return FileManager.default.temporaryDirectory }
        return directory.appendingPathComponent("Tankbook", isDirectory: true)
    }
}

/// The endpoint is public (docs/API.md) - no bearer, ever.
private struct NoTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}
