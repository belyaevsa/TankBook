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
    /// The access token expired and the refresh failed (PR.1): the session is
    /// gone and the user signs in again. Distinct from `deviceRevoked` (a 410
    /// from the server) and from `offline`/`serverUnavailable` (an outage the
    /// app retries itself). Nothing is lost - rows stay dirty (S7).
    public var authExpired = false
    public var upgradeRequired = false
    /// The host could not be reached (no network, DNS failure, connection
    /// refused): the device is offline. Passive - the honest next step is
    /// "will sync when you're back online" (docs/ERRORS.md -> Settings), never
    /// an error. Nothing is lost - rows stay dirty (S7).
    public var offline = false
    /// The host answered 5xx: the server is up but failing. Distinct from
    /// `offline` because the honest next step differs: a 5xx names the service
    /// being down with "try again", where offline is a passive "back online"
    /// (docs/ERRORS.md -> Settings). Nothing is lost either way - rows stay
    /// dirty (S7).
    public var serverUnavailable = false
    /// A `402`/unknown-4xx refusal from a server newer than this client, or a
    /// `429` wait. Distinct from `offline`/`serverUnavailable` because the
    /// honest next step differs: an outage resolves itself, a refusal needs a
    /// newer app (P6.11). `retryAfterSeconds` carries the server's own hint
    /// when it sent one. Nothing is lost either way - the rows stay dirty (S7).
    public var refusedByServer: SyncServerError?
    public var retryAfterSeconds: Int?
    /// P6.8: the cycle was postponed because Low Power Mode is on and this was
    /// opportunistic work (docs/SYNC.md -> Low Power Mode). Nothing ran, the
    /// dirty queue is exactly as it was, and the work drains when the mode
    /// ends - resume, not next launch.
    public var deferred = false

    public init() {}
}

extension SyncOutcome {
    /// Splits the transport failure into the two PR.13 states, made where the
    /// transport failure is actually known: `offline` is the one case where the
    /// host never answered; every other error (a 5xx, an undecodable body, a
    /// pull-side refusal) means the host answered and the service is down, so it
    /// folds into `serverUnavailable`. Kept on the outcome so `SyncEngine`'s
    /// catch ladder stays below the cyclomatic-complexity budget.
    mutating func applyTransportFailure(_ error: any Error) {
        if case SyncServerError.offline = error {
            offline = true
        } else {
            serverUnavailable = true
        }
    }
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
    /// The injected power state (docs/SYNC.md -> Low Power Mode). Consulted for
    /// the blob-upload deferral; never `ProcessInfo` read inline.
    public let powerState: any PowerStateProvider

    public init(
        repository: TankbookRepository,
        transport: any SyncTransport,
        cursorStore: any SyncCursorStore,
        payloadMemory: any SyncPayloadMemory = InMemorySyncPayloadMemory(),
        maxConflictRetries: Int = 3,
        batchLimit: Int = 200,
        pullPageLimit: Int = 500,
        blobGate: (any BlobPushGate)? = nil,
        powerState: any PowerStateProvider = ProcessInfoPowerState()
    ) {
        self.repository = repository
        self.transport = transport
        self.cursorStore = cursorStore
        self.payloadMemory = payloadMemory
        self.maxConflictRetries = maxConflictRetries
        self.batchLimit = batchLimit
        self.pullPageLimit = pullPageLimit
        self.blobGate = blobGate
        self.powerState = powerState
    }

    public func synchronize(trigger: PowerWorkTrigger = .userInitiated) async -> SyncOutcome {
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
        } catch SyncServerError.authExpired {
            outcome.authExpired = true
            return outcome
        } catch {
            // A 5xx, an undecodable body, or a pull-side refusal: the host
            // answered, so the honest reading is "the service is down" - never
            // offline. `applyTransportFailure` splits the one case (offline) that
            // did NOT reach the host. The refusal folding is the pre-existing
            // pull-side asymmetry PR.7 noted.
            outcome.applyTransportFailure(error)
            return outcome
        }

        // 2. PUSH.
        do {
            let summary = try await pushAll(trigger: trigger)
            outcome.pushed = summary.pushed
            outcome.conflictsResolved = summary.conflicts
            outcome.clampedIds = summary.clamped
            affected.formUnion(summary.touched)
        } catch SyncServerError.upgradeRequired {
            outcome.upgradeRequired = true
            try? repository.recoverStuckPushes()
        } catch SyncServerError.tierRefused {
            outcome.refusedByServer = .tierRefused
            try? repository.recoverStuckPushes()
        } catch SyncServerError.rateLimited(let retryAfter) {
            outcome.refusedByServer = .rateLimited(retryAfterSeconds: retryAfter)
            outcome.retryAfterSeconds = retryAfter
            try? repository.recoverStuckPushes()
        } catch SyncServerError.refused(let status) {
            outcome.refusedByServer = .refused(status: status)
            try? repository.recoverStuckPushes()
        } catch SyncServerError.authExpired {
            outcome.authExpired = true
            try? repository.recoverStuckPushes()
        } catch {
            // A 5xx, a 410 during push, or an undecodable body: the host
            // answered, so this is the service being down - never offline.
            outcome.applyTransportFailure(error)
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

    private func pushAll(trigger: PowerWorkTrigger) async throws -> PushSummary {
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
                    // P6.8: blob upload is the heaviest work there is and
                    // defers while Low Power Mode is on (docs/SYNC.md), even
                    // inside a user-initiated sync - the record stays dirty and
                    // the entry syncs text-first with the blob pending (S7),
                    // exactly as it does when the blob transport is down.
                    // Nothing is lost: the row is not pushed, so it stays dirty
                    // for the next cycle.
                    if LowPowerPolicy.defers(work: .blobUpload, trigger: trigger,
                                             lowPowerMode: powerState.isLowPowerModeEnabled) {
                        continue
                    }
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
