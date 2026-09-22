import Foundation

// The pull half of a cycle: every page applied through `applyPull`, in an
// order the server does not guarantee is dependency order (docs/SYNC.md ->
// pull order).
extension SyncEngine {
    func pullAll(tally: SyncCycleTally) async throws -> (pulled: Int, touched: Set<UUID>) {
        var since = try cursorStore.load() ?? 0
        var pulled = 0
        var touched = Set<UUID>()
        // Records whose parent row is not on this device yet. A page is ordered
        // by scn and scn is per record, so a car edited after its entries were
        // logged arrives AFTER them on a from-zero pull; the entry tables'
        // foreign key rejects the child until the parent lands. They are held
        // for the rest of the pull and retried after every page.
        var parked: [SyncPullRecord] = []

        while true {
            let response = try await transport.pull(since: since, limit: pullPageLimit)
            for remote in response.records {
                if let applied = try applyPullOrPark(remote, tally: tally) {
                    touched.formUnion(applied)
                    pulled += 1
                } else {
                    parked.append(remote)
                }
            }
            let landed = try retryParked(&parked, tally: tally)
            touched.formUnion(landed.touched)
            pulled += landed.count
            // Persist the cursor only after the page is applied (cursor safety:
            // a crash before the next page resumes from the applied cursor and
            // re-reads the same page - nothing is skipped). A parked record is
            // not applied, so the cursor waits for the page its parent is on.
            if parked.isEmpty { try cursorStore.save(response.nextSince) }
            if !response.more {
                if !parked.isEmpty {
                    // The parent is on no page of this account: the record is
                    // unapplied on this device and stays on the server. Logged,
                    // never a wedge - a cursor that never advances replays the
                    // same page every cycle and the account never restores.
                    log?.emit(SyncOrphanedRecords(items: parked.map {
                        SyncOrphanedRecord(entityType: $0.entityType, id: $0.id)
                    }))
                    try cursorStore.save(response.nextSince)
                }
                break
            }
            since = response.nextSince
        }
        tally.pulled = pulled
        return (pulled, touched)
    }

    /// `applyPull`, returning nil when the record's parent row is missing so the
    /// caller parks it; every other failure propagates.
    private func applyPullOrPark(_ remote: SyncPullRecord, tally: SyncCycleTally) throws -> Set<UUID>? {
        do {
            return try applyPull(remote, tally: tally)
        } catch let error where TankbookRepository.isMissingParentFailure(error) {
            return nil
        }
    }

    /// Re-applies the parked records until a pass lands none of them. Parked
    /// records can depend on each other (a service item on its record, the
    /// record on its car), so one pass is not enough.
    private func retryParked(_ parked: inout [SyncPullRecord],
                             tally: SyncCycleTally) throws -> (count: Int, touched: Set<UUID>) {
        var count = 0
        var touched = Set<UUID>()
        var progressed = !parked.isEmpty
        while progressed {
            progressed = false
            var still: [SyncPullRecord] = []
            for remote in parked {
                if let applied = try applyPullOrPark(remote, tally: tally) {
                    touched.formUnion(applied)
                    count += 1
                    progressed = true
                } else {
                    still.append(remote)
                }
            }
            parked = still
        }
        return (count, touched)
    }
}
