import Foundation
import Observation
import os
import TankbookCore

/// The app's one config service (P6.18b, docs/CONFIG.md -> "App version and
/// the update notice" + "Delivery"). Owns the core `ConfigStore` and exposes
/// the derived update requirement to the surface.
///
/// **The load-bearing rule, pinned by tests** (`ConfigUpdateSurfaceTests`): the
/// requirement is derived from the **held snapshot** the store resolved at cold
/// start (live, else cache, else bundled) - **never** from a fetch in flight.
/// `refresh()` runs at launch and on foreground, but nothing the UI draws ever
/// waits on it: `requirement` is a synchronous read of the snapshot the store
/// already holds, so a cold start with a cached document shows the notice
/// instantly and a first launch offline shows nothing at all.
///
/// The running version is **injected**, never read from `Bundle.main` in core:
/// the app reads `CFBundleShortVersionString` and passes it in, and a
/// DEBUG/test launch argument can pin a parseable value. An unparseable
/// running version fails open to `.none` (logged at WARN) - the fail-open rule
/// is pinned by the core decision function and is not re-decided here.
@MainActor
@Observable
final class AppConfigService {
    /// The running build's dotted version. DEBUG/test only: `-configRunningVersion`
    /// pins a parseable value (the shipped bundle version must be three dotted
    /// numerics for the requirement ever to be derivable - see the note in
    /// `docs/CONFIG.md`); production always uses `CFBundleShortVersionString`.
    let runningVersion: String

    /// The App Store destination behind the update button. **Empty today** -
    /// there is no App Store listing and no app id yet, so no "Update in the
    /// App Store" affordance renders anywhere. The button appears only when
    /// this holds a value, the same shape as the marketing site's
    /// `apple-itunes-app` gate (`docs/CONFIG.md` -> "The App Store link
    /// problem"). DEBUG/test only: `-configAppStoreID` makes the button's
    /// presence testable before a real id exists.
    let appStoreURL: URL?

    /// The resolved config the surface reads. `@Observable`-tracked so a
    /// foreground refresh that changes the snapshot re-renders the UI; the
    /// requirement below is derived from THIS snapshot, never from a fetch
    /// result held separately.
    private(set) var config: AppConfig

    private let store: ConfigStore

    private static let log = Logger(subsystem: "app.tankbook", category: "config")

    init(store: ConfigStore, runningVersion: String, appStoreURL: URL?) {
        self.store = store
        self.runningVersion = runningVersion
        self.appStoreURL = appStoreURL
        #if DEBUG
        AppConfigTestSeed.seedIfRequested(store: store)
        #endif
        self.config = store.current
        if AppVersion(runningVersion) == nil {
            // docs/CONFIG.md: an unparseable running version fails OPEN to
            // `.none`. Field name only, never the value (docs/LOGGING.md hard
            // rule 12).
            Self.log.error("config.updateRequirement: running version string does not parse - resolving .none")
        }
    }

    /// Builds the app's one service over the real store: bundled defaults, the
    /// config cache directory, the (DEBUG-provisioned) signature key, the
    /// Keychain rollback floor, a per-install device id, and the live fetcher +
    /// health prober (PR.3a). The surface reads the held snapshot regardless -
    /// no screen ever waits on a fetch (hard rule 1).
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppConfigService {
        let bundled = (try? ConfigDefaults.bundledAppConfig()) ?? fallbackBundled()

        // Config and health are public endpoints (docs/API.md), so the client
        // needs no token: a nil provider means `TankbookHTTPClient` never builds
        // an Authorization header for them.
        let client = TankbookHTTPClient(
            transport: URLSessionTransport(),
            tokenProvider: NoConfigTokenProvider()
        )

        // The fetcher reads the resolved base URL at fetch time, so it follows
        // an `apiBaseUrl` migration instead of pinning the one baked in at
        // launch. A box breaks the store<->fetcher construction cycle: the
        // closure captures the box (a Sendable reference), and the box's `store`
        // is assigned before `make()` returns - no refresh runs until the
        // service exists, so the closure never reads it unset.
        let box = ConfigStoreBox()
        let fetcher = RemoteConfigFetcher(client: client) {
            box.store?.current.apiBaseURL ?? bundled.apiBaseURL
        }
        let prober = RemoteHealthProber(client: client)
        let store = ConfigStore(
            bundled: bundled,
            cacheDirectory: cacheDirectory(),
            verifier: ConfigSignatureVerifier(publicKeyBase64: ConfigSigningKey.bundledPublicKeyBase64),
            keychain: KeychainConfigRollbackFloor(),
            clock: { Date() },
            deviceIdentifier: deviceIdentifier(),
            fetcher: fetcher,
            healthProber: prober
        )
        box.store = store
        return AppConfigService(
            store: store,
            runningVersion: runningVersion(arguments),
            appStoreURL: appStoreURL(arguments)
        )
    }

