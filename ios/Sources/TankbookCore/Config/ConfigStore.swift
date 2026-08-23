import Foundation
import os

/// Errors surfaced by `ConfigStore` when a required layer cannot be assembled.
public enum ConfigStoreError: Error, Sendable {
    case bundledUnavailable
    case bundledMissingAPIBaseURL
}

/// A single fetch of the remote config document (docs/CONFIG.md -> "Delivery").
///
/// `document` is the served bytes verbatim; `signature` is the Ed25519
/// signature over their canonical form. P0.12b supplies only a test double for
/// the fetcher; the real HTTP client, the health gate and auto-revert land in
/// P0.12c.
public struct ConfigFetchResult: Sendable, Equatable {
    public let document: Data
    public let signature: String
    public let etag: String?

    public init(document: Data, signature: String, etag: String?) {
        self.document = document
        self.signature = signature
        self.etag = etag
    }
}

public protocol ConfigFetcher: Sendable {
    func fetch() async throws -> ConfigFetchResult
}

/// Resolves the three-layer config precedence (docs/CONFIG.md):
///
///     Debug override (DEBUG only) > Remote (live, else cached) > Bundled
///
/// Two rules operate at two levels and are kept separate on purpose:
///
/// - **Document level, all or nothing**: a remote document that is malformed,
///   unsigned, badly signed, expired, or below the Keychain floor is rejected
///   *entirely* and the layer beneath is used.
/// - **Key level, sparse override**: once a document is valid, each key it
///   *contains* overrides the layer beneath per key; absent keys fall through.
///
/// The store is injected, not a singleton: cache directory, clock, verifier and
/// Keychain are all passed in so tests construct one over fabricated layers.
/// A hard-coded `Date()` would be a defect - expiry and floor tests need a
/// controllable clock - so the clock is a closure.
public final class ConfigStore: @unchecked Sendable {
    public typealias Clock = @Sendable () -> Date

    private struct State {
        var resolved: AppConfig
        var remote: ConfigDocument?
        var remoteSignature: String
        var remoteEtag: String?
        var floor: Int?
        var consecutiveFailures: Int
        var activeBaseURL: String?
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let bundled: AppConfig
    private let cacheDirectory: URL
    private let verifier: ConfigSignatureVerifier
    private let keychain: any ConfigRollbackFloorStoring
    private let clock: Clock
    private let deviceIdentifier: String
    private let fetcher: (any ConfigFetcher)?
    private let log: TankbookLog?

    #if DEBUG
    private var debugOverride: DebugConfigOverride?
    #endif

    /// Creates the store and performs the cold-start read: loads the Keychain
    /// floor, reads and verifies the cache, and resolves `current`.
    public init(
        bundled: AppConfig,
        cacheDirectory: URL,
        verifier: ConfigSignatureVerifier,
        keychain: any ConfigRollbackFloorStoring,
        clock: @escaping Clock,
        deviceIdentifier: String,
        fetcher: (any ConfigFetcher)? = nil,
        log: TankbookLog? = nil
    ) {
        self.bundled = bundled
        self.cacheDirectory = cacheDirectory
        self.verifier = verifier
        self.keychain = keychain
        self.clock = clock
        self.deviceIdentifier = deviceIdentifier
        self.fetcher = fetcher
        self.log = log

        let floor = keychain.highestSeenVersion()
        var state = State(
            resolved: bundled,
            remote: nil,
            remoteSignature: "",
            remoteEtag: nil,
            floor: floor,
            consecutiveFailures: 0,
            activeBaseURL: nil
        )

        if let record = ConfigCacheFile.read(directory: cacheDirectory) {
            state.consecutiveFailures = record.consecutiveFailures
            state.activeBaseURL = record.activeBaseURL

            let validation = Self.validate(
                document: record.document,
                signature: record.signature,
                verifier: verifier,
                floor: floor,
                now: clock()
            )
            switch validation {
            case .success(let document):
                Self.adopt(&state, document: document, signature: record.signature, etag: record.etag,
                           bundled: bundled, keychain: keychain, debugOverride: nil)
                log?.emit(ConfigApply(
                    version: document.version,
                    source: .cache,
                    changedKeys: Self.changedKeyNames(bundled: bundled, resolved: state.resolved)
                ))
            case .failure(let reason):
                log?.emit(ConfigReject(reason: reason))
                log?.emit(ConfigApply(version: bundled.version, source: .bundled, changedKeys: []))
            }
        } else {
            log?.emit(ConfigApply(version: bundled.version, source: .bundled, changedKeys: []))
        }

        self.lock = OSAllocatedUnfairLock(initialState: state)
    }

