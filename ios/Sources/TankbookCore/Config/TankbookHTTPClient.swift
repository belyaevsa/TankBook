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
    /// Per-request read timeout in seconds. nil inherits the session default
    /// (`TransportTimeouts.readJSON`). The long paths (blob PUT, import multipart)
    /// set `TransportTimeouts.upload` explicitly rather than every call inheriting
    /// the longest budget.
    public var timeoutInterval: TimeInterval?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:],
                body: Data? = nil, timeoutInterval: TimeInterval? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
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

/// The app identity every request announces (docs/API.md -> "Request headers",
/// PR.8): the marketing version + build, the platform, and the payload schema
/// version the client speaks. Built from the bundle by `current`; tests inject
/// a fixed value because a plain `swift test` process has no Info.plist.
public struct TankbookAppInfo: Sendable, Equatable {
    public let version: AppVersion
    public let build: String
    public let platform: String
    public let schemaVersion: Int

    public init(version: AppVersion, build: String, platform: String = "ios",
                schemaVersion: Int = PayloadCodec.currentSchemaVersion) {
        self.version = version
        self.build = build
        self.platform = platform
        self.schemaVersion = schemaVersion
    }

    /// The `X-Tankbook-App` value: `<version>+<build>` (docs/API.md).
    public var appHeader: String {
        "\(version)+\(build)"
    }

    /// The `X-Tankbook-Schema-Version` value.
    public var schemaVersionHeader: String {
        String(schemaVersion)
    }

    /// Reads the running bundle; nil when there is none (a plain `swift test`
    /// process), in which case the client omits the app headers rather than
    /// announcing a guessed version.
    public static func current(bundle: Bundle = .main) -> TankbookAppInfo? {
        guard let version = AppVersion(bundle: bundle),
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else { return nil }
        return TankbookAppInfo(version: version, build: build)
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
    /// The server answered with a non-2xx, non-304 status. `traceId` is read
    /// from the problem+json body so a support report maps to the exact server
    /// line (docs/LOGGING.md §2); `retryAfterSeconds` comes from the Retry-After
    /// header so a 429 keeps the server's own wait. Owners translate this into
    /// their own errors - a real response, never a transport failure.
    case httpError(status: Int, traceId: String?, retryAfterSeconds: Int?)
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
    /// The app identity announced on every request (PR.8). nil only in a
    /// process without a bundle (a plain `swift test`), where the app headers
    /// are omitted; the trace header is always sent.
    private let appInfo: TankbookAppInfo?

    public init(
        transport: any TankbookHTTPTransport,
        tokenProvider: any AuthorizationTokenProvider,
        refresher: (any SessionRefreshing)? = nil,
        maxRedirects: Int = 10,
        appInfo: TankbookAppInfo? = TankbookAppInfo.current()
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.refresher = refresher
        self.maxRedirects = maxRedirects
        self.appInfo = appInfo
    }

    /// Sends a request, following redirects while re-checking the allowlist at
    /// every hop. A request to a non-allowlisted host is refused before any I/O.
    ///
    /// Every outgoing request is stamped with a fresh `X-Tankbook-Trace`
    /// (UUIDv7) plus the app headers at this chokepoint, so no caller - auth,
    /// sync, blobs, import, feedback, the gateway - can miss them (PR.8; the
    /// PR.3b lesson: one transport outside the fence ships unconverted).
    ///
    /// A `401` is an auth event, not a gate from a newer server (PR.1): when a
    /// refresher is wired, the client refreshes once and replays the request
    /// with the rotated bearer; a failed refresh propagates as
    /// `SessionRefresherError`, so no transport ever maps a 401 to an
    /// "update the app" refusal again.
    ///
    /// **RV.65: the replay happens only when the bearer actually changed.** The
    /// whole request - body included - is re-sent on a replay, and for `/extract`
    /// or `/blobs` that body is the upload this row exists to protect. A refresh
    /// that hands back the SAME token value has changed nothing: the server
    /// already rejected exactly this bearer, so a replay would re-send the
    /// payload for a guaranteed second 401. "Unchanged" is decided by comparing
    /// the token the rejected request carried (read from the provider once, at
    /// send time, and threaded through as the override so the wire value is
    /// exactly what is compared) against the refresher's result - equality means
    /// nothing to retry, so the 401 is treated as final. A genuine rotation
    /// (token value differs) still replays exactly once.
    ///
    /// A final non-2xx, non-304 response is thrown as
    /// `TankbookHTTPClientError.httpError` carrying the status and the `traceId`
    /// read from the problem+json body - the client is the only layer that sees
    /// the raw body, so it reads the trace id here, once, for every owner.
    public func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard HostAllowlist.allows(url: request.url) else {
            throw TankbookHTTPClientError.hostNotAllowlisted
        }
        var traced = request
        attachHeaders(&traced)
        // RV.65: capture the bearer THIS request goes out under, and pass it as
        // the override so every hop of the original request carries exactly the
        // value we compare against - never a re-read that a concurrent refresh
        // could have rotated between the check and the wire.
        let sentBearer = tokenProvider.token()
        var response = try await follow(traced, remainingRedirects: maxRedirects,
                                        overrideToken: sentBearer)
        if response.status == 401, let refresher {
            let token = try await refresher.refresh()
            if token != sentBearer {
                response = try await follow(traced, remainingRedirects: maxRedirects,
                                            overrideToken: token)
            }
        }
        guard Self.isError(response.status) else { return response }
        throw TankbookHTTPClientError.httpError(
            status: response.status,
            traceId: Self.traceId(fromBody: response.body),
            retryAfterSeconds: response.value(forHeader: "Retry-After").flatMap(Int.init)
        )
    }

