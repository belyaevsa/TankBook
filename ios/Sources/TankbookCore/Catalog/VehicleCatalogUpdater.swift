import Foundation
import os

/// Why a fetched catalog pack was not applied, as a stable code (docs/ERRORS.md
/// -> Vehicle catalog updates; docs/LOGGING.md hard rule 12: a reason is a
/// code, never content).
public enum CatalogRejectReason: String, Sendable {
    /// The fetch itself failed - offline, a 5xx, a timeout.
    case fetchFailed
    /// The body did not decode to the registered pack shape.
    case malformed
    /// The pack decoded but failed semantic validation.
    case invalid
    /// `packVersion` is not greater than the one held - rollback protection.
    case notNewer
}

/// The client updater for the server-curated vehicle catalog (docs/SYNC.md ->
/// Reference data). Three layers, strict precedence:
///
///     bundled seed < cached pack < server pack
///
/// with overlapping identities **replaced, not merged**, and every failure
/// invisible: the app always has a usable catalog (the bundled seed at
/// minimum), so nothing here ever throws and no user-facing error value exists
/// in this API (docs/ERRORS.md -> Vehicle catalog updates). This task adds no
/// string on purpose - there is no error surface, because there is no next
/// step a user could take.
///
/// A pack is consumed according to its wire `kind` (docs/SYNC.md -> "Applying
/// an update"): a **full** pack replaces the held server set - an entry absent
/// from it was withdrawn by curation and stops being offered - while a
/// **delta** overlays only the entries it mentions and never removes anything.
/// The bundled seed stays layer 1 underneath both, so Add-car suggestions work
/// with no cache and no network (hard rule 1).
///
/// A corrected pack changes what the *next* car pre-fills and never rewrites a
/// car already saved - no `Vehicle` references a catalog entry (docs/SCHEMA.md
/// -> Vehicle catalog). "Server is master" governs the catalog, never the
/// garage.
public final class VehicleCatalogUpdater: @unchecked Sendable {
    public typealias Clock = @Sendable () -> Date

    private struct State {
        /// The validated server-pack entry set held in memory - the cache's
        /// content when one was read at cold start, else empty.
        var serverEntries: [VehicleCatalogEntry]
        /// The pack version the client holds: the seed's when there is no
        /// cache, else the cache's. Sent as `since_version` on the next fetch.
        var heldVersion: Int
        /// "Model not found" tally - a count only, never the typed text
        /// (docs/SYNC.md -> Curation feedback loop, hard rule 12).
        var missCount: Int
        var lastFetchAt: Date?
        var fetchInFlight: Bool
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let bundled: [VehicleCatalogEntry]
    private let cacheDirectory: URL
    private let fetcher: (any VehicleCatalogFetcher)?
    private let clock: Clock
    private let minimumFetchInterval: TimeInterval
    private let log: TankbookLog?

    /// Builds the updater and performs the cold-start read: loads the cache if
    /// present (a truncated or corrupt cache falls back to the seed - never a
    /// crash) and resolves `entries` from what is on disk. Nothing here is
    /// launch-blocking and nothing here needs a network (hard rule 1).
    public init(
        bundled: [VehicleCatalogEntry],
        cacheDirectory: URL,
        fetcher: (any VehicleCatalogFetcher)? = nil,
        clock: @escaping Clock = { Date() },
        minimumFetchInterval: TimeInterval = 3600,
        log: TankbookLog? = nil
    ) {
        self.bundled = bundled
        self.cacheDirectory = cacheDirectory
        self.fetcher = fetcher
        self.clock = clock
        self.minimumFetchInterval = minimumFetchInterval
        self.log = log

        let bundledVersion = bundled.map(\.packVersion).max() ?? 0
        var serverEntries: [VehicleCatalogEntry] = []
        var heldVersion = bundledVersion
        var missCount = 0

        if let record = VehicleCatalogCacheFile.read(directory: cacheDirectory) {
            serverEntries = record.entries
            heldVersion = max(heldVersion, record.packVersion)
            missCount = record.missCount
            log?.emit(CatalogApply(version: record.packVersion, source: .cache,
                                   changedEntries: record.entries.count))
        } else {
            log?.emit(CatalogApply(version: bundledVersion, source: .bundled, changedEntries: 0))
        }

        self.lock = OSAllocatedUnfairLock(initialState: State(
            serverEntries: serverEntries,
            heldVersion: heldVersion,
            missCount: missCount,
            lastFetchAt: nil,
            fetchInFlight: false
        ))
    }

    /// The effective entry list: the bundled seed entries with any validated
    /// cached/server entry of the same identity substituted in place. This
    /// feeds the same `CatalogSuggester` the Add-car screen uses - layers 2 and
    /// 3 live underneath the existing query surface, not beside it.
    public var entries: [VehicleCatalogEntry] {
        let server = lock.withLock { $0.serverEntries }
        return Self.resolved(bundled: bundled, server: server)
    }

    /// The pack version the client holds - sent as `since_version`.
    public var heldPackVersion: Int {
        lock.withLock { $0.heldVersion }
    }

    /// The running "model not found" tally. A count only (docs/SYNC.md ->
    /// Curation feedback loop); the typed text is never captured.
    public var catalogMissCount: Int {
        lock.withLock { $0.missCount }
    }

    /// A single suggestion query over the resolved entries - the same surface
    /// Add-car uses, now backed by all three layers.
    public func suggestions(for query: String, limit: Int = 8) -> [CatalogSuggestion] {
        CatalogSuggester(entries: entries).suggestions(for: query, limit: limit)
    }

