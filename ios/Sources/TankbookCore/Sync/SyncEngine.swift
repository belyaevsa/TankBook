import Foundation

/// The result of one sync cycle (docs/SYNC.md, S1-S9). Counts and flags only -
/// no domain values (hard rule 12).
public struct SyncOutcome: Equatable, Sendable {
    public var pulled = 0
    public var pushed = 0
    public var conflictsResolved = 0
    public var flaggedEntries = 0
    public var clampedIds: [UUID] = []
    public var deviceRevoked = false
    public var upgradeRequired = false
    public var transportUnavailable = false

    public init() {}
}

/// The sync client's one cycle: pull -> merge -> push (docs/SYNC.md, Protocol).
/// Pure coordination over an injected `SyncTransport` and the repository; every
/// failure is survivable - a transport outage returns rows to `.dirty`, a `410`
/// revokes without deleting local data, a `426` stops the push but never the
/// pull. No screen is ever sync-gated (hard rule 1).
public struct SyncEngine {
    public let repository: TankbookRepository
    public let transport: any SyncTransport
    public let cursorStore: any SyncCursorStore
    public let payloadMemory: any SyncPayloadMemory
    public let maxConflictRetries: Int
    public let batchLimit: Int
    public let pullPageLimit: Int
    /// The blob gate attachments hook into the existing push loop through
    /// (docs/SYNC.md, upload step 5). Nil (the default) keeps the pre-P4.6
    /// behaviour: attachment records push without a committed blob - wired only
    /// by the production app and the attachment tests.
    public let blobGate: (any BlobPushGate)?

    public init(
        repository: TankbookRepository,
        transport: any SyncTransport,
        cursorStore: any SyncCursorStore,
        payloadMemory: any SyncPayloadMemory = InMemorySyncPayloadMemory(),
        maxConflictRetries: Int = 3,
        batchLimit: Int = 200,
        pullPageLimit: Int = 500,
        blobGate: (any BlobPushGate)? = nil
    ) {
        self.repository = repository
        self.transport = transport
        self.cursorStore = cursorStore
        self.payloadMemory = payloadMemory
        self.maxConflictRetries = maxConflictRetries
        self.batchLimit = batchLimit
        self.pullPageLimit = pullPageLimit
        self.blobGate = blobGate
    }

    public func synchronize() async -> SyncOutcome {
        var outcome = SyncOutcome()
        try? repository.recoverStuckPushes()
        var affected = Set<UUID>()

        // 1. PULL (never sync-gated; a 410/transport failure just stops this half).
        do {
            let (pulled, touched) = try await pullAll()
            outcome.pulled = pulled
            affected.formUnion(touched)
        } catch SyncServerError.deviceRevoked {
            outcome.deviceRevoked = true
            return outcome
        } catch {
            outcome.transportUnavailable = true
            return outcome
        }

        // 2. PUSH.
        do {
            let summary = try await pushAll()
            outcome.pushed = summary.pushed
            outcome.conflictsResolved = summary.conflicts
            outcome.clampedIds = summary.clamped
            affected.formUnion(summary.touched)
        } catch SyncServerError.upgradeRequired {
            outcome.upgradeRequired = true
            try? repository.recoverStuckPushes()
        } catch {
            outcome.transportUnavailable = true
            try? repository.recoverStuckPushes()
        }

        // 3. Domain re-validation after the merge batch (docs/SYNC.md S3).
        outcome.flaggedEntries = (try? repository.revalidateTimeline(vehicleIds: affected)) ?? 0
        return outcome
    }

    // MARK: - Pull

    private func pullAll() async throws -> (pulled: Int, touched: Set<UUID>) {
        var since = try cursorStore.load() ?? 0
        var pulled = 0
        var touched = Set<UUID>()

        while true {
            let response = try await transport.pull(since: since, limit: pullPageLimit)
            for remote in response.records {
                touched.formUnion(try applyPull(remote))
                pulled += 1
            }
            // Persist the cursor only after the page is applied (cursor safety:
            // a crash before the next page resumes from the applied cursor and
            // re-reads the same page - nothing is skipped).
            try cursorStore.save(response.nextSince)
            if !response.more { break }
            since = response.nextSince
        }
        return (pulled, touched)
    }

