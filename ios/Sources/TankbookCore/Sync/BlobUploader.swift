import Foundation

/// The upload chain (docs/SYNC.md -> Attachments, step 1-4): sha256 -> begin ->
/// [PUT unless `exists`] -> commit. The ordering here is the load-bearing
/// invariant - the referencing record may only push after `commit` returns, so a
/// record never points at a blob the server cannot serve. Pure orchestration
/// over the injected `BlobTransport`; no `URLSession`, no file I/O.
public struct BlobUploader: Sendable {
    public let transport: any BlobTransport

    public init(transport: any BlobTransport) {
        self.transport = transport
    }

    /// Uploads `data` under its `sha256` content address. `begin` answering
    /// `exists` (dedupe) skips the PUT entirely and returns without committing.
    public func upload(sha256: String, data: Data, contentType: String) async throws {
        switch try await transport.begin(sha256: sha256, size: data.count, contentType: contentType) {
        case .exists:
            return
        case .upload(let url, _):
            try await transport.put(data, to: url, contentType: contentType)
            try await transport.commit(sha256: sha256)
        }
    }
}