    /// The requirement for THIS build, from the held snapshot. A synchronous
    /// read - never an await, never a fetch result.
    var requirement: AppConfig.UpdateRequirement {
        config.updateRequirement(runningVersion: runningVersion)
    }

    /// Whether server-backed surfaces (sync, cloud extract, import parse) may
    /// talk to the server. Under `.required` they are withheld; everything
    /// local - logging, editing, recompute, export - is untouched (hard rule 1).
    var allowsServerBacked: Bool { requirement != .required }

    /// Foreground / launch refresh. The requirement is re-derived from the
    /// snapshot this updates; a fetch in flight never changes what the UI
    /// draws (pinned by `ConfigUpdateSurfaceTests`).
    func refresh() async {
        await store.refresh()
        config = store.current
    }

    // MARK: - Construction details

    /// A mutable holder for the store, so the fetcher's `@Sendable` base-URL
    /// closure can read the resolved `apiBaseURL` at fetch time without
    /// capturing a `var` (which `@Sendable` forbids). Written once in `make()`
    /// before any refresh can run; read only from `refresh()` thereafter.
    private final class ConfigStoreBox: @unchecked Sendable {
        var store: ConfigStore?
    }

    /// A token provider that supplies no token, for the public config + health
    /// endpoints (docs/API.md). `TankbookHTTPClient` still enforces the
    /// allowlist on every request; it just never builds an `Authorization`
    /// header for these.
    private struct NoConfigTokenProvider: AuthorizationTokenProvider {
        func token() -> String? { nil }
    }

    /// The store's cold-start cache directory (docs/CONFIG.md -> "Where it is
    /// stored"): `Application Support/Tankbook`, the same directory the
    /// database lives in.
    private static func cacheDirectory() -> URL {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return FileManager.default.temporaryDirectory }
        return directory.appendingPathComponent("Tankbook", isDirectory: true)
    }

    /// A stable per-install device identifier for config rollout bucketing
    /// (docs/CONFIG.md -> "rolloutSalt + per-flag rollout percentage"). Not a
    /// secret and not synced - plain `UserDefaults`, matching the import
    /// device-id pattern.
    private static func deviceIdentifier() -> String {
        let key = "tankbook.config.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private static func runningVersion(_ arguments: [String]) -> String {
        #if DEBUG
        if let index = arguments.firstIndex(of: "-configRunningVersion"),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func appStoreURL(_ arguments: [String]) -> URL? {
        let appID: String
        #if DEBUG
        if let index = arguments.firstIndex(of: "-configAppStoreID"),
           arguments.indices.contains(index + 1) {
            appID = arguments[index + 1]
        } else {
            appID = compiledAppStoreID
        }
        #else
        appID = compiledAppStoreID
        #endif
        guard !appID.isEmpty, appID.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)")
    }

    /// The compiled-in App Store app id. **Empty today**: no listing exists
    /// yet, so no update affordance renders until an id lands here (or in the
    /// DEBUG launch argument above). This is the only value the store link
    /// gates on - no placeholder URL, no dead button (docs/CONFIG.md).
    private static let compiledAppStoreID = ""

    /// A minimal bundled config for the case the bundled JSON cannot be read -
    /// which must never happen in practice (the bundled layer is the bootstrap
    /// floor). The nested quota/pack types only expose their `Decodable` init,
    /// so they are decoded from literals rather than hand-rolled; a literal
    /// that fails to decode can only mean a code bug, so it is a hard failure.
    private static func fallbackBundled() -> AppConfig {
        func decode<T: Decodable>(_ json: String) -> T {
            guard let value = try? JSONDecoder().decode(T.self, from: Data(json.utf8)) else {
                fatalError("config: bundled fallback payload is invalid - the app cannot boot")
            }
            return value
        }
        return AppConfig(
            apiBaseURL: URL(string: "https://api.tankbook.live")!,
            tier2OnDeviceLLM: true,
            tier3CloudFallback: true,
            llmQuota: decode("{\"onDeviceLLM\":200,\"cloudFallback\":50}"),
            ocrConfidenceThreshold: 0.75,
            minSchemaVersion: 1,
            referencePacks: decode("{\"rates\":1,\"catalog\":1}"),
            maintenance: nil,
            appUpdate: nil,
            rolloutSalt: "bundled-fallback",
            flags: [:],
            version: 0
        )
    }
}