    /// Executes one hop, then follows a redirect if present and allowed.
    /// `overrideToken` is the bearer every hop of this logical request carries -
    /// for the original send it is the provider value captured up front (RV.65,
    /// so the 401 replay compares against exactly what the server rejected), and
    /// for a replay it is the freshly rotated bearer. When nil the token is read
    /// from the provider as usual (a request that set no bearer).
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

    /// Stamps the trace and app headers onto the request. The trace id is one
    /// UUIDv7 per `send` call, so the whole chain - redirects and a 401 replay -
    /// is one logical request to support, and two calls never share an id.
    private func attachHeaders(_ request: inout TankbookHTTPRequest) {
        request.headers["X-Tankbook-Trace"] = UUID.uuidV7().uuidString.lowercased()
        guard let appInfo else { return }
        request.headers["X-Tankbook-App"] = appInfo.appHeader
        request.headers["X-Tankbook-Platform"] = appInfo.platform
        request.headers["X-Tankbook-Schema-Version"] = appInfo.schemaVersionHeader
    }

    /// True for a status that is neither a 2xx success nor a 304 "not modified"
    /// (a legitimate outcome for config/catalog fetches that must not throw).
    private static func isError(_ status: Int) -> Bool {
        !(200...299).contains(status) && status != 304
    }

    /// Reads `traceId` from a problem+json body (docs/API.md conventions); nil
    /// when the body is absent, not JSON, or carries no traceId.
    private static func traceId(fromBody body: Data?) -> String? {
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let value = object["traceId"] as? String, !value.isEmpty else { return nil }
        return value
    }

    private func isRedirect(_ status: Int) -> Bool {
        (300...399).contains(status)
    }
}

extension UUID {
    /// A version-7 (time-ordered) UUID: its leading 48 bits are the Unix
    /// millisecond timestamp, so ids sort by creation and the server can read
    /// them without a lookup table (docs/LOGGING.md §2: `X-Tankbook-Trace` is
    /// a UUIDv7).
    static func uuidV7() -> UUID {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        bytes[0] = UInt8((timestamp >> 40) & 0xFF)
        bytes[1] = UInt8((timestamp >> 32) & 0xFF)
        bytes[2] = UInt8((timestamp >> 24) & 0xFF)
        bytes[3] = UInt8((timestamp >> 16) & 0xFF)
        bytes[4] = UInt8((timestamp >> 8) & 0xFF)
        bytes[5] = UInt8(timestamp & 0xFF)
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
            bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