    /// Background, throttled, silent refresh (docs/SYNC.md -> "Applying an
    /// update"): fetch the delta since the held version, validate it **whole or
    /// not at all**, apply it by identity and persist. A cold start never calls
    /// this before the suggestion surface is ready, and this call itself never
    /// throws and never produces a user-facing error (docs/ERRORS.md). While a
    /// fetch is in flight a second call is a no-op; a refresh inside
    /// `minimumFetchInterval` of the last one is a no-op.
    public func refresh() async {
        guard let fetcher else { return }
        let now = clock()
        let shouldStart = lock.withLock { state -> Bool in
            if state.fetchInFlight { return false }
            if let last = state.lastFetchAt, now.timeIntervalSince(last) < minimumFetchInterval {
                return false
            }
            state.fetchInFlight = true
            return true
        }
        guard shouldStart else { return }

        defer {
            lock.withLock { state in
                state.fetchInFlight = false
                state.lastFetchAt = clock()
            }
        }

        let since = lock.withLock { $0.heldVersion }
        let pack: VehicleCatalogPack?
        do {
            pack = try await fetcher.fetchPack(sinceVersion: since)
        } catch let error as CatalogFetchError {
            switch error {
            case .transportUnavailable, .badStatus:
                log?.emit(CatalogReject(reason: .fetchFailed))
            case .invalidResponse:
                log?.emit(CatalogReject(reason: .malformed))
            }
            return
        } catch {
            // A test double or future fetcher threw an unknown error: one
            // silent miss, the previous pack stands.
            log?.emit(CatalogReject(reason: .fetchFailed))
            return
        }

        // A nil pack is a 304: the catalog is unchanged. Nothing to do.
        guard let pack else { return }
        apply(pack: pack)
    }

    /// Counts one "model not found" search miss. Only the count is recorded and
    /// logged - the typed text is never captured, at any level, in any build
    /// (docs/SYNC.md -> Curation feedback loop, docs/LOGGING.md hard rule 12).
    /// The tally persists across launches so it can feed the curation roadmap.
    public func recordCatalogMiss() {
        let count = lock.withLock { state -> Int in
            state.missCount += 1
            return state.missCount
        }
        persist(now: clock())
        log?.emit(CatalogMiss(totalCount: count))
    }

    // MARK: - Apply

    private func apply(pack: VehicleCatalogPack) {
        let outcome: ApplyOutcome = lock.withLock { state in
            guard pack.packVersion > state.heldVersion else {
                // Rollback protection - and the equal case is a rollback too:
                // `>=` would keep re-applying the same version on every fetch.
                return .rejected(.notNewer)
            }
            guard Self.validate(pack) else {
                return .rejected(.invalid)
            }
            // The kind decides how the pack is consumed (docs/SYNC.md ->
            // "Applying an update"): a FULL pack IS everything the server
            // publishes, so the held set is REPLACED - an entry absent from it
            // was withdrawn and stops being offered as a suggestion. A DELTA is
            // only what changed, so it is OVERLAID by identity and can never
            // remove an entry the server did not mention. The bundled seed
            // stays layer 1 underneath either way (hard rule 1).
            let server: [VehicleCatalogEntry]
            switch pack.kind {
            case .full:
                server = pack.entries
            case .delta:
                server = Self.resolved(bundled: state.serverEntries, server: pack.entries)
            }
            state.serverEntries = server
            state.heldVersion = pack.packVersion
            return .applied(entries: server)
        }
        switch outcome {
        case .rejected(let reason):
            log?.emit(CatalogReject(reason: reason))
        case .applied:
            persist(now: clock())
            log?.emit(CatalogApply(version: pack.packVersion, source: .live,
                                   changedEntries: pack.entries.count))
        }
    }

    private enum ApplyOutcome {
        case applied(entries: [VehicleCatalogEntry])
        case rejected(CatalogRejectReason)
    }

    // MARK: - Resolution

    /// Entries overridden (by identity) by a higher layer: each `server` entry
    /// with the same `identityKey` as a `bundled` one replaces it in place;
    /// model lines the server adds are appended. Order is deterministic so the
    /// suggestion surface is stable across calls. This is the one function
    /// behind both the cold-start resolution and a fetched pack's application.
    static func resolved(bundled: [VehicleCatalogEntry],
                         server: [VehicleCatalogEntry]) -> [VehicleCatalogEntry] {
        var result = bundled
        var indexByIdentity: [String: Int] = [:]
        for (index, entry) in bundled.enumerated() {
            indexByIdentity[entry.identityKey] = index
        }
        for entry in server {
            if let index = indexByIdentity[entry.identityKey] {
                result[index] = entry
            } else {
                indexByIdentity[entry.identityKey] = result.count
                result.append(entry)
            }
        }
        return result
    }

    /// The semantic "whole or not at all" gate (docs/SYNC.md -> "Validated
    /// before it is applied"). Structural problems already failed at decode;
    /// this checks the decoded pack is a plausible curated catalog: a positive
    /// version and entries with a name, an offer set and sane capacities. A
    /// pack that fails here is rejected entirely - never partially applied -
    /// and the previous cache stands.
    static func validate(_ pack: VehicleCatalogPack) -> Bool {
        guard pack.packVersion > 0 else { return false }
        return pack.entries.allSatisfy { entry in
            !entry.make.isEmpty
                && !entry.model.isEmpty
                && !entry.fuelKinds.isEmpty
                && (entry.tankCapacityL ?? 0) >= 0
                && (entry.batteryCapacityKWh ?? 0) >= 0
        }
    }

    // MARK: - Persistence

    private func persist(now: Date) {
        let record = lock.withLock { state in
            VehicleCatalogCacheRecord(
                packVersion: state.heldVersion,
                entries: state.serverEntries,
                fetchedAt: now,
                missCount: state.missCount
            )
        }
        try? VehicleCatalogCacheFile.write(record, directory: cacheDirectory)
    }
}
