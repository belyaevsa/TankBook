import Foundation
import os
import Testing
@testable import TankbookCore

/// The background photo prefetch (docs/SYNC.md -> Delivery, docs/JOURNEYS.md
/// J11). Three properties: the plan is newest-first and skips what is already
/// on the device; the run defers whole under Low Power Mode or a constrained
/// path, spending nothing; progress is reported monotonically to the end.
@Suite("Blob prefetch (PJ.35)")
struct BlobPrefetchTests {

    private static let day: TimeInterval = 86_400

    /// Serves, for any sha, bytes that hash to that sha - the fetcher's
    /// verify-on-download then accepts every planned item. Records the order.
    private final class ContentAddressedTransport: BlobTransport, @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [String]())
        private let bytesBySha: [String: Data]
        var downloads: [String] { lock.withLock { $0 } }

        init(payloads: [Data]) {
            bytesBySha = Dictionary(uniqueKeysWithValues: payloads.map { (BlobHash.sha256($0), $0) })
        }

        func begin(sha256: String, size: Int, contentType: String) async throws -> BlobBeginResult { .exists }
        func put(_ data: Data, to url: URL, contentType: String) async throws {}
        func commit(sha256: String) async throws {}
        func download(sha256: String) async throws -> Data {
            lock.withLock { $0.append(sha256) }
            guard let data = bytesBySha[sha256] else { throw BlobSyncError.hashMismatch }
            return data
        }
    }

    private final class Progress: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [(Int, Int)]())
        var reports: [(Int, Int)] { lock.withLock { $0 } }
        func report(_ completed: Int, _ total: Int) { lock.withLock { $0.append((completed, total)) } }
    }

    // MARK: - The plan

    @Test("missing blobs are ordered by their entry's date, newest first, and available ones are skipped")
    func planIsNewestFirstAndSkipsAvailable() {
        let vehicle = makeSyncVehicle()
        let old = makeSyncAttachment(sha256: "aaa")
        let mid = makeSyncAttachment(sha256: "bbb")
        let new = makeSyncAttachment(sha256: "ccc")
        let onDevice = makeSyncAttachment(sha256: "ddd")
        let base = Date(timeIntervalSince1970: 1_752_000_000)
        var oldFill = makeSyncFillUp(vehicleId: vehicle.id, date: base - 30 * Self.day)
        oldFill.attachments = [old.id]
        var midFill = makeSyncFillUp(vehicleId: vehicle.id, date: base - 10 * Self.day)
        midFill.attachments = [mid.id, onDevice.id]
        var newFill = makeSyncFillUp(vehicleId: vehicle.id, date: base)
        newFill.attachments = [new.id]

        let plan = BlobPrefetchPlan.newestFirst(
            attachments: [old, onDevice, new, mid], entries: [oldFill, newFill, midFill],
            isAvailable: { $0.file.sha256 == "ddd" })

        #expect(plan.map(\.sha256) == ["ccc", "bbb", "aaa"])
    }

    @Test("one receipt shared by a grouped save is planned once, at its newest date")
    func sharedShaIsPlannedOnce() {
        let vehicle = makeSyncVehicle()
        let shared = makeSyncAttachment(sha256: "shared")
        let other = makeSyncAttachment(sha256: "other")
        let base = Date(timeIntervalSince1970: 1_752_000_000)
        var fill = makeSyncFillUp(vehicleId: vehicle.id, date: base - 5 * Self.day)
        fill.attachments = [shared.id]
        var later = makeSyncFillUp(vehicleId: vehicle.id, date: base - 2 * Self.day)
        later.attachments = [other.id]
        // A second attachment row pointing at the same bytes, on a newer entry.
        let sharedAgain = makeSyncAttachment(sha256: "shared")
        var newest = makeSyncFillUp(vehicleId: vehicle.id, date: base)
        newest.attachments = [sharedAgain.id]

        let plan = BlobPrefetchPlan.newestFirst(
            attachments: [shared, other, sharedAgain], entries: [fill, later, newest],
            isAvailable: { _ in false })

        #expect(plan.map(\.sha256) == ["shared", "other"])
    }

    @Test("an attachment no entry references is planned at its own creation date")
    func orphanFallsBackToCreatedAt() {
        let orphan = makeSyncAttachment(sha256: "orphan")
        let plan = BlobPrefetchPlan.newestFirst(attachments: [orphan], entries: [], isAvailable: { _ in false })
        #expect(plan.map(\.sha256) == ["orphan"])
        #expect(plan.first?.date == orphan.createdAt)
    }

    // MARK: - The gates

    @Test("Low Power Mode defers the whole run, even a user-initiated one, and downloads nothing")
    func lowPowerDefers() async {
        let transport = ContentAddressedTransport(payloads: [Data("a".utf8)])
        let prefetcher = BlobPrefetcher(
            fetcher: LazyBlobFetcher(transport: transport, store: InMemoryBlobStore()),
            powerState: MutablePowerState(lowPower: true),
            isNetworkConstrained: { false })
        let plan = [BlobPrefetchPlan.Item(sha256: BlobHash.sha256(Data("a".utf8)), date: Date())]

        let outcome = await prefetcher.run(plan: plan, trigger: .userInitiated) { _, _ in }

        #expect(outcome == .deferredLowPower)
        #expect(transport.downloads.isEmpty)
    }

    @Test("a constrained path defers the whole run and downloads nothing")
    func constrainedNetworkDefers() async {
        let transport = ContentAddressedTransport(payloads: [Data("a".utf8)])
        let prefetcher = BlobPrefetcher(
            fetcher: LazyBlobFetcher(transport: transport, store: InMemoryBlobStore()),
            powerState: MutablePowerState(lowPower: false),
            isNetworkConstrained: { true })
        let plan = [BlobPrefetchPlan.Item(sha256: BlobHash.sha256(Data("a".utf8)), date: Date())]

        #expect(await prefetcher.run(plan: plan, trigger: .background) { _, _ in } == .deferredConstrainedNetwork)
        #expect(transport.downloads.isEmpty)
    }

    @Test("an empty plan is nothing to fetch, never a zero-of-zero bar")
    func emptyPlanIsNothingToFetch() async {
        let transport = ContentAddressedTransport(payloads: [])
        let prefetcher = BlobPrefetcher(
            fetcher: LazyBlobFetcher(transport: transport, store: InMemoryBlobStore()),
            powerState: MutablePowerState(lowPower: false),
            isNetworkConstrained: { false })
        let progress = Progress()
        #expect(await prefetcher.run(plan: [], trigger: .background, progress: progress.report) == .nothingToFetch)
        #expect(progress.reports.isEmpty)
    }

    // MARK: - The run

    @Test("the run fetches in plan order, reports monotonic progress to the end, and counts a bad blob as failed")
    func runFetchesInOrderWithMonotonicProgress() async {
        let payloads = [Data("newest".utf8), Data("older".utf8)]
        let transport = ContentAddressedTransport(payloads: payloads)
        let store = InMemoryBlobStore()
        let prefetcher = BlobPrefetcher(
            fetcher: LazyBlobFetcher(transport: transport, store: store),
            powerState: MutablePowerState(lowPower: false),
            isNetworkConstrained: { false })
        let shas = payloads.map(BlobHash.sha256)
        let plan = [
            BlobPrefetchPlan.Item(sha256: shas[0], date: Date()),
            BlobPrefetchPlan.Item(sha256: shas[1], date: Date() - 1),
            BlobPrefetchPlan.Item(sha256: "nowhere", date: Date() - 2)
        ]
        let progress = Progress()

        let outcome = await prefetcher.run(plan: plan, trigger: .background, progress: progress.report)

        #expect(outcome == .completed(fetched: 2, failed: 1))
        #expect(transport.downloads == [shas[0], shas[1], "nowhere"])
        #expect(progress.reports.map(\.0) == [0, 1, 2, 3])
        #expect(progress.reports.allSatisfy { $0.1 == 3 })
        #expect((try? store.data(for: shas[0])) != nil)
        #expect((try? store.data(for: shas[1])) != nil)
    }
}
