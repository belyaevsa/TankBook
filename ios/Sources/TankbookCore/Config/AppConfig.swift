import CryptoKit
import Foundation

/// The fully-resolved runtime configuration, consumed by the rest of the app
/// (docs/CONFIG.md -> "How code consumes it").
///
/// A plain value type so a caller can `let config = store.snapshot()` at the
/// start of an operation and use it throughout, immune to a later refresh
/// flipping a switch mid-flight. `Sendable` + `Equatable` so snapshots are cheap
/// to copy and compare.
///
/// Typed fields, never string keys: `config.tier3CloudFallback`, never
/// `config.bool("tier3_cloud_fallback")` - a renamed key is a compile error,
/// and the coverage test asserts every documented remote key maps to a field
/// (docs/CONFIG.md -> "How code consumes it", rule 2).
public struct AppConfig: Sendable, Equatable {
    public let apiBaseURL: URL
    public let tier2OnDeviceLLM: Bool
    public let tier3CloudFallback: Bool
    public let llmQuota: ConfigDocument.LLMQuota
    public let ocrConfidenceThreshold: Double
    public let minSchemaVersion: Int
    public let referencePacks: ConfigDocument.ReferencePacks
    public let maintenance: ConfigDocument.MaintenanceNotice?
    public let appUpdate: ConfigDocument.AppUpdateNotice?
    public let rolloutSalt: String
    public let flags: [String: ConfigDocument.FeatureFlag]

    /// The version of the applied document, for logging (`config.apply`). The
    /// bundled layer's own version when no remote document applied.
    public let version: Int

    /// The derived update requirement (docs/CONFIG.md -> "App version and the
    /// update notice"). One sign computed from the two thresholds - there is
    /// deliberately no `severity` field in the document, because it could
    /// contradict its own thresholds.
    public enum UpdateRequirement: Sendable, Equatable {
        /// Running `>= latestVersion`. Nothing is shown, nothing is withheld.
        case none
        /// Running `>= minSupportedVersion` and `< latestVersion` (**soft**).
        /// A dismissible row in Settings -> About; nothing is withheld.
        case recommended
        /// Running `< minSupportedVersion` (**hard**). Server-backed surfaces
        /// are withheld - never the whole app (hard rule 1: a build that
        /// cannot record a fill-up is broken; one that cannot sync is merely
        /// degraded).
        case required
    }

    public init(
        apiBaseURL: URL,
        tier2OnDeviceLLM: Bool,
        tier3CloudFallback: Bool,
        llmQuota: ConfigDocument.LLMQuota,
        ocrConfidenceThreshold: Double,
        minSchemaVersion: Int,
        referencePacks: ConfigDocument.ReferencePacks,
        maintenance: ConfigDocument.MaintenanceNotice?,
        appUpdate: ConfigDocument.AppUpdateNotice? = nil,
        rolloutSalt: String,
        flags: [String: ConfigDocument.FeatureFlag],
        version: Int
    ) {
        self.apiBaseURL = apiBaseURL
        self.tier2OnDeviceLLM = tier2OnDeviceLLM
        self.tier3CloudFallback = tier3CloudFallback
        self.llmQuota = llmQuota
        self.ocrConfidenceThreshold = ocrConfidenceThreshold
        self.minSchemaVersion = minSchemaVersion
        self.referencePacks = referencePacks
        self.maintenance = maintenance
        self.appUpdate = appUpdate
        self.rolloutSalt = rolloutSalt
        self.flags = flags
        self.version = version
    }

    /// Builds a resolved config from a document plus a guaranteed base URL. The
    /// bundled document always carries `apiBaseUrl`; a remote document may not,
    /// in which case the caller supplies the value that already resolved from a
    /// lower layer.
    init(document: ConfigDocument, apiBaseURL: URL) {
        self.init(
            apiBaseURL: apiBaseURL,
            tier2OnDeviceLLM: document.tier2OnDeviceLLM,
            tier3CloudFallback: document.tier3CloudFallback,
            llmQuota: document.llmQuota,
            ocrConfidenceThreshold: document.ocrConfidenceThreshold,
            minSchemaVersion: document.minSchemaVersion,
            referencePacks: document.referencePacks,
            maintenance: document.maintenance,
            appUpdate: document.appUpdate,
            rolloutSalt: document.rolloutSalt,
            flags: document.flags,
            version: document.version
        )
    }

