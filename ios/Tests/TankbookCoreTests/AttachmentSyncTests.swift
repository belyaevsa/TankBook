import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TankbookCore

// P4.6 attachment-sync tests (docs/SYNC.md -> Attachments: the blob pipeline,
// docs/TASKS.md P4.6). The decisions (what to upload, in what order, when to
// download, what to cache) are pure value types over injected doubles - no
// `URLSession`, no server, no file I/O. The load-bearing invariant is the
// upload ordering: a record referencing a blob must not push until `commit`
// has succeeded, asserted on the *call order*, not on "both happened".

private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)

private func uploadURL() -> URL {
    URL(string: "https://storage.example/presigned/put")!
}

// MARK: - The ordering invariant (the test this task exists for)

@Test func attachmentRecordDoesNotPushUntilCommitSucceeds() async throws {
    let repo = try makeSyncRepository()
    let rendition = Data("rendition-bytes".utf8)
    let sha256 = BlobHash.sha256(rendition)

    let orderLog = OrderLog()
    let blobTransport = BlobTransportDouble(orderLog: orderLog)
    blobTransport.setBeginResult(.upload(url: uploadURL(), expiresAt: nil))
    let gate = LocalFileBlobPushGate(
        uploader: BlobUploader(transport: blobTransport),
        source: FixedBlobSource(data: rendition))
    let syncTransport = SyncTransportDouble(orderLog: orderLog)
    let engine = makeSyncEngine(repository: repo, transport: syncTransport, blobGate: gate)

    let attachment = makeSyncAttachment(sha256: sha256)
    try repo.upsertAttachment(attachment)

    _ = await engine.synchronize()

    // Assert ORDER, not occurrence: begin -> PUT -> commit must all precede the
    // record's push. A test that only checked "commit and push both happened"
    // would pass a broken implementation that pushed first.
    let order = orderLog.recorded
    guard let begin = order.firstIndex(of: "begin"),
          let put = order.firstIndex(of: "put"),
          let commit = order.firstIndex(of: "commit"),
          let push = order.firstIndex(of: "push") else {
        Issue.record("expected begin/put/commit/push in the call log, got \(order)")
        return
    }
    #expect(begin < put, "begin must precede PUT")
    #expect(put < commit, "PUT must precede commit")
    #expect(commit < push, "commit must precede the record's push")

    // And the record did push (the upload gate allowed it).
    #expect(syncTransport.recordedPushBatches.contains { $0.contains { $0.id == attachment.id } })
    #expect(try repo.fetchDirtyRows().isEmpty)
}

// MARK: - The negative half: commit failure

@Test func commitFailureDefersTheRecordAndRetriesLater() async throws {
    let repo = try makeSyncRepository()
    let rendition = Data("rendition-bytes".utf8)
    let sha256 = BlobHash.sha256(rendition)

    let blobTransport = BlobTransportDouble()
    blobTransport.setBeginResult(.upload(url: uploadURL(), expiresAt: nil))
    blobTransport.setCommitError(.transportUnavailable)
    let gate = LocalFileBlobPushGate(
        uploader: BlobUploader(transport: blobTransport),
        source: FixedBlobSource(data: rendition))
    let syncTransport = SyncTransportDouble()
    let engine = makeSyncEngine(repository: repo, transport: syncTransport, blobGate: gate)

    let attachment = makeSyncAttachment(sha256: sha256)
    try repo.upsertAttachment(attachment)

    _ = await engine.synchronize()

    // The record did NOT push - no push batch carried it.
    #expect(!syncTransport.recordedPushBatches.contains { $0.contains { $0.id == attachment.id } },
            "a record whose commit failed must not push")
    // It stays dirty: the upload is retried later (S7), nothing is lost.
    #expect(try repo.fetchDirtyRows().contains { $0.id == attachment.id })

    // Recovery: the commit succeeds; the next cycle uploads and pushes.
    blobTransport.setCommitError(nil)
    _ = await engine.synchronize()
    #expect(syncTransport.recordedPushBatches.contains { $0.contains { $0.id == attachment.id } })
    #expect(try repo.fetchDirtyRows().isEmpty)
}

