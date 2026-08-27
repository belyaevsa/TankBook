import Foundation
import os
@testable import TankbookCore

// Shared sync test doubles (P4.5). `SyncTransportDouble` is a deterministic
// in-memory `SyncTransport`: it records every pull/push it receives and returns
// scripted responses, so the S1-S9 suite asserts against what was actually sent
// rather than a mock's opinion (the same trap named in the P4.4 brief).

/// A thread-safe, interleaved call log shared across the sync and blob transport
/// doubles. P4.6's upload-ordering invariant spans two transports - the blob
/// chain (begin/PUT/commit) must complete before the record's push - so both
/// doubles append to one log and the test asserts relative positions rather
/// than "both happened".
final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.lock(); events.append(event); lock.unlock()
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

/// A scripted, recording `BlobTransport`. Records every begin/put/commit/
/// download and returns scripted results, so the attachment suite asserts what
/// was actually issued (put was skipped on dedupe; download count is zero on a
/// payload-only list; commit precedes push).
final class BlobTransportDouble: BlobTransport, @unchecked Sendable {
    private struct State {
        var beginResult: BlobBeginResult = .exists
        var beginError: BlobSyncError?
        var putError: BlobSyncError?
        var commitError: BlobSyncError?
        var downloadError: BlobSyncError?
        var downloadResult: Data = Data()
        var beginRequests: [(sha256: String, size: Int, contentType: String)] = []
        var putRequests: [URL] = []
        var commits: [String] = []
        var downloads: [String] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let orderLog: OrderLog?

    init(orderLog: OrderLog? = nil) {
        self.orderLog = orderLog
    }

    func setBeginResult(_ result: BlobBeginResult) {
        lock.withLock { $0.beginResult = result }
    }

    func setBeginError(_ error: BlobSyncError?) {
        lock.withLock { $0.beginError = error }
    }

    func setPutError(_ error: BlobSyncError?) {
        lock.withLock { $0.putError = error }
    }

    func setCommitError(_ error: BlobSyncError?) {
        lock.withLock { $0.commitError = error }
    }

    func setDownloadError(_ error: BlobSyncError?) {
        lock.withLock { $0.downloadError = error }
    }

    func setDownloadResult(_ data: Data) {
        lock.withLock { $0.downloadResult = data }
    }

    var putRequestCount: Int {
        lock.withLock { $0.putRequests.count }
    }

    var commitCount: Int {
        lock.withLock { $0.commits.count }
    }

    var downloadCount: Int {
        lock.withLock { $0.downloads.count }
    }

    var recordedBeginRequests: [(sha256: String, size: Int, contentType: String)] {
        lock.withLock { $0.beginRequests }
    }

    func begin(sha256: String, size: Int, contentType: String) async throws -> BlobBeginResult {
        orderLog?.append("begin")
        let snapshot = lock.withLock { state -> (error: BlobSyncError?, result: BlobBeginResult) in
            state.beginRequests.append((sha256, size, contentType))
            return (state.beginError, state.beginResult)
        }
        if let error = snapshot.error { throw error }
        return snapshot.result
    }

    func put(_ data: Data, to url: URL, contentType: String) async throws {
        orderLog?.append("put")
        let error = lock.withLock { state -> BlobSyncError? in
            state.putRequests.append(url)
            return state.putError
        }
        if let error { throw error }
    }

    func commit(sha256: String) async throws {
        orderLog?.append("commit")
        let error = lock.withLock { state -> BlobSyncError? in
            state.commits.append(sha256)
            return state.commitError
        }
        if let error { throw error }
    }

    func download(sha256: String) async throws -> Data {
        orderLog?.append("download")
        let snapshot = lock.withLock { state -> (error: BlobSyncError?, result: Data) in
            state.downloads.append(sha256)
            return (state.downloadError, state.downloadResult)
        }
        if let error = snapshot.error { throw error }
        return snapshot.result
    }
}

/// A `BlobSource` that answers every attachment with the same fixed bytes - the
/// test double for the file-backed rendition source (no file I/O).
struct FixedBlobSource: BlobSource {
    let data: Data?
    func renditionData(for attachment: Attachment) throws -> Data? { data }
}

/// An in-memory `BlobStore` - the test double for the content-addressed cache.
final class InMemoryBlobStore: BlobStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    func data(for sha256: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return store[sha256]
    }

