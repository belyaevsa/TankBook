#if DEBUG
import Foundation
import TankbookCore

/// RV.17's slow-fetch seam for the attachment viewer: a `BlobTransport` that
/// sleeps a deliberate delay and returns the SAME JPEG the `-seedPhotoRemote`
/// seed hashes into the attachment's `file.sha256`, so `LazyBlobFetcher`'s
/// verify-on-download passes and the viewer resolves to the full rendition
/// rather than a failure. Without a slow transport the `.fetching` state is
/// unobservable from a UI test - the fetch is either instant (a cache hit) or
/// the seeded launch is offline (an instant failure), and a progress test that
/// passes because the fetch was instant proves nothing (the RV.8 trap).
///
/// Armed by `-seedBlobFetchDelay <seconds>`; only `download` matters to the
/// viewer, the write methods are no-ops so the seed can never cause an upload.
struct SeededBlobTransport: BlobTransport {
    let delay: Duration

    func begin(sha256: String, size: Int, contentType: String) async throws -> BlobBeginResult {
        .exists
    }

    func put(_ data: Data, to url: URL, contentType: String) async throws {}

    func commit(sha256: String) async throws {}

    func download(sha256: String) async throws -> Data {
        try await Task.sleep(for: delay)
        return PhotoSyncingTestSeed.remoteRendition
    }

    static func from(arguments: [String] = ProcessInfo.processInfo.arguments) -> SeededBlobTransport? {
        guard let index = arguments.firstIndex(of: "-seedBlobFetchDelay"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else { return nil }
        return SeededBlobTransport(delay: .seconds(seconds))
    }
}
#endif
