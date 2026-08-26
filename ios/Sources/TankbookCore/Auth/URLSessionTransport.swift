import Foundation

/// A `URLSession`-backed `TankbookHTTPTransport`. The real transport for the
/// auth service; the sync client (P4.5) reuses it for its own endpoints rather
/// than owning its own socket plumbing.
public struct URLSessionTransport: TankbookHTTPTransport {
    public enum TransportError: Error, Equatable {
        case notHTTP
    }

    public init() {}

    public func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
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
