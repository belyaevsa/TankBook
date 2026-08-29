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
    /// Fetches the remote config document, sending `If-None-Match` when an etag
    /// is known. Returns nil when the server answered `304` - the held document
    /// stands, and that is **not a failure** (docs/API.md `GET /config`).
    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult?
}

/// Probes `GET /health` against a candidate base URL (docs/CONFIG.md ->
/// "Health gate before adoption"). Injected so the gate is testable with no
/// network; the real prober lands with the sync work.
public protocol HealthProber: Sendable {
    func probe(baseURL: URL) async -> Bool
}

/// The outcome of a request against the active base URL, reported by the
/// networking layer (docs/CONFIG.md -> "Auto-revert on sustained failure").
///
/// The two cases are what draws the line between a broken base URL and a broken
/// server: `.transportFailure` means the host could not be reached at all, which
/// is evidence the base URL is wrong and counts toward auto-revert. `.response`
/// means the host answered, whatever the status, so the base URL is reachable;
/// it resets the failure counter, never increments it.
public enum ConfigTransportOutcome: Sendable, Equatable {
    case transportFailure
    case response(status: Int)
}

/// The config layer's handle that a transport uses to resolve the base URL and
/// report request outcomes, both at request time rather than captured once at
/// construction (docs/CONFIG.md -> "Base URL per operation").
///
/// The two travel as one value on purpose: a transport that reads the base URL
/// per operation but forgets to report (or vice versa) is exactly the PR.3b
/// defect - the guardrails become real code with no caller, or a promoted base
/// URL that nothing observes. Bundling them makes the omission a missing
/// argument, not a silent one.
public struct ConfigTransportDirector: Sendable {
    /// Resolves the current `apiBaseURL` on every call. There is deliberately no
    /// stored `URL` - a transport that holds one has captured it once by
    /// accident, which is the bug this type exists to prevent.
    public let baseURL: @Sendable () -> URL
    /// Reports a request's outcome to `ConfigStore.recordRequestOutcome`
    /// (`.transportFailure` vs `.response(status:)`). This is what feeds the
    /// failure counter and makes auto-revert reachable in the shipping app.
    public let report: @Sendable (ConfigTransportOutcome) async -> Void

    public init(baseURL: @escaping @Sendable () -> URL,
                report: @escaping @Sendable (ConfigTransportOutcome) async -> Void) {
        self.baseURL = baseURL
        self.report = report
    }
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
        var remoteFetchedAt: Date?
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
    /// The minimum interval between automatic (launch/foreground) config fetches
    /// (docs/CONFIG.md -> "Delivery": once per 6 hours). A compiled constant -
    /// deliberately **not** a remote key: `configPollInterval` does not exist in
    /// the document, the seeder or the schema, and adding it spans both tiers
    /// and three bundled copies (that is PR.3c). A user-initiated refresh
    /// bypasses this throttle; a background/foreground one does not.
    static let automaticRefreshInterval: TimeInterval = 6 * 60 * 60

