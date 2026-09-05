import Foundation

/// The production `RateFetcher`: the public `GET /v1/rates/pack` endpoint over
/// HTTP, through the host-bound `TankbookHTTPClient` so the allowlist rules
/// (docs/SECURITY.md) apply exactly as they do for auth and sync. The endpoint
/// is public - no auth - but the client is still host-allowlisted before any
/// I/O. The body is decoded exactly: `rate` is a JSON NUMBER and is rebuilt
/// from its raw token through `Decimal(string:locale:)` (never through
/// `Double`), and `source` goes through `RateSource.wire(_:)` so a carried-
/// forward row keeps its real source (docs/API.md -> Exchange rates).
public struct RemoteRateFetcher: RateFetcher, Sendable {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider)
        self.director = director
    }

    public func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        var components = URLComponents(
            url: endpoint("rates/pack"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "from", value: Self.dayString(from)),
            URLQueryItem(name: "to", value: Self.dayString(to)),
            URLQueryItem(name: "base", value: base.rawValue),
        ]
        guard let url = components?.url else {
            throw RateFetchError.invalidResponse
        }
        let request = TankbookHTTPRequest(url: url, method: "GET")
        let response = try await send(request)
        do {
            return try Self.decodePack(response.body)
        } catch {
            // A malformed or partial body is one silent miss, not a distinct
            // failure mode (F9): the entry stays rate-pending either way.
            throw RateFetchError.invalidResponse
        }
    }

    // MARK: - HTTP

    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        do {
            let response = try await client.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch TankbookHTTPClientError.httpError(let status, _, _, _) {
            // A 400 problem+json (bad range), a 500, and any other non-2xx all
            // leave the cache unchanged: a miss is never an error (F9). The
            // host answered, so this is a response, never evidence the URL is
            // wrong.
            await director.report(.response(status: status))
            throw RateFetchError.invalidResponse
        } catch {
            // Every transport failure - allowlist refusal, socket error - is
            // one silent miss to the caller (RateStore.refresh swallows it),
            // and evidence the host was unreachable.
            await director.report(.transportFailure)
            throw RateFetchError.transportUnavailable
        }
    }

    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    // MARK: - Decoding

    /// Decodes a pack body exactly. `rate` is a JSON number, so it is read from
    /// its raw token and rebuilt with `Decimal(string:locale: en_US_POSIX)` -
    /// decoding it through Swift's default `Decimal` decoding would route it
    /// through `Double` and silently corrupt the value (docs/SCHEMA.md types
    /// money as Decimal). The `base` is top-level; each row is a quote for it.
    static func decodePack(_ data: Data?) throws -> [ExchangeRate] {
        guard let data else { throw RateFetchError.invalidResponse }
        let tree = try JSONValue.parse(data)
        guard let object = tree.objectValue,
              let base = object["base"]?.stringValue.flatMap(CurrencyCode.init(rawValue:)),
              let rows = object["rates"]?.arrayValue else {
            throw RateFetchError.invalidResponse
        }
        var rates: [ExchangeRate] = []
        rates.reserveCapacity(rows.count)
        for row in rows {
            guard let item = row.objectValue,
                  let dateString = item["date"]?.stringValue,
                  let date = Self.day(from: dateString),
                  let quote = item["quote"]?.stringValue.flatMap(CurrencyCode.init(rawValue:)),
                  let sourceString = item["source"]?.stringValue,
                  let rateToken = item["rate"]?.numberToken,
                  let rate = Decimal(string: rateToken, locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0 else {
                throw RateFetchError.invalidResponse
            }
            rates.append(ExchangeRate(base: base, quote: quote, date: date,
                                      rate: rate, source: RateSource.wire(sourceString)))
        }
        return rates
    }

    // MARK: - Dates (yyyy-MM-dd, the wire contract for `from`/`to`/`date`)

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func day(from iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }
}

/// Errors surfaced by `RemoteRateFetcher`. Every one is swallowed by
/// `RateStore.refresh()` - a rate miss, a network failure, a 400 and a garbage
/// body are all silent (hard rule 1, F9).
public enum RateFetchError: Error, Equatable {
    case transportUnavailable
    case invalidResponse
}

extension JSONValue {
    /// The raw token of a `.number`, or nil.
    var numberToken: String? {
        if case .number(let token) = self { return token }
        return nil
    }
}
