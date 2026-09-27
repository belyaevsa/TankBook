import Foundation
import os

// MARK: - Net request/response observability (OB.2, RV.59, RV.65)

/// Wraps any `TankbookHTTPTransport` and emits one `net.request` before each
/// physical request and one `net.response` after it (docs/LOGGING.md §4).
///
/// This is the seam that would have shown RV.59's duplicate config fetch and
/// RV.65's doubled 53 KB upload from the device side: because the decorator
/// wraps the transport, every request that flows through the app - auth, sync,
/// blobs (including the presigned PUT), import, feedback, the LLM gateway -
/// is observable no matter which `TankbookHTTPClient` owner built it, and every
/// redirect hop / 401 replay is a separate request/response pair, which is
/// exactly how a doubled upload reads in the log.
///
/// Privacy (hard rule 12): each line carries the endpoint's route **path**
/// (`/v1/sync/pull`, `/v1/blobs/<sha256>`) and the body's **byte count** -
/// never the host, never the query string (a presigned URL's signature and
/// expiry live there), never a header, and never a body value. The `traceId`
/// rides the request's own `X-Tankbook-Trace` header (set once per logical
/// request by `TankbookHTTPClient.send`), so every hop of one logical request
/// joins the same correlation id (docs/LOGGING.md §2). A request with no trace
/// header (the presigned PUT, which is sent without tracing) logs with no
/// traceId.
///
/// `attempt` counts how many times this exact path+method has already been
/// executed under the same trace id - the number a doubled-upload diagnosis
/// reads first. A request that fails in transport (a timeout, a cancellation,
/// no network, the app suspended mid-request) still gets its `net.response`:
/// `status` 0, the time it took, and a `TransportFailure` code, and the error
/// is rethrown unchanged.
public struct LoggingHTTPTransport: TankbookHTTPTransport, Sendable {
    private let inner: any TankbookHTTPTransport
    private let log: TankbookLog
    private let counter = OSAllocatedUnfairLock(initialState: [String: Int]())

    public init(inner: any TankbookHTTPTransport, log: TankbookLog) {
        self.inner = inner
        self.log = log
    }

    public func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let endpoint = request.url.path
        let method = request.method
        let trace = request.headers["X-Tankbook-Trace"]
        let traceId = trace.flatMap(UUID.init(uuidString:))
        let key = "\(trace ?? "untraced")|\(method) \(endpoint)"
        let attempt = counter.withLock { state in
            let next = (state[key] ?? 0) + 1
            state[key] = next
            return next
        }
        let requestBytes = request.body?.count ?? 0
        let startedAt = Date()

        log.emit(NetRequest(endpoint: endpoint, method: method, attempt: attempt,
                            requestBytes: requestBytes),
                 traceId: traceId)

        let response: TankbookHTTPResponse
        do {
            response = try await inner.execute(request)
        } catch {
            log.emit(NetResponse(
                endpoint: endpoint,
                status: 0,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                requestBytes: requestBytes,
                errorCode: TransportFailure(error).rawValue),
                traceId: traceId)
            throw error
        }

        // OB.3: on a failure the line carries the server's `code` member from
        // the problem+json body (docs/LOGGING.md §4 promises `errorCode`; the
        // decorator is the layer that still holds the raw body, so it reads it
        // here). ONLY the `code` member, only for an error status - never a
        // title, never a detail, never any other body value (hard rule 12),
        // and never for a success (a 200 body is user content, not an error).
        let errorCode: String?
        if response.status >= 400 {
            errorCode = TankbookHTTPClient.problemBodyMembers(fromBody: response.body).code
        } else {
            errorCode = nil
        }
        log.emit(NetResponse(
            endpoint: endpoint,
            status: response.status,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            requestBytes: requestBytes,
            responseBytes: response.body?.count ?? 0,
            retryAfter: response.value(forHeader: "Retry-After").flatMap(Int.init),
            errorCode: errorCode),
            traceId: traceId)
        return response
    }
}

/// Why a request got no HTTP response, as the closed set `net.response`'s
/// `errorCode` carries with `status` 0 (docs/LOGGING.md §4). A code, never the
/// error's description, which can carry a URL (hard rule 12).
public enum TransportFailure: String, Sendable {
    case timeout
    case cancelled
    case offline
    case unreachable
    case tls
    case transport

    public init(_ error: any Error) {
        if error is CancellationError { self = .cancelled; return }
        guard let urlError = error as? URLError else { self = .transport; return }
        switch urlError.code {
        case .timedOut: self = .timeout
        case .cancelled: self = .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            self = .unreachable
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            self = .tls
        default: self = .transport
        }
    }
}