    /// The derived update requirement for a running build, per the
    /// docs/CONFIG.md table: `>= latestVersion` -> `.none`; `>= minSupportedVersion`
    /// -> `.recommended`; `< minSupportedVersion` -> `.required`. Comparison is
    /// numeric per component (`AppVersion`), never lexicographic.
    ///
    /// **Fails open, never closed**: an absent `appUpdate` key, a threshold in
    /// the document that would not parse, or a running version that will not
    /// parse each resolve `.none`. Failing closed would let one malformed
    /// string withdraw sync from every install at once - the config equivalent
    /// of bricking.
    ///
    /// The running version is **injected** as the raw `CFBundleShortVersionString`;
    /// core never reads `Bundle.main`, so tests construct any version without a
    /// bundle. It arrives unparsed on purpose: parsing it here keeps the
    /// fail-open rule inside the same function as the decision, where the
    /// caller cannot lose it between the bundle and the call.
    public func updateRequirement(runningVersion: String) -> UpdateRequirement {
        guard let appUpdate, let running = AppVersion(runningVersion) else {
            return .none
        }
        if running >= appUpdate.latestVersion { return .none }
        if running >= appUpdate.minSupportedVersion { return .recommended }
        return .required
    }

    /// A copy with a different `apiBaseURL` and every other field unchanged.
    ///
    /// Used by `ConfigStore` when the base URL resolves from the health-gated
    /// `activeBaseURL` (or the bundled default) rather than directly from a
    /// document's `apiBaseUrl`, which is only ever a *candidate*.
    func withAPIBaseURL(_ apiBaseURL: URL) -> AppConfig {
        AppConfig(
            apiBaseURL: apiBaseURL,
            tier2OnDeviceLLM: tier2OnDeviceLLM,
            tier3CloudFallback: tier3CloudFallback,
            llmQuota: llmQuota,
            ocrConfidenceThreshold: ocrConfidenceThreshold,
            minSchemaVersion: minSchemaVersion,
            referencePacks: referencePacks,
            maintenance: maintenance,
            appUpdate: appUpdate,
            rolloutSalt: rolloutSalt,
            flags: flags,
            version: version
        )
    }

    /// Applies a valid remote document as a **sparse, per-key override**
    /// (docs/CONFIG.md -> "How it is resolved").
    ///
    /// Document-level validity (parse, signature, expiry, floor) is decided by
    /// the caller; once a document is valid, only the keys *present in its raw
    /// JSON* override this value. A document that omits `apiBaseUrl`,
    /// `maintenance` or `flags` leaves those exactly as they are here - it does
    /// not blank them. This is why the method inspects `presentKeyNames` rather
    /// than blindly copying the decoded fields.
    func applying(remote: ConfigDocument) -> AppConfig {
        let keys = remote.presentKeyNames
        func value<T>(_ key: String, _ remote: T, _ current: T) -> T {
            keys.contains(key) ? remote : current
        }
        return AppConfig(
            apiBaseURL: value("apiBaseUrl", remote.apiBaseURL ?? apiBaseURL, apiBaseURL),
            tier2OnDeviceLLM: value("tier2OnDeviceLLM", remote.tier2OnDeviceLLM, tier2OnDeviceLLM),
            tier3CloudFallback: value("tier3CloudFallback", remote.tier3CloudFallback, tier3CloudFallback),
            llmQuota: value("llmQuota", remote.llmQuota, llmQuota),
            ocrConfidenceThreshold: value("ocrConfidenceThreshold", remote.ocrConfidenceThreshold, ocrConfidenceThreshold),
            minSchemaVersion: value("minSchemaVersion", remote.minSchemaVersion, minSchemaVersion),
            referencePacks: value("referencePacks", remote.referencePacks, referencePacks),
            maintenance: value("maintenance", remote.maintenance, maintenance),
            appUpdate: value("appUpdate", remote.appUpdate, appUpdate),
            rolloutSalt: value("rolloutSalt", remote.rolloutSalt, rolloutSalt),
            flags: value("flags", remote.flags, flags),
            version: remote.version
        )
    }
}