    func save(_ data: Data, for sha256: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[sha256] = data
    }
}

/// A scripted, recording `SyncTransport`. The lock makes it a valid `Sendable`
/// double for the async engine.
final class SyncTransportDouble: SyncTransport, @unchecked Sendable {
    private struct State {
        var pullResponses: [Result<SyncPullResponse, SyncServerError>] = []
        var pushResponses: [Result<SyncPushResponse, SyncServerError>] = []
        var pullRequests: [(since: Int64, limit: Int)] = []
        var pushBatches: [[SyncPushChange]] = []
        var callOrder: [String] = []
        var alwaysConflict = false
        var conflictCurrent: SyncPullRecord?
        var failAll = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let orderLog: OrderLog?

    init(orderLog: OrderLog? = nil) {
        self.orderLog = orderLog
    }

    func enqueuePull(_ response: SyncPullResponse) {
        lock.withLock { $0.pullResponses.append(.success(response)) }
    }

    func enqueuePullError(_ error: SyncServerError) {
        lock.withLock { $0.pullResponses.append(.failure(error)) }
    }

    func enqueuePush(_ response: SyncPushResponse) {
        lock.withLock { $0.pushResponses.append(.success(response)) }
    }

    func enqueuePushError(_ error: SyncServerError) {
        lock.withLock { $0.pushResponses.append(.failure(error)) }
    }

    /// Makes every push answer `conflict(current:)` with the given record - the
    /// S6 "server conflicts forever" harness.
    func setAlwaysConflict(current: SyncPullRecord) {
        lock.withLock {
            $0.alwaysConflict = true
            $0.conflictCurrent = current
        }
    }

    func setFailAll(_ fail: Bool) {
        lock.withLock { $0.failAll = fail }
    }

    var recordedPullRequests: [(since: Int64, limit: Int)] {
        lock.withLock { $0.pullRequests }
    }

    var recordedPushBatches: [[SyncPushChange]] {
        lock.withLock { $0.pushBatches }
    }

    /// The interleaved call order ("pull"/"push"), for the S7 pull-before-push
    /// assertion.
    var recordedCallOrder: [String] {
        lock.withLock { $0.callOrder }
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        orderLog?.append("pull")
        let snapshot = lock.withLock { state -> (failAll: Bool, next: Result<SyncPullResponse, SyncServerError>?) in
            state.pullRequests.append((since, limit))
            state.callOrder.append("pull")
            let next = state.pullResponses.isEmpty ? nil : state.pullResponses.removeFirst()
            return (state.failAll, next)
        }

        if snapshot.failAll { throw SyncServerError.transportUnavailable }
        if let next = snapshot.next { return try next.get() }
        return SyncPullResponse(records: [], nextSince: since, more: false,
                                schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1))
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        orderLog?.append("push")
        struct Snapshot {
            var failAll: Bool
            var alwaysConflict: Bool
            var current: SyncPullRecord?
            var next: Result<SyncPushResponse, SyncServerError>?
        }
        let snapshot = lock.withLock { state -> Snapshot in
            state.pushBatches.append(changes)
            state.callOrder.append("push")
            let next = state.pushResponses.isEmpty ? nil : state.pushResponses.removeFirst()
            return Snapshot(failAll: state.failAll, alwaysConflict: state.alwaysConflict,
                            current: state.conflictCurrent, next: next)
        }

        if snapshot.failAll { throw SyncServerError.transportUnavailable }
        if snapshot.alwaysConflict, let current = snapshot.current {
            return SyncPushResponse(results: changes.map {
                SyncPushResult(id: $0.id, status: .conflict(current: current))
            })
        }
        if let next = snapshot.next { return try next.get() }
        var scn: Int64 = 1
        return SyncPushResponse(results: changes.map { change in
            defer { scn += 1 }
            return SyncPushResult(id: change.id, status: .accepted(newScn: scn, clamped: false))
        })
    }
}

