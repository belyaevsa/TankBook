import Foundation

/// A `URLSession`-backed `TankbookHTTPTransport`. The real transport for the
/// auth service; the sync client (P4.5) reuses it for its own endpoints rather
/// than owning its own socket plumbing.
///
/// The transport builds its **own** `URLSession` from `TransportTimeouts`
/// (docs/PRACTICES.md U6): the shared session's 60 s default is the frozen-button
/// bug this type exists to remove. The configuration is injectable so tests can
/// drive a stalling session and a tiny timeout without a real wall-clock wait.
public struct URLSessionTransport: TankbookHTTPTransport {
    public enum TransportError: Error, Equatable {
        case notHTTP
    }

    /// The session the transport runs requests on. Exposed so the L1 test can
    /// assert the configuration equals the named budgets, not merely that a
    /// configuration exists.
    public let session: URLSession
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = TransportTimeouts.defaultConfiguration()) {
        self.configuration = configuration
        self.session = URLSession(configuration: configuration)
    }

    public func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body
        // Always set the read budget explicitly. `URLRequest.timeoutInterval`
        // carries its own 60 s default that would otherwise shadow the session's
        // configured `timeoutIntervalForRequest` (the well-known URLSession
        // gotcha). The long paths (blob PUT, import multipart) ask for
        // `TransportTimeouts.upload` via the per-request override; everything
        // else takes the session's `TransportTimeouts.readJSON` budget.
        urlRequest.timeoutInterval = request.timeoutInterval ?? configuration.timeoutIntervalForRequest

        let data: Data
        let response: URLResponse
        if let handler = UploadProgress.handler, let body = request.body {
            // An upload task reports bytes as they leave the device; a data task does not.
            urlRequest.httpBody = nil
            (data, response) = try await session.upload(for: urlRequest, from: body,
                                                        delegate: UploadProgressDelegate(handler: handler))
        } else {
            (data, response) = try await session.data(for: urlRequest)
        }
        guard let http = response as? HTTPURLResponse else { throw TransportError.notHTTP }

        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            headers[String(describing: name)] = String(describing: value)
        }
        return TankbookHTTPResponse(
            status: http.statusCode,
            url: response.url,
            headers: headers,
            body: data
        )
    }
}

/// A request's upload progress, for the one caller that shows it (the debug case
/// send). Task-local, so it reaches the transport through every layer between -
/// the client's redirects, the token refresh, the logging wrapper - without each
/// of them carrying a callback. Reports the bytes of the request body sent so far.
public enum UploadProgress {
    @TaskLocal public static var handler: (@Sendable (Int64) -> Void)?
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let handler: @Sendable (Int64) -> Void

    init(handler: @escaping @Sendable (Int64) -> Void) {
        self.handler = handler
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        handler(totalBytesSent)
    }
}
