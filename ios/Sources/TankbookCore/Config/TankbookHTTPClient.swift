import Foundation

/// Supplies the auth token for an outgoing request (docs/SECURITY.md -> "The
/// auth token is bound to the host, not to the session").
///
/// The client calls this **only after** an allowlist check has passed, so the
/// token value is never requested for a host the app must not talk to. The real
/// provider reads the Keychain; this type keeps the Keychain out of the client.
public protocol AuthorizationTokenProvider: Sendable {
    func token() -> String?
}

/// Executes a single HTTP request. The client depends on this seam rather than
/// on `URLSession` so every behaviour is testable in a plain `swift test`
/// process with no sockets (docs/TESTING.md). The real `URLSession`-backed
/// implementation lands with the sync work.
public protocol TankbookHTTPTransport: Sendable {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse
}

/// An outgoing request as the client hands it to the transport. `headers` are
/// case-sensitive; the client writes `Authorization` and reads `Location`.
public struct TankbookHTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// A response as the transport returns it.
public struct TankbookHTTPResponse: Sendable, Equatable {
    public var status: Int
    public var url: URL?
    public var headers: [String: String]
    public var body: Data?

    public init(status: Int, url: URL? = nil, headers: [String: String] = [:], body: Data? = nil) {
        self.status = status
        self.url = url
        self.headers = headers
        self.body = body
    }

    public func value(forHeader name: String) -> String? {
        if let value = headers[name] { return value }
        for (key, value) in headers where key.lowercased() == name.lowercased() {
            return value
        }
        return nil
    }
}

/// Errors surfaced by `TankbookHTTPClient`.
public enum TankbookHTTPClientError: Error, Sendable, Equatable {
    /// The request host is not on the allowlist. Raised before any I/O and
    /// before the token provider is consulted (docs/SECURITY.md -> "the request
    /// simply goes out unauthenticated" is the redirect case; here the request
    /// does not go out at all).
    case hostNotAllowlisted
    /// A redirect chain exceeded `maxRedirects`.
    case tooManyRedirects
}

/// The host-bound HTTP client: the **second**, independent checkpoint
/// (docs/SECURITY.md -> "Defence in depth"). Config validation and this client
/// enforce the same allowlist, so a bypass of one still cannot reach an
/// attacker's host or leak the token.
///
/// Two rules make the token safe:
///
/// 1. **Enforce the allowlist at request time**, on every request, before any
///    I/O. A request to a non-allowlisted host throws without touching the
///    transport or the token provider.
/// 2. **Build `Authorization` only for allowlisted hosts.** The header string is
///    constructed inside `authorizing`, which runs its own allowlist check, so
///    the token value is never even fetched for a non-allowlisted host - not
///    built-then-dropped, not built-then-refused. Redirects re-run the check,
///    so a 3xx to a foreign host carries no token.
public struct TankbookHTTPClient: Sendable {
    private let transport: any TankbookHTTPTransport
    private let tokenProvider: any AuthorizationTokenProvider
    private let refresher: (any SessionRefreshing)?
    private let maxRedirects: Int

    public init(
        transport: any TankbookHTTPTransport,
        tokenProvider: any AuthorizationTokenProvider,
        refresher: (any SessionRefreshing)? = nil,
        maxRedirects: Int = 10
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.refresher = refresher
        self.maxRedirects = maxRedirects
    }

    /// Sends a request, following redirects while re-checking the allowlist at
    /// every hop. A request to a non-allowlisted host is refused before any I/O.
    ///
    /// A `401` is an auth event, not a gate from a newer server (PR.1): when a
    /// refresher is wired, the client refreshes once and replays the request
    /// with the rotated bearer; a failed refresh propagates as
    /// `SessionRefresherError`, so no transport ever maps a 401 to an
    /// "update the app" refusal again.
    public func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard HostAllowlist.allows(url: request.url) else {
            throw TankbookHTTPClientError.hostNotAllowlisted
        }
        var response = try await follow(request, remainingRedirects: maxRedirects, overrideToken: nil)
        if response.status == 401, let refresher {
            let token = try await refresher.refresh()
            response = try await follow(request, remainingRedirects: maxRedirects, overrideToken: token)
        }
        return response
    }

    /// Executes one hop, then follows a redirect if present and allowed.
    /// `overrideToken` carries a freshly rotated bearer through the replay; when
    /// nil the token is read from the provider as usual.
    private func follow(_ request: TankbookHTTPRequest,
                        remainingRedirects: Int,
                        overrideToken: String?) async throws -> TankbookHTTPResponse {
        let response = try await transport.execute(authorizing(request, overrideToken: overrideToken))

        guard isRedirect(response.status) else { return response }
        guard remainingRedirects > 0 else { throw TankbookHTTPClientError.tooManyRedirects }
        guard let location = response.value(forHeader: "Location"),
              let nextURL = URL(string: location, relativeTo: request.url)?.absoluteURL else {
            return response
        }

        // Re-run the allowlist check for the redirect target. `authorizing`
        // strips `Authorization` whenever the new host is not allowed, so the
        // token never travels to a host it was not bound to.
        var next = TankbookHTTPRequest(url: nextURL, method: request.method, headers: request.headers)
        next.headers.removeValue(forKey: "Authorization")
        return try await follow(next, remainingRedirects: remainingRedirects - 1,
                                overrideToken: overrideToken)
    }

    /// Returns a copy of `request` with `Authorization` attached **only** when
    /// the request host is allowlisted. This is the single point where the
    /// header string is constructed, and it never runs for a non-allowlisted
    /// host. `overrideToken` (the post-refresh replay) wins over the provider
    /// so the replay carries the rotated bearer even when the provider has not
    /// re-read it yet.
    private func authorizing(_ request: TankbookHTTPRequest,
                             overrideToken: String?) -> TankbookHTTPRequest {
        var out = request
        guard HostAllowlist.allows(url: request.url) else { return out }
        if let overrideToken {
            out.headers["Authorization"] = "Bearer \(overrideToken)"
        } else if let token = tokenProvider.token() {
            out.headers["Authorization"] = "Bearer \(token)"
        }
        return out
    }

    private func isRedirect(_ status: Int) -> Bool {
        (300...399).contains(status)
    }
}