    private func applyPull(_ remote: SyncPullRecord) throws -> Set<UUID> {
        guard let local = try repository.localSyncRecord(id: remote.id, entityType: remote.entityType) else {
            let touched = try repository.applyRemoteRecord(remote.asRecord(), scn: remote.scn)
            payloadMemory.recordSynced(id: remote.id, payload: remote.payload)
            try resurrectReferencedVehicles(for: remote.entityType, touched: touched)
            return touched
        }

        var localRecord = local.record
        if local.record.entityType == Vehicle.entityType {
            localRecord.fieldVersions = VehicleFieldVersions.compute(
                current: local.record.payload,
                lastSynced: payloadMemory.lastSyncedPayload(for: remote.id),
                updatedAt: local.record.clientUpdatedAt
            )
        }
        let result = RecordMerge.merge(local: localRecord, remote: remote.asRecord())

        switch result.winner {
        case .remote:
            let touched = try repository.applyRemoteRecord(result.keep, scn: remote.scn)
            payloadMemory.recordSynced(id: remote.id, payload: result.keep.payload)
            // S1/S4: a local edit overwritten by sync lands in the undo log.
            if let loser = result.loser, !loser.deleted, isLocalEdit(local.syncState) {
                try repository.recordSyncOverwrite(recordId: remote.id, losingRecord: loser)
            }
            try resurrectReferencedVehicles(for: remote.entityType, touched: touched)
            return touched
        case .local:
            // The local version is newer. A pending local edit stays dirty to
            // push; an already-synced row that "wins" on device-clock is clock
            // skew and is re-dirtied only if its content actually differs.
            if isLocalEdit(local.syncState) { return [] }
            if local.record.payload != remote.payload || local.record.deleted != remote.deleted {
                try repository.markDirty(id: remote.id, entityType: remote.entityType)
            }
            return []
        case .fieldMerge:
            // S9: the merged Vehicle is a new write - store it dirty so it pushes.
            let touched = try repository.applyRecord(result.keep, syncState: .dirty)
            payloadMemory.recordSynced(id: remote.id, payload: result.keep.payload)
            return touched
        }
    }

    /// S5: an entry pulled from another device references a vehicle this device
    /// deleted - resurrect it as archived (docs/SYNC.md S5).
    private func resurrectReferencedVehicles(for entityType: String, touched: Set<UUID>) throws {
        guard entityType != Vehicle.entityType else { return }
        for vehicleId in touched {
            try repository.resurrectArchivedIfTombstoned(vehicleId: vehicleId)
        }
    }

    // MARK: - Push

    private struct PushSummary {
        var pushed = 0
        var conflicts = 0
        var clamped: [UUID] = []
        var touched = Set<UUID>()
    }

