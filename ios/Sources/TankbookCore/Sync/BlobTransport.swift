import Foundation

/// The network seam for the blob pipeline (docs/SYNC.md -> Attachments). The
/// production implementation is `RemoteBlobTransport`; tests use a recording
/// in-memory double - the same injected-protocol split as `SyncTransport`, so
/// the upload ordering and the verify-on-download rule are provable without a
/// server or sockets (docs/TESTING.md).
public protocol BlobTransport: Sendable {
    /// `POST /blobs/begin { sha256, size, contentType }` -> `.exists` (dedupe)
    /// or `.upload(url:presigned)`. Throws `BlobSyncError.sizeExceeded` (413) or
    /// `BlobSyncError.quotaExceeded` (429).
    func begin(sha256: String, size: Int, contentType: String) async throws -> BlobBeginResult
    /// PUTs the bytes directly to the presigned URL (docs/SYNC.md: bytes never
    /// proxied through the API server).
    func put(_ data: Data, to url: URL, contentType: String) async throws
    /// `POST /blobs/commit { sha256 }` - the server verifies object + size.
    func commit(sha256: String) async throws
    /// `GET /blobs/{sha256}` -> the blob bytes (the 302 to the presigned GET is
    /// the production transport's business).
    func download(sha256: String) async throws -> Data
}

/// The `POST /blobs/begin` outcome (docs/API.md).
public enum BlobBeginResult: Sendable, Equatable {
    /// Another device already uploaded this content - skip the PUT entirely.
    case exists
    /// Upload the bytes to the presigned `url` before committing.
    case upload(url: URL, expiresAt: Date?)
}

/// Failures surfaced by the blob pipeline. Raw HTTP outcomes mapped to meaning
/// (docs/API.md); none carries a payload value (hard rule 12).
public enum BlobSyncError: Error, Equatable, Sendable {
    /// `413`: the rendition exceeds the server's per-type cap.
    case sizeExceeded
    /// `429`: the account's storage quota is exhausted.
    case quotaExceeded
    /// `404`: the blob is not owned by this account.
    case notFound
    /// Download verification: the fetched bytes did not hash to the requested
    /// sha256. The bytes are discarded - never cached, never displayed.
    case hashMismatch
    /// The host could not be reached or was refused.
    case transportUnavailable
    /// The access token expired and the refresh failed (PR.1): an auth event,
    /// never an undecodable body and never an unknown gate.
    case authExpired
    /// The server answered but the body could not be decoded.
    case invalidResponse
}