/// The feature flags the app can gate behind rollout
/// (docs/CONFIG.md -> "What may be configured remotely": `rolloutSalt` +
/// per-flag rollout percentage). The raw value is the flag's key in the
/// document's `flags` map.
public enum ConfigFlag: String, Sendable, CaseIterable {
    /// Pump-photo capture mode (docs/TASKS.md P2.7). Ships off until the
    /// accuracy gate clears, and a remote document can only turn it DOWN while
    /// the gate fails - the gate is `PumpPhotoGate`, a property of the build's
    /// measured accuracy, not a runtime opinion.
    case pumpPhoto
}

/// Where the applied document came from, for the `config.apply` event
/// (docs/CONFIG.md -> "Logging").
public enum ConfigSource: String, Sendable {
    case live
    case cache
    case bundled
}

/// Why a document (or one of its keys) was rejected (docs/CONFIG.md ->
/// "Document level: all or nothing" and "Guardrails on apiBaseUrl"). The raw
/// values are the `reason` field of `config.reject`; they are codes, not domain
/// values (docs/LOGGING.md hard rule 12).
///
/// The first five are document-level rejections (the whole document is refused).
/// The last two are **key-level** rejections of `apiBaseUrl` only: the rest of
/// an otherwise-valid document still applies and the previous base URL stands.
public enum ConfigRejectReason: String, Error, Sendable, CaseIterable {
    case malformedDocument
    case verifierNotConfigured
    case badSignature
    case expired
    case belowFloor
    case apiBaseURLNotAllowlisted
    case apiBaseURLHealthProbeFailed
}

// MARK: - Bundled defaults

/// The layer-1 bundled defaults (docs/CONFIG.md -> "The bootstrap paradox").
public enum ConfigDefaults {
    /// Loads `Config.default.json` and resolves it into an `AppConfig`.
    ///
    /// The bundled layer is **not signed and is never signature-checked**: it is
    /// compiled into the binary, which is the root of trust (docs/CONFIG.md ->
    /// "Threat: the cache file is tampered with"). It is also never
    /// expiry-checked, so it can always serve as the fallback no matter how long
    /// the app has been installed.
    public static func bundledAppConfig() throws -> AppConfig {
        guard let url = Bundle.module.url(forResource: "Config.default", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw ConfigStoreError.bundledUnavailable
        }
        let document = try ConfigDocument.parse(data)
        guard let apiBaseURL = document.apiBaseURL else {
            throw ConfigStoreError.bundledMissingAPIBaseURL
        }
        return AppConfig(document: document, apiBaseURL: apiBaseURL)
    }
}

// MARK: - Rollout

/// Deterministic rollout bucketing for `ConfigStore.isEnabled(_:)`
/// (docs/CONFIG.md -> "rolloutSalt + per-flag rollout percentage"). Pure and
/// stateless so the same salt + device + flag always land in the same bucket.
enum ConfigRollout {
    static func isEnabled(
        _ feature: ConfigDocument.FeatureFlag,
        salt: String,
        deviceIdentifier: String,
        flagName: String
    ) -> Bool {
        guard feature.enabled else { return false }
        if feature.rolloutPercent >= 100 { return true }
        if feature.rolloutPercent <= 0 { return false }
        return bucket(salt: salt, deviceIdentifier: deviceIdentifier, flagName: flagName) < feature.rolloutPercent
    }

    /// A stable value in `0 ..< 100`. SHA-256 over a fixed-length-tagged input,
    /// so two different flags never alias and no per-call randomness is involved.
    static func bucket(salt: String, deviceIdentifier: String, flagName: String) -> Int {
        let input = salt + "|" + deviceIdentifier + "|" + flagName
        let digest = SHA256.hash(data: Data(input.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        return Int(value % 100)
    }
}

extension ConfigDocument {
    /// The top-level key names present in the raw served bytes.
    ///
    /// `ConfigDocument` decodes *all* known fields, so the decoded struct cannot
    /// distinguish "absent" from "present with a default". Sparse override needs
    /// the distinction, so it reads the key set straight from the raw JSON.
    /// Unknown keys are included here and simply ignored during resolution
    /// (docs/CONFIG.md -> "How it is resolved").
    var presentKeyNames: Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: rawBytes) as? [String: Any] else {
            return []
        }
        return Set(object.keys)
    }
}
