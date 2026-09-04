import Foundation

// The account & devices API client (docs/API.md -> "Account & devices"). Like
// sync and import, everything goes through `TankbookHTTPClient`, so the host
// allowlist and the host-bound Authorization apply here exactly as they do to
// the sync transport. The transport is injectable, so the client is testable in
// a plain `swift test` process with no sockets (docs/TESTING.md).

/// One registered device as served by `GET /account/devices` (docs/API.md).
/// `revoked` marks a device whose next pull will get 410; `lastSeenAt` is the
/// server's view of when the device last pulled. The name is server-supplied
/// runtime data - the UI must never place it where a preposition governs its
/// case in Russian (docs/LOCALIZATION.md - the P4.7 lesson).
public struct AccountDevice: Sendable, Equatable, Decodable {
    public let id: UUID
    public let name: String
    public let platform: String
    public let lastSeenAt: Date
    public let revoked: Bool

    public init(id: UUID, name: String, platform: String, lastSeenAt: Date, revoked: Bool) {
        self.id = id
        self.name = name
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.revoked = revoked
    }
}

extension Array where Element == AccountDevice {
    /// The number of devices that can still reach this account - the Settings
    /// account card's "· N device(s)" suffix (docs/SYNC.md -> The Settings sync
    /// surface). RV.54 (product owner, 2026-09-04): the count counts LIVE
    /// devices only, because the number answers "how many devices can reach my
    /// data", and a revoked device's next pull gets 410 - it cannot reach the
    /// data any more, so it does not count. Revoked rows are still returned by
    /// `GET /account/devices` and still shown in the Account & devices list:
    /// the counting excludes them, the list never does (the history is the point
    /// of showing them). Deliberately client-side - the endpoint keeps returning
    /// revoked rows marked, never omitted (docs/API.md -> Account & devices).
    public var liveDeviceCount: Int {
        filter { !$0.revoked }.count
    }
}

/// Errors the account client surfaces, each mapped from a specific wire status
/// (docs/API.md -> Account & devices, docs/ERRORS.md -> the screen's rows).
public enum AccountClientError: Error, Sendable, Equatable {
    /// The request could not reach the server (offline, DNS, timeout). Never an
    /// error a user can fix by doing anything other than being online again.
    case transportUnreachable
    /// The transport or host allowlist refused the request outright - a bug or
    /// a security violation, never the user's offline state.
    case client
    /// `401` - the bearer token is no longer accepted. The session is gone; the
    /// user signs in again. Local data is untouched (hard rule 1).
    case unauthorized
    /// `404` - the device (or account) does not belong to this session's
    /// account. Shown as the device having already been removed.
    case notFound
    /// Any other non-2xx.
    case server(status: Int)
    /// The response body was not the expected JSON.
    case invalidResponse
}

/// The host-bound client for `GET /account/devices`, `DELETE
/// /account/devices/{id}` and `DELETE /account`. Public so the app target can
/// build it over its own transport and session store; the methods are the three
/// the Account & devices screen needs and nothing else.
public struct AccountClient: Sendable {
    public let httpClient: TankbookHTTPClient
    public let director: ConfigTransportDirector
    /// ISO-8601 decoder that accepts the server's `DateTimeOffset` serialization
    /// (round-trip `O` format, offset and fractional seconds) and the plain UTC
    /// forms. A device list must decode on any server version.
    private let decoder: JSONDecoder

    public init(httpClient: TankbookHTTPClient, director: ConfigTransportDirector) {
        self.httpClient = httpClient
        self.director = director
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISO8601WithOffset)
        self.decoder = decoder
    }

    /// `GET /account/devices` - the manage-devices list. Revoked devices are
    /// returned marked, never omitted, so the screen can show what happened.
    public func devices() async throws -> [AccountDevice] {
        let url = endpoint("account/devices")
        let response = try await send(TankbookHTTPRequest(url: url))
        guard let body = response.body else { throw AccountClientError.invalidResponse }
        do {
            let payload = try decoder.decode(DevicesPayload.self, from: body)
            return payload.devices
        } catch {
            throw AccountClientError.invalidResponse
        }
    }

    /// `DELETE /account/devices/{id}` - revokes one device. Its next pull gets
    /// 410; its local data stays on it (the tombstone rule applies to devices
    /// too - revoke stops syncing, it erases nothing).
    public func revoke(deviceID: UUID) async throws {
        let url = endpoint("account/devices/\(deviceID.uuidString.lowercased())")
        _ = try await send(TankbookHTTPRequest(url: url, method: "DELETE"))
    }

    /// `DELETE /account` - tombstones the account. The server purges its copy
    /// after the grace period; every device's pull gets 410; **the local log on
    /// this phone is untouched** (docs/SYNC.md, site/delete-account.md).
    public func deleteAccount() async throws {
        let url = endpoint("account")
        _ = try await send(TankbookHTTPRequest(url: url, method: "DELETE"))
    }

    // MARK: - Plumbing

    /// All account endpoints live under `/v1` (docs/API.md -> "Account &
    /// devices"; backend `Program.cs`: `app.MapGroup("/v1")`).
    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        do {
            let response = try await httpClient.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch SessionRefresherError.authExpired {
            // The host answered (401, then a failed refresh). Session gone,
            // base URL fine - a response, never evidence the URL is wrong.
            await director.report(.response(status: 401))
            throw AccountClientError.unauthorized
        } catch TankbookHTTPClientError.httpError(let status, _, _) {
            // The host answered with a non-2xx account status - a response,
            // never a transport failure - mapped per status below.
            await director.report(.response(status: status))
            throw Self.error(for: status)
        } catch is TankbookHTTPClientError {
            // Host-not-allowlisted / redirect loop: a real client bug or a
            // security violation, never an offline state.
            await director.report(.transportFailure)
            throw AccountClientError.client
        } catch {
            await director.report(.transportFailure)
            throw AccountClientError.transportUnreachable
        }
    }

    static func error(for status: Int) -> AccountClientError {
        switch status {
        case 401: return .unauthorized
        case 404: return .notFound
        default: return .server(status: status)
        }
    }

    private struct DevicesPayload: Decodable {
        let devices: [AccountDevice]
    }

    /// Decodes the server's ISO-8601 timestamps. System.Text.Json serializes a
    /// `DateTimeOffset` round-trip: `2026-08-28T10:30:00.0000000+02:00`; other
    /// paths may produce `...Z` with 0 or 3 fractional digits. Normalises a
    /// fraction longer than three digits down to three (the formatters accept
    /// only three), then tries the fractional-second and plain internet-date
    /// forms, so a schema evolution cannot blank a `lastSeenAt`.
    private static func decodeISO8601WithOffset(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let normalized = raw.replacingOccurrences(
            of: #"\.([0-9]{3})[0-9]+"#, with: ".$1",
            options: .regularExpression)
        let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        for formatter in [fractional, plain] {
            if let date = formatter.date(from: normalized) { return date }
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "cannot decode ISO-8601 date: \(raw)")
    }
}