    /// The currently-resolved config, driving SwiftUI.
    public var current: AppConfig {
        lock.withLock { $0.resolved }
    }

    /// Takes a snapshot once, for use throughout an operation (docs/CONFIG.md ->
    /// "How code consumes it", rule 1). A snapshot taken before a refresh is
    /// unaffected by that refresh.
    public func snapshot() -> AppConfig {
        lock.withLock { $0.resolved }
    }

    /// Whether a feature flag is enabled for this device, applying the flag's
    /// rollout percentage via `rolloutSalt` + a stable device hash
    /// (docs/CONFIG.md -> "rolloutSalt + per-flag rollout percentage").
    public func isEnabled(_ flag: ConfigFlag) -> Bool {
        let config = snapshot()
        guard let feature = config.flags[flag.rawValue] else { return false }
        return ConfigRollout.isEnabled(
            feature,
            salt: config.rolloutSalt,
            deviceIdentifier: deviceIdentifier,
            flagName: flag.rawValue
        )
    }

    /// Foreground / nudge / failure-triggered fetch. With no injected fetcher
    /// (this slice ships only a test double) it is a no-op; P0.12c wires the
    /// real HTTP client and the transport-failure accounting.
    public func refresh() async {
        guard let fetcher else { return }
        let result: ConfigFetchResult
        do {
            result = try await fetcher.fetch()
        } catch {
            // Transport failure is silent and keeps the current config
            // (docs/CONFIG.md -> "Failure behaviour"). P0.12c accounts
            // consecutive failures and auto-reverts.
            return
        }

        let now = clock()
        let floor = lock.withLock { $0.floor }
        let validation = Self.validate(
            document: result.document,
            signature: result.signature,
            verifier: verifier,
            floor: floor,
            now: now
        )
        switch validation {
        case .failure(let reason):
            log?.emit(ConfigReject(reason: reason))
        case .success(let document):
            let resolved = lock.withLock { state -> AppConfig in
                Self.adopt(&state, document: document, signature: result.signature, etag: result.etag,
                           bundled: bundled, keychain: keychain, debugOverride: resolvedOverride())
                let record = ConfigCacheRecord(
                    document: document.rawBytes,
                    signature: result.signature,
                    etag: result.etag,
                    fetchedAt: now,
                    activeBaseURL: state.activeBaseURL,
                    consecutiveFailures: state.consecutiveFailures
                )
                try? ConfigCacheFile.write(record, directory: cacheDirectory)
                return state.resolved
            }
            log?.emit(ConfigApply(
                version: document.version,
                source: .live,
                changedKeys: Self.changedKeyNames(bundled: bundled, resolved: resolved)
            ))
        }
    }

    #if DEBUG
    /// Sets a sparse debug override (DEBUG builds only - compiled out of
    /// Release). It sits above every other layer, matching the precedence in
    /// docs/CONFIG.md, and is applied per key like a remote document.
    public func setDebugOverride(_ override: DebugConfigOverride?) {
        lock.withLock { state in
            debugOverride = override
            state.resolved = Self.resolve(bundled: bundled, remote: state.remote, debugOverride: override)
        }
    }
    #endif

    private func resolvedOverride() -> DebugConfigOverride? {
        #if DEBUG
        return debugOverride
        #else
        return nil
        #endif
    }

    // MARK: - Adoption

    /// Applies an already-validated document: stores it, bumps the rollback
    /// floor (persisting to the Keychain), and re-resolves. Called on both the
    /// cold-start cache read and a successful fetch.
    private static func adopt(
        _ state: inout State,
        document: ConfigDocument,
        signature: String,
        etag: String?,
        bundled: AppConfig,
        keychain: any ConfigRollbackFloorStoring,
        debugOverride: DebugConfigOverride?
    ) {
        state.remote = document
        state.remoteSignature = signature
        state.remoteEtag = etag

        let previousFloor = state.floor
        let newFloor = max(previousFloor ?? Int.min, document.version)
        if newFloor > (previousFloor ?? Int.min) {
            state.floor = newFloor
            keychain.record(version: newFloor)
        }
        state.resolved = resolve(bundled: bundled, remote: document, debugOverride: debugOverride)
    }