    private func pushAll() async throws -> PushSummary {
        var summary = PushSummary()

        // Snapshot the dirty set once: each row gets one push attempt this
        // cycle. A row a conflict could not resolve stays dirty for the next
        // cycle rather than looping here (S6's bound is per conflict, and the
        // cycle must terminate even when the server conflicts forever).
        let dirty = try repository.fetchDirtyRows()
        var index = 0
        while index < dirty.count {
            let batch = Array(dirty[index ..< min(index + batchLimit, dirty.count)])
            index += batch.count

            var changes: [SyncPushChange] = []
            var items: [(id: UUID, entityType: String)] = []
            var localRecords: [UUID: SyncRecord] = [:]

            for change in batch {
                guard let local = try repository.localSyncRecord(id: change.id, entityType: change.entityType) else { continue }
                // Upload ordering (docs/SYNC.md, step 5): a live attachment
                // record must have its blob committed before it pushes. The gate
                // runs the begin -> PUT -> commit chain here, before the batch's
                // push; a deferral (missing file, 413/429, transport down) leaves
                // the record dirty for the next cycle - the entry syncs
                // text-first with the blob pending (S7).
                if change.entityType == Attachment.entityType, !local.record.deleted, let gate = blobGate {
                    guard let attachment = try? attachment(from: local.record),
                          await gate.ensureBlobCommitted(for: attachment) else {
                        continue
                    }
                }
                var record = local.record
                if local.record.entityType == Vehicle.entityType {
                    let versions = VehicleFieldVersions.compute(
                        current: local.record.payload,
                        lastSynced: payloadMemory.lastSyncedPayload(for: change.id),
                        updatedAt: local.record.clientUpdatedAt
                    )
                    record.fieldVersions = versions
                    record.payload = VehicleFieldVersions.write(into: local.record.payload, versions: versions)
                }
                localRecords[change.id] = record
                changes.append(SyncPushChange(
                    id: record.id,
                    entityType: record.entityType,
                    schemaVersion: record.schemaVersion,
                    baseScn: local.baseScn,
                    payload: record.payload,
                    clientUpdatedAt: record.clientUpdatedAt,
                    deleted: record.deleted
                ))
                items.append((change.id, change.entityType))
            }

            // Every live attachment record in this batch was deferred (blob not
            // committed yet); nothing to push, nothing to mark in flight.
            if changes.isEmpty { continue }

            let entityTypes = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.entityType) })
            try repository.markPushing(ids: items)

            let response = try await transport.push(changes)
            for result in response.results {
                let entityType = entityTypes[result.id] ?? ""
                switch result.status {
                case .accepted(let newScn, let isClamped):
                    try repository.markSynced(id: result.id, entityType: entityType, scn: newScn)
                    if let record = localRecords[result.id] {
                        payloadMemory.recordSynced(id: result.id, payload: record.payload)
                    }
                    if isClamped { summary.clamped.append(result.id) }
                    summary.pushed += 1
                case .conflict(let current):
                    let (resolved, conflictTouched) = try await resolveConflict(
                        id: result.id,
                        local: localRecords[result.id],
                        current: current,
                        entityType: entityType
                    )
                    summary.conflicts += resolved
                    summary.touched.formUnion(conflictTouched)
                case .rejected:
                    try repository.markDirty(id: result.id, entityType: entityType)
                }
            }
        }
        return summary
    }

    /// S6: a stale `baseScn` conflict re-merges against the server's current and
    /// re-pushes, fully automatically, with a bounded number of retries.
    private func resolveConflict(id: UUID, local: SyncRecord?, current: SyncPullRecord,
                                 entityType: String) async throws -> (resolved: Int, touched: Set<UUID>) {
        guard var localRecord = local else {
            try repository.markSynced(id: id, entityType: entityType, scn: current.scn)
            payloadMemory.recordSynced(id: id, payload: current.payload)
            return (1, [])
        }
        var currentRecord = current.asRecord()
        var currentScn = current.scn
        var remaining = maxConflictRetries

        while true {
            let result = RecordMerge.merge(local: localRecord, remote: currentRecord)
            let keep = result.keep

            // Nothing left to change - the server already holds our content.
            if keep.payload == currentRecord.payload && keep.deleted == currentRecord.deleted {
                let touched = try repository.applyRecord(keep, syncState: .synced(scn: currentScn))
                payloadMemory.recordSynced(id: id, payload: currentRecord.payload)
                // The local version lost (S1/S4): it lands in the undo log.
                if keep.payload != localRecord.payload || keep.deleted != localRecord.deleted {
                    try repository.recordSyncOverwrite(recordId: id, losingRecord: localRecord)
                }
                return (1, touched)
            }

            guard remaining > 0 else {
                try repository.markDirty(id: id, entityType: entityType)
                return (0, [])
            }
            remaining -= 1

            let change = SyncPushChange(
                id: keep.id,
                entityType: keep.entityType,
                schemaVersion: keep.schemaVersion,
                baseScn: currentScn,
                payload: keep.payload,
                clientUpdatedAt: keep.clientUpdatedAt,
                deleted: keep.deleted
            )
            let response = try await transport.push([change])
            guard let result = response.results.first else {
                try repository.markDirty(id: id, entityType: entityType)
                return (0, [])
            }
            switch result.status {
            case .accepted(let newScn, _):
                try repository.markSynced(id: id, entityType: entityType, scn: newScn)
                payloadMemory.recordSynced(id: id, payload: keep.payload)
                return (1, [])
            case .conflict(let nextCurrent):
                currentRecord = nextCurrent.asRecord()
                currentScn = nextCurrent.scn
                localRecord = keep
            case .rejected:
                try repository.markDirty(id: id, entityType: entityType)
                return (0, [])
            }
        }
    }

    private func isLocalEdit(_ state: SyncState) -> Bool {
        switch state {
        case .dirty, .pushing: return true
        case .synced: return false
        }
    }

    /// Decodes an `Attachment` entity from a record payload so the blob gate can
    /// read its content address and kind.
    private func attachment(from record: SyncRecord) throws -> Attachment {
        try PayloadCodec.decode(
            PayloadEnvelope(entityType: record.entityType,
                            schemaVersion: record.schemaVersion,
                            payload: record.payload),
            as: Attachment.self
        ).entity
    }
}
