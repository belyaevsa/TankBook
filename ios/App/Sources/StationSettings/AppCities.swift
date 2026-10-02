import Foundation
import TankbookCore

/// The app's city dictionary (docs/API.md "GET /reference/cities"): the bundled
/// seed, the disk cache and the public refresh. A screenshot or UI-test launch
/// (`-freezeSyncState`) refreshes nothing, so the bundled dictionary is what
/// the seeds and tests see.
enum AppCities {
    static let store = CityStore(seed: .bundled, cacheDirectory: cacheDirectory(), fetcher: makeFetcher())

    static var dictionary: CityDictionary { store.current }

    static func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-freezeSyncState") { return }
        #endif
        await store.refresh()
    }

    private static func makeFetcher() -> RemoteCityPackFetcher {
        #if DEBUG
        let transport = appTransport(SeededLaunch.transport())
        #else
        let transport = appTransport(URLSessionTransport())
        #endif
        return RemoteCityPackFetcher(director: AppConfigStore.shared.director, transport: transport,
                                     tokenProvider: PublicEndpointTokenProvider())
    }

    private static func cacheDirectory() -> URL {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return FileManager.default.temporaryDirectory }
        return directory.appendingPathComponent("Tankbook", isDirectory: true)
    }
}

/// The endpoint is public (docs/API.md) - no bearer, ever.
private struct PublicEndpointTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}