// MARK: - Entity/record builders

private let testTimestamp = Date(timeIntervalSinceReferenceDate: 0)

func makeSyncVehicle(id: UUID = UUID.v7(), name: String = "Volvo V60",
                     tankCapacityL: Double? = 71, initialOdometer: Int? = 119_486,
                     homeCurrency: CurrencyCode = .eur,
                     units: Vehicle.Units = Vehicle.Units(distance: .km, volume: .l,
                                                          consumption: .lPer100, energy: .kWhPer100),
                     paceLimitKmPerDay: Double = 1500) -> Vehicle {
    Vehicle(
        id: id, createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
        name: name, make: "Volvo", model: "V60", year: 2021, plate: "ABC-123",
        powertrain: .hybrid, fuelKinds: [.petrol95], tankCapacityL: tankCapacityL,
        batteryCapacityKWh: nil, homeCurrency: homeCurrency, units: units, photo: nil,
        archived: false, paceLimitKmPerDay: paceLimitKmPerDay, initialOdometer: initialOdometer
    )
}

func makeSyncFillUp(id: UUID = UUID.v7(), vehicleId: UUID, date: Date = testTimestamp,
                    odometer: Int? = 82_400, note: String? = nil, volumeL: Double = 42.3,
                    isFull: Bool = true) -> FillUp {
    FillUp(
        id: id, createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
        note: note, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        volumeL: volumeL, unitPrice: Decimal(string: "1.679")!, fuelKind: .petrol95,
        fuelGrade: nil, isFull: isFull, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .verified, extraction: nil
    )
}

/// Encodes a synced entity into a pull record (what the server would return).
func makePullRecord<E: SyncedEntity>(_ entity: E, scn: Int64, deleted: Bool? = nil) -> SyncPullRecord {
    let envelope = try! PayloadCodec.encode(entity)
    return SyncPullRecord(
        id: entity.id,
        entityType: E.entityType,
        schemaVersion: PayloadCodec.currentSchemaVersion,
        scn: scn,
        payload: envelope.payload,
        clientUpdatedAt: entity.updatedAt,
        deleted: deleted ?? (entity.deletedAt != nil)
    )
}

/// Builds a `SyncRecord` from a synced entity, with explicit per-field versions.
func makeSyncRecord<E: SyncedEntity>(_ entity: E, clientUpdatedAt: Date,
                                     fieldVersions: [String: Date]? = nil) -> SyncRecord {
    let envelope = try! PayloadCodec.encode(entity)
    return SyncRecord(
        id: entity.id,
        entityType: E.entityType,
        schemaVersion: PayloadCodec.currentSchemaVersion,
        payload: envelope.payload,
        clientUpdatedAt: clientUpdatedAt,
        deleted: entity.deletedAt != nil,
        fieldVersions: fieldVersions
    )
}

func makeSyncRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

func makeSyncEngine(repository: TankbookRepository, transport: any SyncTransport,
                    cursor: SyncCursorStore = InMemorySyncCursorStore(),
                    memory: SyncPayloadMemory = InMemorySyncPayloadMemory(),
                    maxConflictRetries: Int = 3,
                    pullPageLimit: Int = 500,
                    blobGate: (any BlobPushGate)? = nil) -> SyncEngine {
    SyncEngine(repository: repository, transport: transport, cursorStore: cursor,
               payloadMemory: memory, maxConflictRetries: maxConflictRetries,
               pullPageLimit: pullPageLimit,
               blobGate: blobGate)
}

func makeSyncAttachment(id: UUID = UUID.v7(), kind: AttachmentKind = .photo,
                        sha256: String, thumbnailBase64: String? = nil,
                        relativePath: String = "photos/seed.jpg") -> Attachment {
    Attachment(
        id: id, createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
        kind: kind, file: LocalFileRef(sha256: sha256, relativePath: relativePath),
        extractedTimestamp: nil, ocrText: nil, thumbnailBase64: thumbnailBase64
    )
}