    /// The merge of the three layers: bundled overridden (per key) by a valid
    /// remote document, overridden in turn by a debug override in DEBUG builds.
    private static func resolve(
        bundled: AppConfig,
        remote: ConfigDocument?,
        debugOverride: DebugConfigOverride?
    ) -> AppConfig {
        let base = remote.map { bundled.applying(remote: $0) } ?? bundled
        return debugOverride.map { $0.applying(to: base) } ?? base
    }

    // MARK: - Validation

    /// The document-level "all or nothing" gate (docs/CONFIG.md). Order is
    /// deliberate: parse first (cheap structural reject), then signature, then
    /// expiry, then floor. Signature verification runs here on **every** load
    /// from cache - not only on fetch - which is the whole tampering defence.
    private static func validate(
        document: Data,
        signature: String,
        verifier: ConfigSignatureVerifier,
        floor: Int?,
        now: Date
    ) -> Result<ConfigDocument, ConfigRejectReason> {
        guard let parsed = try? ConfigDocument.parse(document) else {
            return .failure(.malformedDocument)
        }
        guard verifier.isConfigured else {
            return .failure(.verifierNotConfigured)
        }
        guard verifier.isValid(signatureBase64: signature, documentBytes: document) else {
            return .failure(.badSignature)
        }
        guard now <= parsed.notAfter else {
            return .failure(.expired)
        }
        if let floor, parsed.version < floor {
            return .failure(.belowFloor)
        }
        return .success(parsed)
    }

    /// Field names (never values - docs/LOGGING.md hard rule 12) that changed
    /// between the bundled base and a resolved config, for `config.apply`.
    static func changedKeyNames(bundled: AppConfig, resolved: AppConfig) -> [String] {
        var keys: [String] = []
        if bundled.apiBaseURL != resolved.apiBaseURL { keys.append("apiBaseUrl") }
        if bundled.tier2OnDeviceLLM != resolved.tier2OnDeviceLLM { keys.append("tier2OnDeviceLLM") }
        if bundled.tier3CloudFallback != resolved.tier3CloudFallback { keys.append("tier3CloudFallback") }
        if bundled.llmQuota != resolved.llmQuota { keys.append("llmQuota") }
        if bundled.ocrConfidenceThreshold != resolved.ocrConfidenceThreshold { keys.append("ocrConfidenceThreshold") }
        if bundled.minSchemaVersion != resolved.minSchemaVersion { keys.append("minSchemaVersion") }
        if bundled.referencePacks != resolved.referencePacks { keys.append("referencePacks") }
        if bundled.maintenance != resolved.maintenance { keys.append("maintenance") }
        if bundled.rolloutSalt != resolved.rolloutSalt { keys.append("rolloutSalt") }
        if bundled.flags != resolved.flags { keys.append("flags") }
        return keys
    }
}

/// A developer-set sparse override (DEBUG builds only). Each non-nil field
/// overrides the resolved config; nil fields leave the lower layer untouched.
/// Only the store's stored property and setter are compiled out of Release;
/// the type itself carries no Release behaviour.
public struct DebugConfigOverride: Sendable, Equatable {
    public var apiBaseURL: URL?
    public var tier2OnDeviceLLM: Bool?
    public var tier3CloudFallback: Bool?
    public var llmQuota: ConfigDocument.LLMQuota?
    public var ocrConfidenceThreshold: Double?
    public var minSchemaVersion: Int?
    public var referencePacks: ConfigDocument.ReferencePacks?
    public var maintenance: ConfigDocument.MaintenanceNotice?
    public var rolloutSalt: String?
    public var flags: [String: ConfigDocument.FeatureFlag]?

    public init() {}

    func applying(to base: AppConfig) -> AppConfig {
        AppConfig(
            apiBaseURL: apiBaseURL ?? base.apiBaseURL,
            tier2OnDeviceLLM: tier2OnDeviceLLM ?? base.tier2OnDeviceLLM,
            tier3CloudFallback: tier3CloudFallback ?? base.tier3CloudFallback,
            llmQuota: llmQuota ?? base.llmQuota,
            ocrConfidenceThreshold: ocrConfidenceThreshold ?? base.ocrConfidenceThreshold,
            minSchemaVersion: minSchemaVersion ?? base.minSchemaVersion,
            referencePacks: referencePacks ?? base.referencePacks,
            maintenance: maintenance ?? base.maintenance,
            rolloutSalt: rolloutSalt ?? base.rolloutSalt,
            flags: flags ?? base.flags,
            version: base.version
        )
    }
}