    private let fetcher: (any ConfigFetcher)?
    private let healthProber: (any HealthProber)?
    private let maxConsecutiveFailures: Int
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
        healthProber: (any HealthProber)? = nil,
        maxConsecutiveFailures: Int = 5,
        log: TankbookLog? = nil
    ) {
        self.bundled = bundled
        self.cacheDirectory = cacheDirectory
        self.verifier = verifier
        self.keychain = keychain
        self.clock = clock
        self.deviceIdentifier = deviceIdentifier
        self.fetcher = fetcher
        self.healthProber = healthProber
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.log = log

        let floor = keychain.highestSeenVersion()
        var state = State(
            resolved: bundled,
            remote: nil,
            remoteSignature: "",
            remoteEtag: nil,
            remoteFetchedAt: nil,
            floor: floor,
            consecutiveFailures: 0,
            activeBaseURL: nil
        )

        if let record = ConfigCacheFile.read(directory: cacheDirectory) {
            state.consecutiveFailures = record.consecutiveFailures
            // A tampered cache could name an arbitrary activeBaseURL; drop it if
            // it is not allowlisted, so resolution falls back to the bundled
            // default (docs/CONFIG.md -> "Defence in depth"). The HTTP client
            // re-checks anyway, but the two checkpoints are independent.
            if let active = record.activeBaseURL, Self.isAllowlistedBaseURL(active) {
                state.activeBaseURL = active
            }

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
                           fetchedAt: record.fetchedAt, bundled: bundled, keychain: keychain, debugOverride: nil)
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
        // The pump-photo flag is additionally gated by the build's measured
        // accuracy (P2.7 -> "the gate IS the check"): a remote document may only
        // ever turn it DOWN while the gate fails, never up. The accuracy gate is
        // a property of the build, not a runtime opinion (docs/CONFIG.md ->
        // "Config can never disable a security control").
        if flag == .pumpPhoto, !PumpPhotoGate.allowsPumpPhoto { return false }
        let config = snapshot()
        guard let feature = config.flags[flag.rawValue] else { return false }
        return ConfigRollout.isEnabled(
            feature,
            salt: config.rolloutSalt,
            deviceIdentifier: deviceIdentifier,
            flagName: flag.rawValue
        )
    }

    /// Foreground / nudge / failure-triggered fetch (docs/CONFIG.md ->
    /// "Delivery"). A transport failure fetching config is silent and keeps the
    /// current config; it is not the same thing as a transport failure against
    /// the active base URL, which is reported via `recordRequestOutcome`.
    ///
    /// Automatic refreshes are throttled to `automaticRefreshInterval` from the
    /// cache record's `fetchedAt` (using the injected `clock`, never `Date()`).
    /// A user-initiated refresh bypasses the throttle; the background/foreground
    /// paths do not. A `304` answer (fetcher returns nil) is "no change", not a
    /// failure.
    public func refresh(userInitiated: Bool = false) async {
        guard let fetcher else { return }

        let now = clock()
        if !userInitiated {
            let fetchedAt = lock.withLock { $0.remoteFetchedAt }
            if let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.automaticRefreshInterval {
                return
            }
        }

        let etag = lock.withLock { $0.remoteEtag }
        let result: ConfigFetchResult?
        do {
            result = try await fetcher.fetch(ifNoneMatch: etag)
        } catch {
            return
        }
        guard let result else {
            // 304: the held document stands. Not a change, not a failure.
            return
        }

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
            await apply(document: document, signature: result.signature, etag: result.etag, now: now)
        }
    }

    /// Reports the outcome of a request made against the active base URL
    /// (docs/CONFIG.md -> "Auto-revert on sustained failure"). Called by the
    /// networking layer after each request; the transport/response distinction
    /// lives in `ConfigTransportOutcome`.
    ///
    /// - A `.transportFailure` (host unreachable) increments the persisted
    ///   failure counter; on reaching `maxConsecutiveFailures` the store reverts
    ///   to the bundled default, resets the counter, logs at WARN and re-probes.
    /// - A `.response` (host answered, any status) proves the base URL is
    ///   reachable and resets the counter to 0. A 500 from our own server is
    ///   therefore never evidence that the base URL is wrong.
    public func recordRequestOutcome(_ outcome: ConfigTransportOutcome) async {
        switch outcome {
        case .response:
            let changed = lock.withLock { state -> Bool in
                let changed = state.consecutiveFailures != 0
                state.consecutiveFailures = 0
                return changed
            }
            if changed { persist(now: clock()) }
        case .transportFailure:
            let shouldRevert = lock.withLock { state -> Bool in
                state.consecutiveFailures += 1
                let active = state.activeBaseURL
                let isBundled = active == nil || active == bundled.apiBaseURL.absoluteString
                return state.consecutiveFailures >= maxConsecutiveFailures && !isBundled
            }
            if shouldRevert {
                await revertToBundled()
            } else {
                persist(now: clock())
            }
        }
    }

    /// The currently-active base URL string, or nil when the store is on the
    /// bundled default. Internal for tests (a plain `swift test` needs to
    /// observe the persisted state without a real Keychain).
    var activeBaseURLValue: String? {
        lock.withLock { $0.activeBaseURL }
    }

    /// The current consecutive transport-failure count. Internal for tests.
    var consecutiveFailureCount: Int {
        lock.withLock { $0.consecutiveFailures }
    }

    #if DEBUG
    /// Sets a sparse debug override (DEBUG builds only - compiled out of
    /// Release). It sits above every other layer, matching the precedence in
    /// docs/CONFIG.md, and is applied per key like a remote document.
    public func setDebugOverride(_ override: DebugConfigOverride?) {
        lock.withLock { state in
            debugOverride = override
            state.resolved = Self.resolve(
                bundled: bundled,
                remote: state.remote,
                activeBaseURL: state.activeBaseURL,
                debugOverride: override
            )
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

    // MARK: - Candidate base URL

    /// The health gate and promotion (docs/CONFIG.md -> "Guardrails on
    /// apiBaseUrl"): a document's `apiBaseUrl` is only ever a *candidate*.
    ///
    /// - A candidate that fails the allowlist is rejected at the **key** level:
    ///   the rest of the document applies, the previous base URL stands.
    /// - A candidate that differs from the current URL is probed (`GET /health`)
    ///   before promotion; a failed probe discards it. One probe per refresh.
    /// - With no prober injected (this slice ships no real one) the health gate
    ///   is absent and an allowlisted candidate is promoted directly; auto-revert
    ///   remains the safety net.
    private func apply(document: ConfigDocument, signature: String, etag: String?, now: Date) async {
        let candidate: URL? = document.presentKeyNames.contains("apiBaseUrl") ? document.apiBaseURL : nil

        if let candidate, !HostAllowlist.allows(url: candidate) {
            log?.emit(ConfigReject(reason: .apiBaseURLNotAllowlisted))
            commit(document: document, signature: signature, etag: etag, now: now, activeURL: nil)
            return
        }

        let currentURL = lock.withLock { $0.resolved.apiBaseURL }
        guard let candidate, candidate != currentURL else {
            commit(document: document, signature: signature, etag: etag, now: now, activeURL: nil)
            return
        }

        if let healthProber {
            guard await healthProber.probe(baseURL: candidate) else {
                log?.emit(ConfigReject(reason: .apiBaseURLHealthProbeFailed))
                commit(document: document, signature: signature, etag: etag, now: now, activeURL: nil)
                return
            }
        }
        log?.emit(ConfigBaseURLPromote(host: candidate.host ?? ""))
        commit(document: document, signature: signature, etag: etag, now: now,
               activeURL: candidate.absoluteString)
    }

    /// Stores an already-validated document, optionally promoting a new active
    /// base URL, bumps the rollback floor, re-resolves, persists and logs.
    private func commit(
        document: ConfigDocument,
        signature: String,
        etag: String?,
        now: Date,
        activeURL: String?
    ) {
        let resolved = lock.withLock { state -> AppConfig in
            state.remote = document
            state.remoteSignature = signature
            state.remoteEtag = etag
            state.remoteFetchedAt = now
            if let activeURL {
                state.activeBaseURL = activeURL
                // A new active URL starts a fresh failure streak.
                state.consecutiveFailures = 0
            }
            let previousFloor = state.floor
            let newFloor = max(previousFloor ?? Int.min, document.version)
            if newFloor > (previousFloor ?? Int.min) {
                state.floor = newFloor
                keychain.record(version: newFloor)
            }
            state.resolved = Self.resolve(
                bundled: bundled,
                remote: document,
                activeBaseURL: state.activeBaseURL,
                debugOverride: resolvedOverride()
            )
            return state.resolved
        }
        persist(now: now)
        log?.emit(ConfigApply(
            version: document.version,
            source: .live,
            changedKeys: Self.changedKeyNames(bundled: bundled, resolved: resolved)
        ))
    }

    /// Reverts to the bundled default after N consecutive transport failures
    /// (docs/CONFIG.md -> "Auto-revert on sustained failure"): resets the
    /// counter, logs at WARN, and re-probes the bundled default. The re-probe
    /// result is advisory - the bundled URL is the floor and there is nothing
    /// below it to fall back to.
    private func revertToBundled() async {
        let (abandonedHost, failureCount): (String, Int) = lock.withLock { state in
            let host = state.activeBaseURL.flatMap { URL(string: $0)?.host }
                ?? bundled.apiBaseURL.host ?? ""
            let count = state.consecutiveFailures
            state.activeBaseURL = nil
            state.consecutiveFailures = 0
            state.resolved = Self.resolve(
                bundled: bundled,
                remote: state.remote,
                activeBaseURL: state.activeBaseURL,
                debugOverride: resolvedOverride()
            )
            return (host, count)
        }
        persist(now: clock())
        log?.emit(ConfigBaseURLRevert(host: abandonedHost, failureCount: failureCount))
        if let healthProber {
            _ = await healthProber.probe(baseURL: bundled.apiBaseURL)
        }
    }

    /// Writes the current state to the cache file, but only when a remote
    /// document is held (the cache envelope stores the document verbatim, so
    /// there is nothing to persist on pure-bundled resolution).
    private func persist(now: Date) {
        let record: ConfigCacheRecord? = lock.withLock { state in
            guard let document = state.remote else { return nil }
            return ConfigCacheRecord(
                document: document.rawBytes,
                signature: state.remoteSignature,
                etag: state.remoteEtag,
                fetchedAt: state.remoteFetchedAt ?? now,
                activeBaseURL: state.activeBaseURL,
                consecutiveFailures: state.consecutiveFailures
            )
        }
        guard let record else { return }
        try? ConfigCacheFile.write(record, directory: cacheDirectory)
    }

    private static func isAllowlistedBaseURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return HostAllowlist.allows(url: url)
    }

    // MARK: - Adoption

    /// Applies an already-validated document on the cold-start cache read:
    /// stores it, bumps the rollback floor (persisting to the Keychain), and
    /// re-resolves. `activeBaseURL` is left as the caller set it (already read
    /// from the cache and allowlist-checked).
    private static func adopt(
        _ state: inout State,
        document: ConfigDocument,
        signature: String,
        etag: String?,
        fetchedAt: Date,
        bundled: AppConfig,
        keychain: any ConfigRollbackFloorStoring,
        debugOverride: DebugConfigOverride?
    ) {
        state.remote = document
        state.remoteSignature = signature
        state.remoteEtag = etag
        state.remoteFetchedAt = fetchedAt

        let previousFloor = state.floor
        let newFloor = max(previousFloor ?? Int.min, document.version)
        if newFloor > (previousFloor ?? Int.min) {
            state.floor = newFloor
            keychain.record(version: newFloor)
        }
        state.resolved = resolve(bundled: bundled, remote: document,
                                 activeBaseURL: state.activeBaseURL, debugOverride: debugOverride)
    }

    /// The merge of the three layers: bundled overridden (per key) by a valid
    /// remote document, overridden in turn by a debug override in DEBUG builds.
    /// `apiBaseURL` resolves from the health-gated `activeBaseURL` (or the
    /// bundled default) - never directly from a document's `apiBaseUrl`, which
    /// is only a candidate.
    private static func resolve(
        bundled: AppConfig,
        remote: ConfigDocument?,
        activeBaseURL: String?,
        debugOverride: DebugConfigOverride?
    ) -> AppConfig {
        var base = remote.map { bundled.applying(remote: $0) } ?? bundled
        let activeURL = activeBaseURL.flatMap { URL(string: $0) } ?? bundled.apiBaseURL
        base = base.withAPIBaseURL(activeURL)
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
    public var appUpdate: ConfigDocument.AppUpdateNotice?
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
            appUpdate: appUpdate ?? base.appUpdate,
            rolloutSalt: rolloutSalt ?? base.rolloutSalt,
            flags: flags ?? base.flags,
            version: base.version
        )
    }
}
