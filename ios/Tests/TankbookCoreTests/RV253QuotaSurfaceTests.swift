import Foundation
import Testing
@testable import TankbookCore

// RV.253 - the Settings quota card must be fed by a real 429, not a DEBUG
// fixture. The transport already classifies the blob quota 429; these L1 tests
// drive the real engine over a scripted blob transport and assert the percent
// reaches the sync outcome (and therefore the Settings surface), that a
// percentless 429 reads as full, and that a later successful upload clears it.

/// One dirty attachment over a `BlobTransportDouble` whose `begin` is scripted
/// to answer the quota 429.
private func makeQuotaEngine(blobTransport: BlobTransportDouble)
    throws -> (engine: SyncEngine, repository: TankbookRepository) {
    let repo = try makeSyncRepository()
    let rendition = Data("quota-rendition".utf8)
    let gate = LocalFileBlobPushGate(
        uploader: BlobUploader(transport: blobTransport),
        source: FixedBlobSource(data: rendition))
    let engine = makeSyncEngine(repository: repo,
                                transport: SyncTransportDouble(),
                                blobGate: gate)
    try repo.upsertAttachment(makeSyncAttachment(sha256: BlobHash.sha256(rendition)))
    return (engine, repo)
}

@Suite("RV.253 quota card is fed by the real 429")
struct RV253QuotaSurfaceTests {

    @Test("a 429 carrying a percent records it and the surface reads quotaFull")
    func percentRidesFromTheTransportToTheSurface() async throws {
        let blobTransport = BlobTransportDouble()
        blobTransport.setBeginError(.quotaExceeded(usedPercent: 97))
        let (engine, _) = try makeQuotaEngine(blobTransport: blobTransport)

        let outcome = await engine.synchronize()

        #expect(outcome.quotaUsedPercent == 97,
                "the engine must record the 429's own percent")
        // The app-level fallback is the shared pure decision, so the assertion
        // covers exactly the line the mutation removes.
        let surfaced = SyncSurface.quotaUsedPercent(forced: nil, outcome: outcome)
        #expect(surfaced == 97)
        let state = SyncSurfaceState(isSignedIn: true, quotaUsedPercent: surfaced)
        #expect(SyncSurface.status(state) == .quotaFull)
        #expect(SyncSurface.chipState(state) == .quotaFull)
    }

    @Test("a 429 with no percent surfaces as 100 - exceeded IS full")
    func percentlessQuotaReadsAsFull() async throws {
        let blobTransport = BlobTransportDouble()
        blobTransport.setBeginError(.quotaExceeded(usedPercent: nil))
        let (engine, _) = try makeQuotaEngine(blobTransport: blobTransport)

        let outcome = await engine.synchronize()

        #expect(outcome.quotaUsedPercent == 100)
        let state = SyncSurfaceState(
            isSignedIn: true,
            quotaUsedPercent: SyncSurface.quotaUsedPercent(forced: nil, outcome: outcome))
        #expect(SyncSurface.status(state) == .quotaFull)
    }

    @Test("a later successful upload clears the quota state")
    func successfulUploadClearsTheQuota() async throws {
        let blobTransport = BlobTransportDouble()
        blobTransport.setBeginError(.quotaExceeded(usedPercent: 97))
        let (engine, repository) = try makeQuotaEngine(blobTransport: blobTransport)

        let quotaOutcome = await engine.synchronize()
        #expect(quotaOutcome.quotaUsedPercent == 97)
        // The attachment was deferred, so it is still queued for the next cycle.
        #expect(try repository.fetchDirtyRows().isEmpty == false)

        // The sweep freed space: the next begin dedupes/commits successfully.
        blobTransport.setBeginError(nil)
        let cleared = await engine.synchronize()

        #expect(cleared.quotaUsedPercent == nil,
                "a cycle whose blob upload succeeds must clear the quota card")
        #expect(SyncSurface.quotaUsedPercent(forced: nil, outcome: cleared) == nil)
        #expect(SyncSurface.status(SyncSurfaceState(
            isSignedIn: true,
            quotaUsedPercent: SyncSurface.quotaUsedPercent(forced: nil, outcome: cleared)))
            != .quotaFull)
    }

    @Test("the screenshot fixture still wins over the outcome")
    func forcedPercentWins() {
        var outcome = SyncOutcome()
        outcome.quotaUsedPercent = 96
        #expect(SyncSurface.quotaUsedPercent(forced: 95, outcome: outcome) == 95)
        #expect(SyncSurface.quotaUsedPercent(forced: nil, outcome: outcome) == 96)
        #expect(SyncSurface.quotaUsedPercent(forced: nil, outcome: nil) == nil)
    }
}