// MARK: - Dedupe: exists skips the PUT

@Test func dedupeSkipsThePutEntirely() async throws {
    let repo = try makeSyncRepository()
    let rendition = Data("rendition-bytes".utf8)
    let sha256 = BlobHash.sha256(rendition)

    // Default `beginResult` is `.exists` - another device already uploaded it.
    let blobTransport = BlobTransportDouble()
    let gate = LocalFileBlobPushGate(
        uploader: BlobUploader(transport: blobTransport),
        source: FixedBlobSource(data: rendition))
    let syncTransport = SyncTransportDouble()
    let engine = makeSyncEngine(repository: repo, transport: syncTransport, blobGate: gate)

    let attachment = makeSyncAttachment(sha256: sha256)
    try repo.upsertAttachment(attachment)

    _ = await engine.synchronize()

    // The PUT was NEVER issued - not merely that the flow completed.
    #expect(blobTransport.putRequestCount == 0, "a begin answering 'exists' must never PUT")
    #expect(blobTransport.commitCount == 0, "no commit either - the blob is already committed")
    // The record still pushed.
    #expect(syncTransport.recordedPushBatches.contains { $0.contains { $0.id == attachment.id } })
}

// MARK: - Rendition caps

@Test func renditionCapsAndPdfPassThrough() throws {
    // A 4000px image comes out <= 2048 on its long edge.
    let big = jpegData(width: 4000, height: 3000)
    let (rendition, contentType) = try AttachmentRendition.rendition(for: big, kind: .photo)
    let (bigWidth, bigHeight) = longEdge(of: rendition)
    #expect(max(bigWidth, bigHeight) <= 2048,
            "a 4000px image must come out <= 2048 on its long edge, got \(max(bigWidth, bigHeight))")
    #expect(contentType == "image/jpeg")

    // A 1200px image is NOT upscaled.
    let small = jpegData(width: 1200, height: 800)
    let (smallRendition, _) = try AttachmentRendition.rendition(for: small, kind: .photo)
    let (sw, sh) = longEdge(of: smallRendition)
    #expect(max(sw, sh) == 1200, "a 1200px image must not be upscaled, got \(max(sw, sh))")

    // A PDF passes through byte-identical.
    let pdf = Data("PDF-content".utf8)
    let (pdfRendition, pdfContentType) = try AttachmentRendition.rendition(for: pdf, kind: .pdf)
    #expect(pdfRendition == pdf, "a PDF must pass through byte-identical")
    #expect(pdfContentType == "application/pdf")

    // An 11 MB PDF is refused.
    let bigPDF = Data(repeating: 0, count: 11 * 1024 * 1024)
    do {
        _ = try AttachmentRendition.rendition(for: bigPDF, kind: .pdf)
        Issue.record("an 11 MB PDF must be refused")
    } catch let error as AttachmentRendition.Error {
        #expect(error == .pdfTooLarge)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

// MARK: - The inline thumbnail

@Test func pullCarriesTheThumbnailInThePayloadAndFetchesNoBlobs() async throws {
    let repo = try makeSyncRepository()
    let rendition = Data("rendition".utf8)
    let sha256 = BlobHash.sha256(rendition)
    let thumbnail = "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAA=="

    let attachment = makeSyncAttachment(sha256: sha256, thumbnailBase64: thumbnail)

    let blobTransport = BlobTransportDouble()
    let syncTransport = SyncTransportDouble()
    syncTransport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(attachment, scn: 1)], nextSince: 1, more: false, schemaPolicy: policy))
    let engine = makeSyncEngine(
        repository: repo, transport: syncTransport,
        blobGate: LocalFileBlobPushGate(
            uploader: BlobUploader(transport: blobTransport),
            source: FixedBlobSource(data: nil)))

    _ = await engine.synchronize()

    // A list renders from the record payload alone: zero blob fetches.
    #expect(blobTransport.downloadCount == 0, "a pull must fetch no blobs - the thumbnail rides in the payload")
    let stored = try repo.liveAttachments().first { $0.id == attachment.id }
    #expect(stored?.thumbnailBase64 == thumbnail, "the thumbnail must arrive inside the record payload")
}

