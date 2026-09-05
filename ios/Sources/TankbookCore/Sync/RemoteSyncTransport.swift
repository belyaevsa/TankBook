import Foundation

/// The production `SyncTransport`: the two sync endpoints over HTTP, through the
/// host-bound `TankbookHTTPClient` so the bearer token and allowlist rules
/// (docs/SECURITY.md) apply exactly as they do for auth. Payloads are encoded
/// and decoded as `JSONValue` trees - the same lossless representation the
/// payload contract uses - with dates as ISO-8601 UTC strings (docs/API.md
/// conventions).
public struct RemoteSyncTransport: SyncTransport {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider,
                refresher: (any SessionRefreshing)? = nil) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider,
                                         refresher: refresher)
        self.director = director
    }

    public func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        var components = URLComponents(
            url: endpoint("sync/pull"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else {
            throw SyncServerError.invalidResponse
        }
        let request = TankbookHTTPRequest(url: url, method: "GET")
        let response = try await send(request)
        return try decodePull(response.body)
    }

    public func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        let body = try encodePush(changes)
        var request = TankbookHTTPRequest(url: endpoint("sync/push"), method: "POST", body: body)
        request.headers["Content-Type"] = "application/json"
        let response = try await send(request)
        return try decodePush(response.body)
    }

    // MARK: - HTTP

    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        do {
            let response = try await client.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch SessionRefresherError.authExpired {
            // The host answered - the 401 that triggered the refresh, then the
            // refresh's own non-2xx. The session is gone; the base URL is fine,
            // so this is a response, never evidence the URL is wrong.
            await director.report(.response(status: 401))
            throw SyncServerError.authExpired
        } catch TankbookHTTPClientError.httpError(let status, let code, _, let retryAfterSeconds) {
            // The host answered with a non-2xx sync status - a response, never
            // a transport failure - mapped by its code when the server named
            // one, else per status below.
            await director.report(.response(status: status))
            throw Self.error(for: status, retryAfterSeconds: retryAfterSeconds, code: ServerErrorCode(raw: code))
        } catch {
            // hostNotAllowlisted, tooManyRedirects, a transport error, or a
            // refresh that could not reach the host: none of them is "the host
            // answered", so each counts toward auto-revert, and none is a 5xx -
            // the device is offline, not the server down.
            await director.report(.transportFailure)
            throw SyncServerError.offline
        }
    }

    /// Maps a non-2xx status (and, when the server named one, its `code`) to a
    /// `SyncServerError`. A code is trusted when it is one this surface
    /// understands; an unknown or absent code falls back to the status mapping,
    /// which is why a newer server's code can never be misread as a failure
    /// class this client would not have chosen itself (PR.9). A 401 is an auth
    /// event, never an unknown gate from a newer server (PR.1 - the honest next
    /// step is "sign in again", never "update the app").
    private static func error(for status: Int, retryAfterSeconds: Int?,
                              code: ServerErrorCode? = nil) -> SyncServerError {
        switch code {
        case .tokenInvalid: return .authExpired
        case .deviceRevoked: return .deviceRevoked
        case .upgradeRequired: return .upgradeRequired
        case .tierRefused: return .tierRefused
        case .rateLimited: return .rateLimited(retryAfterSeconds: retryAfterSeconds)
        default: break
        }
        switch status {
        case 401:
            // Unreachable with a wired refresher (the client intercepts 401
            // first); without one, a 401 is still an auth event.
            return .authExpired
        case 410:
            return .deviceRevoked
        case 426:
            return .upgradeRequired
        case 402:
            return .tierRefused
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfterSeconds)
        case 400...499:
            // An unknown gate from a server newer than this client. Reported as
            // what it is - a refusal carrying its status - never as "could not
            // decode" and never as a generic failure (JOURNEYS F7).
            return .refused(status: status)
        default:
            // 5xx and anything non-HTTP-shaped: the host answered, so the
            // device is online and the service is down - S7 - rows return to
            // dirty and the cycle retries.
            return .serverUnavailable
        }
    }

    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    // MARK: - Encoding

    private func encodePush(_ changes: [SyncPushChange]) throws -> Data {
        let items: [JSONValue] = changes.map { change in
            .object([
                "id": .string(change.id.uuidString),
                "entityType": .string(change.entityType),
                "schemaVersion": .number(String(change.schemaVersion)),
                "baseScn": .number(String(change.baseScn)),
                "payload": change.payload,
                "clientUpdatedAt": .string(PayloadFormat.dateString(change.clientUpdatedAt)),
                "deleted": .bool(change.deleted),
            ])
        }
        return try JSONValue.object(["changes": .array(items)]).jsonData()
    }

    // MARK: - Decoding

    private func decodePull(_ data: Data?) throws -> SyncPullResponse {
        guard let data else { throw SyncServerError.invalidResponse }
        let tree = try JSONValue.parse(data)
        guard let object = tree.objectValue else { throw SyncServerError.invalidResponse }

        let records = (object["records"]?.arrayValue ?? []).compactMap(decodePullRecord)
        guard let nextSince = object["nextSince"]?.int64Value,
              let more = object["more"]?.boolValue else {
            throw SyncServerError.invalidResponse
        }
        let policyObject = object["schemaPolicy"]?.objectValue
        let policy = SyncSchemaPolicy(
            minSupported: policyObject?["minSupported"]?.intValue ?? 0,
            current: policyObject?["current"]?.intValue ?? 1
        )
        return SyncPullResponse(records: records, nextSince: nextSince, more: more, schemaPolicy: policy)
    }

    private func decodePullRecord(_ value: JSONValue) -> SyncPullRecord? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let entityType = object["entityType"]?.stringValue,
              let schemaVersion = object["schemaVersion"]?.intValue,
              let scn = object["scn"]?.int64Value,
              let payload = object["payload"],
              let rawUpdated = object["clientUpdatedAt"]?.stringValue,
              let clientUpdatedAt = PayloadFormat.date(from: rawUpdated) else {
            return nil
        }
        return SyncPullRecord(
            id: id,
            entityType: entityType,
            schemaVersion: schemaVersion,
            scn: scn,
            payload: payload,
            clientUpdatedAt: clientUpdatedAt,
            deleted: object["deleted"]?.boolValue ?? false,
            originDeviceName: object["originDeviceName"]?.stringValue
        )
    }

    private func decodePush(_ data: Data?) throws -> SyncPushResponse {
        guard let data else { throw SyncServerError.invalidResponse }
        let tree = try JSONValue.parse(data)
        guard let object = tree.objectValue, let results = object["results"]?.arrayValue else {
            throw SyncServerError.invalidResponse
        }
        let decoded: [SyncPushResult] = results.compactMap { value in
            guard let resultObject = value.objectValue,
                  let id = resultObject["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let status = resultObject["status"]?.stringValue else {
                return nil
            }
            switch status {
            case "accepted":
                return SyncPushResult(id: id, status: .accepted(
                    newScn: resultObject["newScn"]?.int64Value ?? 0,
                    clamped: resultObject["clamped"]?.boolValue ?? false))
            case "conflict":
                guard let current = resultObject["current"].flatMap(decodePullRecord) else { return nil }
                return SyncPushResult(id: id, status: .conflict(current: current))
            case "rejected":
                return SyncPushResult(id: id, status: .rejected(
                    code: resultObject["error"]?.stringValue ?? "rejected",
                    pointer: resultObject["pointer"]?.stringValue))
            default:
                return nil
            }
        }
        return SyncPushResponse(results: decoded)
    }
}

extension JSONValue {
    var intValue: Int? {
        if case .number(let token) = self { return Int(token) }
        return nil
    }

    var int64Value: Int64? {
        if case .number(let token) = self { return Int64(token) }
        return nil
    }
}
