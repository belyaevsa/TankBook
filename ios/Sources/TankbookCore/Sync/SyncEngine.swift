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
    /// The second push-batch bound, alongside `batchLimit` (RV.97): the maximum
    /// encoded size of one push request body. The server's own `/sync/push` body
    /// cap (~52 MB - 200 x 256 KB payloads + envelope, docs/API.md -> Request
    /// body caps) is NOT the binding constraint - the mobile uplink is: the
    /// observed production livelock body was ~150 KB of imported history, which
    /// died at the push request's 30 s read budget and was rebuilt identically
    /// every cycle because a count-only batch of 200 is unbounded in bytes.
    /// 64 KB splits that body into three requests that each finish inside the
    /// upload budget (`TransportTimeouts.upload`). It is a client transport
    /// constant, so it is compiled here, never remote-configurable
    /// (docs/PRACTICES.md -> constants placement: transport tunables are
    /// compiled).
    public static let defaultMaxBatchBytes = 64 * 1024
    public let maxBatchBytes: Int
    public let pullPageLimit: Int
    /// The blob gate attachments hook into the existing push loop through
    /// (docs/SYNC.md, upload step 5). Nil (the default) keeps the pre-P4.6
    /// behaviour: attachment records push without a committed blob - wired only
    /// by the production app and the attachment tests.
    public let blobGate: (any BlobPushGate)?
    /// The injected power state (docs/SYNC.md -> Low Power Mode). Consulted for
    /// the blob-upload deferral; never `ProcessInfo` read inline.
    public let powerState: any PowerStateProvider
    /// The optional logging facade (OB.2). Nil keeps the engine silent, which
    /// is how every existing test and un-wired embedding behaves. When set, one
    /// cycle emits `sync.cycle.begin`/`sync.cycle.end`, one aggregate
    /// `sync.merge` line per non-empty cycle (never one per record,
    /// docs/LOGGING.md §7), and a `sync.clock.skew` line when the server
    /// clamped pushed stamps.
    public let log: TankbookLog?

    public init(
        repository: TankbookRepository,
        transport: any SyncTransport,
        cursorStore: any SyncCursorStore,
        payloadMemory: any SyncPayloadMemory = InMemorySyncPayloadMemory(),
        maxConflictRetries: Int = 3,
        batchLimit: Int = 200,
        maxBatchBytes: Int = SyncEngine.defaultMaxBatchBytes,
        pullPageLimit: Int = 500,
        blobGate: (any BlobPushGate)? = nil,
        powerState: any PowerStateProvider = ProcessInfoPowerState(),
        log: TankbookLog? = nil
    ) {
        self.repository = repository
        self.transport = transport
        self.cursorStore = cursorStore
        self.payloadMemory = payloadMemory
        self.maxConflictRetries = maxConflictRetries
        self.batchLimit = batchLimit
        self.maxBatchBytes = maxBatchBytes
        self.pullPageLimit = pullPageLimit
        self.blobGate = blobGate
        self.powerState = powerState
        self.log = log
    }

    public func synchronize(trigger: PowerWorkTrigger = .userInitiated) async -> SyncOutcome {
        var outcome = SyncOutcome()
        let sessionId = UUID.v7()
        let startedAt = Date()
        // The per-cycle tally behind the ONE `sync.merge` line (OB.2): counts
        // only - how many remote records arrived, how many local edits a merge
        // overwrote (S1/S4) and how many transport conflicts a push resolved
        // (S6). A reference box because it crosses async calls; it is touched
        // only from this task, so no lock is needed.
        let tally = SyncCycleTally()
        log?.emit(SyncCycleBegin(syncSessionId: sessionId, trigger: trigger.syncTrigger))
        defer {
            log?.emit(SyncCycleEnd(
                syncSessionId: sessionId,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                recordsPulled: outcome.pulled,
                recordsPushed: outcome.pushed))
        }
        // RV.157: the writes THIS cycle performs are the response to a sync,
        // never a new local write - silence the database write signal for the
        // whole cycle so its bookkeeping cannot re-trigger the debounced
        // write-trigger (which would make an offline push retry forever).
        repository.database.writeSignal.suppress()
        defer { repository.database.writeSignal.resume() }

        try? repository.recoverStuckPushes()
        var affected = Set<UUID>()

        // 1. PULL (never sync-gated; a 410/transport failure just stops this half).
        do {
            let (pulled, touched) = try await pullAll(tally: tally)
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
            let summary = try await pushAll(trigger: trigger, tally: tally)
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
        } catch SyncServerError.deviceRevoked {
            // RV.58: a 410 is a revocation, wherever in the cycle it lands. On
            // the PUSH half it used to fold into `applyTransportFailure` (a 5xx
            // "server down"), which the retry policy then retried with backoff -
            // a revoked device kept pulling and pushing for minutes. It is
            // terminal exactly as it is on pull: the cycle stops, the outcome
            // surfaces `deviceRevoked`, and nothing is retried (SyncRetryPolicy
            // never schedules a refusal).
            outcome.deviceRevoked = true
            try? repository.recoverStuckPushes()
        } catch {
            // A 5xx, an offline transport, or an undecodable body: `offline`
            // (the host never answered) and a 5xx (the host answered but the
            // service is down) are the two transient classes - never a
            // revocation, which has its own catch above.
            outcome.applyTransportFailure(error)
            try? repository.recoverStuckPushes()
        }

        // The one aggregate merge line for the cycle (OB.2, docs/LOGGING.md
        // §7): records that arrived plus the conflicts the merge actually
        // performed, tagged by SYNC.md scenario. Emitted only for a cycle that
        // merged something - an inert cycle says nothing.
        if tally.pulled > 0 || tally.overwriteConflicts > 0 || tally.pushTransportConflicts > 0
            || tally.dirtiedByPull > 0 {
            var conflicts: [SyncConflict] = []
            if tally.overwriteConflicts > 0 {
                conflicts.append(SyncConflict(scenario: .s1, count: tally.overwriteConflicts))
            }
            if tally.pushTransportConflicts > 0 {
                conflicts.append(SyncConflict(scenario: .s6, count: tally.pushTransportConflicts))
            }
            log?.emit(SyncMerge(recordsApplied: tally.pulled, conflicts: conflicts,
                                dirtiedByPull: tally.dirtiedByPull))
        }

        // A clamped push means this device's clock runs ahead of the server's -
        // one line per cycle, count only (the id list stays in the outcome).
        if tally.clamped > 0 {
            log?.emit(SyncClockSkew(syncSessionId: sessionId, clampedCount: tally.clamped))
        }

        // 3. Domain re-validation after the merge batch (docs/SYNC.md S3).
        outcome.flaggedEntries = (try? repository.revalidateTimeline(vehicleIds: affected,
                                                                      log: log)) ?? 0
        return outcome
    }

    // MARK: - Pull

    private func pullAll(tally: SyncCycleTally) async throws -> (pulled: Int, touched: Set<UUID>) {
        var since = try cursorStore.load() ?? 0
        var pulled = 0
        var touched = Set<UUID>()

        while true {
            let response = try await transport.pull(since: since, limit: pullPageLimit)
            for remote in response.records {
                touched.formUnion(try applyPull(remote, tally: tally))
                pulled += 1
            }
            // Persist the cursor only after the page is applied (cursor safety:
            // a crash before the next page resumes from the applied cursor and
            // re-reads the same page - nothing is skipped).
            try cursorStore.save(response.nextSince)
            if !response.more { break }
            since = response.nextSince
        }
        tally.pulled = pulled
        return (pulled, touched)
    }

    private func applyPull(_ remote: SyncPullRecord, tally: SyncCycleTally) throws -> Set<UUID> {
        guard let local = try repository.localSyncRecord(id: remote.id, entityType: remote.entityType) else {
            let touched = try repository.applyRemoteRecord(remote.asRecord(), scn: remote.scn)
            payloadMemory.recordSynced(id: remote.id, payload: remote.payload)
            try resurrectReferencedVehicles(for: remote.entityType, remoteDeleted: remote.deleted, touched: touched)
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
                tally.overwriteConflicts += 1
                try repository.recordSyncOverwrite(recordId: remote.id, losingRecord: loser,
                                                   deviceName: remote.originDeviceName)
            }
            try resurrectReferencedVehicles(for: remote.entityType, remoteDeleted: remote.deleted, touched: touched)
            return touched
        case .local:
            // RV.14: a live `Vehicle` whose field-level merge equaled the local
            // record is already correct here - record the server's SCN and leave
            // its sync state alone (a pending edit stays dirty and still pushes).
            if remote.entityType == Vehicle.entityType, !local.record.deleted, !remote.deleted {
                if isLocalEdit(local.syncState) { return [] }
                try repository.markSynced(id: remote.id, entityType: remote.entityType, scn: remote.scn)
                return []
            }
            // The local version is newer. A pending local edit stays dirty to
            // push; an already-synced row that "wins" on device-clock is clock
            // skew and is re-dirtied only if its content actually differs.
            // RV.35: "differs" is judged at the decoded level (`RecordMerge.
            // recordsEqual`), never the raw payload bytes, which do not converge
            // across a lossy round-trip - re-dirtying on those bytes was the
            // echo loop. A genuinely different decoded record (or a differing
            // `deleted` flag) still re-dirties and pushes (hard rule 8).
            if isLocalEdit(local.syncState) { return [] }
            if !RecordMerge.recordsEqual(local.record, remote.asRecord())
                || local.record.deleted != remote.deleted {
                try repository.markDirty(id: remote.id, entityType: remote.entityType)
                tally.dirtiedByPull += 1
            }
            return []
        case .fieldMerge:
            // S9: the merged Vehicle is a genuine new write (its content differs
            // from both sides - RecordMerge reports nothing else as `.fieldMerge`)
            // - store it dirty so it pushes. RV.136: a content-equal merge never
            // reaches here, so a dirty store is never a phantom echo push.
            let touched = try repository.applyRecord(result.keep, syncState: .dirty)
            tally.dirtiedByPull += 1
            payloadMemory.recordSynced(id: remote.id, payload: result.keep.payload)
            return touched
        }
    }

    /// S5: an entry pulled from another device references a vehicle this device
    /// deleted - resurrect it as archived (docs/SYNC.md S5). S5a: a record that
    /// is ITSELF a tombstone (the deletion cascade's own rows) must not
    /// resurrect the car it was tombstoned with - `remoteDeleted` skips it, so
    /// the cascade cannot undo the vehicle tombstone it follows (docs/SYNC.md
    /// S5a).
    private func resurrectReferencedVehicles(for entityType: String, remoteDeleted: Bool, touched: Set<UUID>) throws {
        guard entityType != Vehicle.entityType, !remoteDeleted else { return }
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

    /// One row of the dirty snapshot that survived to push: the wire `change`
    /// plus the local `record` its accepted outcome must remember for the
    /// payload memory. Built once per row, then chunked into push batches.
    private struct PushCandidate {
        let change: SyncPushChange
        let record: SyncRecord
    }

    /// The per-cycle merge tally behind the single `sync.merge` line (OB.2).
    /// Counts only - never a record list, never a domain value. A reference
    /// box (not a struct) because it crosses async calls; it is touched only
    /// from the one synchronize task, so it needs no lock.
    fileprivate final class SyncCycleTally {
        var pulled = 0
        var overwriteConflicts = 0
        var pushTransportConflicts = 0
        var clamped = 0
        /// Records a pull application left queued for push (`.fieldMerge`
        /// Vehicle, or an RV.35 divergence the `.local` arm re-dirtied) - the
        /// echo-loop signal on an otherwise idle account.
        var dirtiedByPull = 0
    }

    private func pushAll(trigger: PowerWorkTrigger, tally: SyncCycleTally) async throws -> PushSummary {
        var summary = PushSummary()

        // Snapshot the dirty set once: each row gets one push attempt this
        // cycle. A row a conflict could not resolve stays dirty for the next
        // cycle rather than looping here (S6's bound is per conflict, and the
        // cycle must terminate even when the server conflicts forever).
        let dirty = try repository.fetchDirtyRows()

        // Stream the rows into batches bounded by BOTH bounds (docs/SYNC.md ->
        // Protocol, RV.97): the server's record cap (`batchLimit`,
        // SyncService.MaxChangesPerBatch) AND the encoded request-body size
        // (`maxBatchBytes`, measured by `SyncPushWire` - the exact bytes
        // `RemoteSyncTransport` puts on the wire, payloads plus the envelope).
        // The size bound is the one that was missing: 200 records of imported
        // history made an unbounded ~150 KB body that outlived the request's
        // read budget and was rebuilt identically every cycle.
        //
        // A batch is flushed as soon as the next row would exceed a bound, not
        // after every candidate has been built: a cycle interrupted part-way has
        // already pushed what it built, the blob gate's uploads stay interleaved
        // with the pushes they belong to (as they were before RV.97), and no
        // more than one batch of payloads is ever held in memory.
        //
        // A change that exceeds the size cap on its own still ships, alone - a
        // record that cannot be pushed is a record lost silently (hard rule 8),
        // and the server accepts a payload up to 256 KB (docs/API.md -> Payload
        // validation). The flush is guarded by the batch being non-empty, so a
        // batch is never empty and an oversize row is never deferred forever.
        var batch: [PushCandidate] = []
        var batchWireBytes = SyncPushWire.wrapperBytes
        for pending in dirty {
            guard let candidate = try await pushCandidate(for: pending, trigger: trigger) else { continue }
            let elementBytes = SyncPushWire.elementBytes(for: candidate.change)
            let wouldOverflowBytes = batchWireBytes + elementBytes + 1 > maxBatchBytes
            if !batch.isEmpty, batch.count >= batchLimit || wouldOverflowBytes {
                try await push(batch, summary: &summary, tally: tally)
                batch = []
                batchWireBytes = SyncPushWire.wrapperBytes
            }
            batch.append(candidate)
            batchWireBytes += elementBytes + (batch.count > 1 ? 1 : 0)
        }
        if !batch.isEmpty {
            try await push(batch, summary: &summary, tally: tally)
        }
        return summary
    }

    /// One dirty row turned into the change that goes on the wire, or nil when
    /// the row is not pushable this cycle (its local record vanished, or a live
    /// attachment's blob is not committed yet).
    private func pushCandidate(for pending: PendingChange,
                               trigger: PowerWorkTrigger) async throws -> PushCandidate? {
        guard let local = try repository.localSyncRecord(id: pending.id, entityType: pending.entityType) else { return nil }
        // Upload ordering (docs/SYNC.md, step 5): a live attachment record must
        // have its blob committed before it pushes. The gate runs the
        // begin -> PUT -> commit chain here, before the batch's push; a deferral
        // (missing file, 413/429, transport down) leaves the record dirty for the
        // next cycle - the entry syncs text-first with the blob pending (S7).
        if pending.entityType == Attachment.entityType, !local.record.deleted, let gate = blobGate {
            // P6.8: blob upload is the heaviest work there is and defers while
            // Low Power Mode is on (docs/SYNC.md), even inside a user-initiated
            // sync - the record stays dirty and the entry syncs text-first with
            // the blob pending (S7), exactly as it does when the blob transport
            // is down. Nothing is lost: the row is not pushed, so it stays dirty
            // for the next cycle.
            if LowPowerPolicy.defers(work: .blobUpload, trigger: trigger,
                                     lowPowerMode: powerState.isLowPowerModeEnabled) {
                return nil
            }
            guard let attachment = try? attachment(from: local.record),
                  await gate.ensureBlobCommitted(for: attachment) else {
                return nil
            }
        }
        var record = local.record
        if local.record.entityType == Vehicle.entityType {
            let versions = VehicleFieldVersions.compute(
                current: local.record.payload,
                lastSynced: payloadMemory.lastSyncedPayload(for: pending.id),
                updatedAt: local.record.clientUpdatedAt
            )
            record.fieldVersions = versions
            record.payload = VehicleFieldVersions.write(into: local.record.payload, versions: versions)
        }
        return PushCandidate(
            change: SyncPushChange(
                id: record.id,
                entityType: record.entityType,
                schemaVersion: record.schemaVersion,
                baseScn: local.baseScn,
                payload: record.payload,
                clientUpdatedAt: record.clientUpdatedAt,
                deleted: record.deleted
            ),
            record: record
        )
    }

    /// One push request: mark the rows in flight, send the batch, apply each
    /// result. Never called with an empty batch.
    private func push(_ batch: [PushCandidate], summary: inout PushSummary,
                      tally: SyncCycleTally) async throws {
        let changes = batch.map(\.change)
        let items = batch.map { (id: $0.change.id, entityType: $0.change.entityType) }
        let entityTypes = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.entityType) })
        let localRecords = Dictionary(uniqueKeysWithValues: batch.map { ($0.change.id, $0.record) })

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
                if isClamped {
                    summary.clamped.append(result.id)
                    tally.clamped += 1
                }
                summary.pushed += 1
            case .conflict(let current):
                let (resolved, conflictTouched) = try await resolveConflict(
                    id: result.id,
                    local: localRecords[result.id],
                    current: current,
                    entityType: entityType,
                    tally: tally
                )
                summary.conflicts += resolved
                tally.pushTransportConflicts += resolved
                summary.touched.formUnion(conflictTouched)
            case .rejected:
                try repository.markDirty(id: result.id, entityType: entityType)
            }
        }
    }

    /// S6: a stale `baseScn` conflict re-merges against the server's current and
    /// re-pushes, fully automatically, with a bounded number of retries.
    private func resolveConflict(id: UUID, local: SyncRecord?, current: SyncPullRecord,
                                 entityType: String, tally: SyncCycleTally) async throws -> (resolved: Int, touched: Set<UUID>) {
        guard var localRecord = local else {
            try repository.markSynced(id: id, entityType: entityType, scn: current.scn)
            payloadMemory.recordSynced(id: id, payload: current.payload)
            return (1, [])
        }
        var currentRecord = current.asRecord()
        var currentScn = current.scn
        var remaining = maxConflictRetries
        let remoteDeviceName = current.originDeviceName

        while true {
            let result = RecordMerge.merge(local: localRecord, remote: currentRecord)
            let keep = result.keep

            // Nothing left to change - the server already holds our content.
            if keep.payload == currentRecord.payload && keep.deleted == currentRecord.deleted {
                let touched = try repository.applyRecord(keep, syncState: .synced(scn: currentScn))
                payloadMemory.recordSynced(id: id, payload: currentRecord.payload)
                // The local version lost (S1/S4): it lands in the undo log.
                if keep.payload != localRecord.payload || keep.deleted != localRecord.deleted {
                    tally.overwriteConflicts += 1
                    try repository.recordSyncOverwrite(recordId: id, losingRecord: localRecord,
                                                       deviceName: remoteDeviceName)
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