// MARK: - Verify-on-download (the corrupt case, not just the happy one)

@Test func downloadVerificationDiscardsCorruptBytes() async throws {
    let transport = BlobTransportDouble()
    let store = InMemoryBlobStore()
    let fetcher = LazyBlobFetcher(transport: transport, store: store)

    let correctBytes = Data("correct-rendition".utf8)
    let sha256 = BlobHash.sha256(correctBytes)

    // The transport hands back bytes that do NOT hash to the requested sha256.
    transport.setDownloadResult(Data("tampered-bytes".utf8))

    do {
        _ = try await fetcher.fetch(sha256: sha256)
        Issue.record("a corrupt download must not be returned")
    } catch let error as BlobSyncError {
        #expect(error == .hashMismatch, "mismatched bytes must be discarded")
    } catch {
        Issue.record("unexpected error: \(error)")
    }

    // Not cached, so it is never displayed from cache.
    #expect(try store.data(for: sha256) == nil, "corrupt bytes must never be cached")
    #expect(transport.downloadCount == 1)
}

// MARK: - Lazy download + cache forever after

@Test func lazyFetchDownloadsExactlyOnceAndCachesForeverAfter() async throws {
    let transport = BlobTransportDouble()
    let store = InMemoryBlobStore()
    let fetcher = LazyBlobFetcher(transport: transport, store: store)

    let correctBytes = Data("correct-rendition".utf8)
    let sha256 = BlobHash.sha256(correctBytes)
    transport.setDownloadResult(correctBytes)

    let first = try await fetcher.fetch(sha256: sha256)
    #expect(first == correctBytes)
    #expect(transport.downloadCount == 1, "opening the entry fetches exactly one blob")

    // A second fetch is a cache hit - content addressing means no revalidation,
    // ever (docs/SYNC.md -> Delivery).
    let second = try await fetcher.fetch(sha256: sha256)
    #expect(second == correctBytes)
    #expect(transport.downloadCount == 1, "a cached blob is never re-fetched")
    #expect(try store.data(for: sha256) == correctBytes)
}

// MARK: - Offline (S7): text-first, blob pending

@Test func offlineSyncsTheEntryTextFirstWithTheBlobPending() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let rendition = Data("rendition".utf8)
    let sha256 = BlobHash.sha256(rendition)
    let attachment = makeSyncAttachment(sha256: sha256)
    try repo.upsertAttachment(attachment)

    let fillUp = makeSyncFillUp(vehicleId: vehicleId)
    try repo.upsertFillUp(fillUp)

    // The blob transport is down (begin fails) - S7.
    let blobTransport = BlobTransportDouble()
    blobTransport.setBeginError(.transportUnavailable)
    let gate = LocalFileBlobPushGate(
        uploader: BlobUploader(transport: blobTransport),
        source: FixedBlobSource(data: rendition))
    let syncTransport = SyncTransportDouble()
    let engine = makeSyncEngine(repository: repo, transport: syncTransport, blobGate: gate)

    _ = await engine.synchronize()

    // The entry synced text-first...
    #expect(syncTransport.recordedPushBatches.contains { $0.contains { $0.id == fillUp.id } },
            "the entry must sync text-first")
    // ...with the blob pending - nothing lost, nothing blocked.
    #expect(try repo.fetchDirtyRows().contains { $0.id == attachment.id },
            "the attachment stays pending until its blob lands")
    // The app is fully usable: entry and attachment are both live locally.
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 1)
    #expect(try repo.liveAttachments().count == 1)
}

// MARK: - Image helpers

private func jpegData(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func longEdge(of jpeg: Data) -> (width: Int, height: Int) {
    let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
    return (width, height)
}
