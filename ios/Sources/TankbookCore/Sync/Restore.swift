import Foundation

/// The verification stats a completed restore presents (docs/JOURNEYS.md J11 ->
/// "the F7 verification stats before finishing": entries, date range, last
/// odometer - numbers, not a checkmark). Raw facts only; the view composes the
/// localised copy from them. Computed by `RestoreStats.compute` from what
/// actually landed, never from a stored counter (hard rule 2's principle).
public struct RestoreStats: Equatable, Sendable {
    public var carCount: Int
    public var carNames: [String]
    public var entryCount: Int
    public var earliestEntry: Date?
    public var latestEntry: Date?
    /// The most recent odometer reading across all entries, in the entry's
    /// distance unit.
    public var lastOdometerKm: Int?
    /// Whole days between the last odometer's entry date and `now` (0 = today).
    public var lastOdometerDaysAgo: Int?

    public init(
        carCount: Int,
        carNames: [String],
        entryCount: Int,
        earliestEntry: Date?,
        latestEntry: Date?,
        lastOdometerKm: Int?,
        lastOdometerDaysAgo: Int?
    ) {
        self.carCount = carCount
        self.carNames = carNames
        self.entryCount = entryCount
        self.earliestEntry = earliestEntry
        self.latestEntry = latestEntry
        self.lastOdometerKm = lastOdometerKm
        self.lastOdometerDaysAgo = lastOdometerDaysAgo
    }

    /// Reduces a restored repository to the verification numbers (docs/SYNC.md:
    /// stats are a pure function of the entry list - derived, never stored).
    public static func compute(repository: TankbookRepository, now: Date = Date()) throws -> RestoreStats {
        let vehicles = try repository.liveVehicles()
        var entryCount = 0
        var earliest: Date?
        var latest: Date?
        var lastOdometerKm: Int?
        var lastOdometerDate: Date?

        for vehicle in vehicles {
            for entry in try repository.liveEntries(forVehicle: vehicle.id) {
                entryCount += 1
                if earliest == nil || entry.date < earliest! { earliest = entry.date }
                if latest == nil || entry.date > latest! { latest = entry.date }
                guard let odometer = entry.odometer else { continue }
                if let lastDate = lastOdometerDate {
                    if entry.date > lastDate || (entry.date == lastDate && odometer > (lastOdometerKm ?? 0)) {
                        lastOdometerKm = odometer
                        lastOdometerDate = entry.date
                    }
                } else {
                    lastOdometerKm = odometer
                    lastOdometerDate = entry.date
                }
            }
        }

        let daysAgo = lastOdometerDate.map { dayDistance(from: $0, to: now) }
        return RestoreStats(
            carCount: vehicles.count,
            carNames: vehicles.map(\.name),
            entryCount: entryCount,
            earliestEntry: earliest,
            latestEntry: latest,
            lastOdometerKm: lastOdometerKm,
            lastOdometerDaysAgo: daysAgo
        )
    }

    /// Whole calendar days from `from` to `to` (0 = the same day), clamped to
    /// zero - a clock a day behind never reads "yesterday" as negative.
    private static func dayDistance(from: Date, to: Date) -> Int {
        let start = Calendar.current.startOfDay(for: from)
        let end = Calendar.current.startOfDay(for: to)
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }
}

/// What a restore attempt found (docs/JOURNEYS.md F7: the three states a restore
/// resolves to, plus the signed-out case). The view maps each to its honest copy
/// and next step - never a generic "something went wrong".
public enum RestoreOutcome: Equatable, Sendable {
    /// The account had data; the garage is populated with the stats to prove it.
    case restored(RestoreStats)
    /// The pull succeeded and the account is truly empty - the recovery entry
    /// point is shown before the user can log anything (F7's merge-conflict
    /// prevention).
    case empty
    /// The backend is down (or the pull was interrupted before anything landed).
    case unreachable
    /// The device was revoked or the account deleted (410).
    case deviceRevoked
}

/// Restore = `SyncEngine` pulling from cursor 0 (docs/SYNC.md, docs/API.md ->
/// "fetching the latest data IS pulling from 0"). There is no separate restore
/// protocol: this type runs the one sync cycle and reduces its outcome to the
/// three F7 states. Text records land first and the garage is usable in
/// seconds; photos never block (blobs are P4.6's lazy path, untouched here).
public struct RestoreEngine {
    public let engine: SyncEngine

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    public func restore(now: Date = Date()) async -> RestoreOutcome {
        let outcome = await engine.synchronize()
        if outcome.deviceRevoked { return .deviceRevoked }

        let stats = try? RestoreStats.compute(repository: engine.repository, now: now)

        if outcome.transportUnavailable {
            // A prior pull already landed data (an interrupted restore being
            // resumed) - that data is usable and must be shown, not hidden
            // behind an unreachable banner.
            if let stats, stats.carCount > 0 { return .restored(stats) }
            return .unreachable
        }

        guard let stats else { return .unreachable }
        if stats.carCount == 0 { return .empty }
        return .restored(stats)
    }
}

/// A content hash of a repository's record stream - the "hash-equals-origin"
/// verification (docs/TESTING.md L3, docs/PHASES.md -> restore-from-zero
/// hash-equals origin dataset). Two devices hold the same data iff their records
/// hash equal here: a count cannot see a silently dropped field, a hash can.
public enum RestoreHash {
    /// Hashes the record stream. Order-independent (records are sorted), and
    /// over the domain payload only - device-local sync bookkeeping
    /// (`syncState`/`syncScn`, and the in-transit `fieldVersions` key) never
    /// appears, because both come from `PayloadCodec.encode(entity)`, which
    /// round-trips the entity itself.
    public static func compute(_ records: [SyncRecord]) -> String {
        let lines = records.map { record -> String in
            let payload = (try? record.payload.jsonString()) ?? "null"
            return [record.entityType, record.id.uuidString,
                    record.deleted ? "1" : "0", payload].joined(separator: "\u{1F}")
        }.sorted()
        return BlobHash.sha256(Data(lines.joined(separator: "\u{1E}").utf8))
    }
}
