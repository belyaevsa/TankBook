import Foundation
import os
import Testing
@testable import TankbookCore

// P5.2a - the real rate feed: the pack endpoint's query, its exact Decimal
// decode (a JSON number must never route through Double), the shared
// wire->RateSource mapping, and the host-allowlist gate. Every test runs with
// no sockets (a transport double stands in for URLSession).

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private struct NoAuthTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}

private final class ScriptedTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let result: Result<TankbookHTTPResponse, any Error>
    private let receivedLock = OSAllocatedUnfairLock(initialState: 0)

    init(status: Int, body: Data?) {
        self.result = .success(TankbookHTTPResponse(status: status, body: body))
    }

    init(error: any Error) {
        self.result = .failure(error)
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        receivedLock.withLock { $0 += 1 }
        return try result.get()
    }

    func receivedCount() -> Int {
        receivedLock.withLock { $0 }
    }
}

private struct RecordingTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(
        initialState: (received: [TankbookHTTPRequest](), responses: [TankbookHTTPResponse]()))

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0.responses = responses }
    }

    func receivedRequests() -> [TankbookHTTPRequest] {
        lock.withLock { $0.received }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { state in
            state.received.append(request)
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200) }
            return state.responses.removeFirst()
        }
    }
}

// MARK: - Exact Decimal decode (trap 1)

@Test func packDecodesRateAsExactDecimalNotDouble() throws {
    // 1.08107664 (a real USD row from the bundled seed) is the guard: routing
    // it through Double yields 1.0810766400000002048, which is NOT the string
    // value. 4.2706 and 0.0108384 are the task's named examples.
    let body = """
    {"from":"2026-08-01","to":"2026-08-27","base":"EUR","rates":[
      {"date":"2026-08-21","quote":"PLN","rate":4.2706,"source":"ecb"},
      {"date":"2026-08-22","quote":"SEK","rate":0.0108384,"source":"cis"},
      {"date":"2026-08-21","quote":"USD","rate":1.08107664,"source":"ecb"}
    ]}
    """
    let rates = try RemoteRateFetcher.decodePack(Data(body.utf8))
    #expect(rates.count == 3)
    // Exact equality against the string-built Decimal: the naive decode routes
    // the JSON number through Double, which fails on 1.08107664.
    #expect(rates[0].rate == decimal("4.2706"))
    #expect(rates[1].rate == decimal("0.0108384"))
    #expect(rates[2].rate == decimal("1.08107664"))
}

@Test func theNaiveDoubleDecodeIsNotTheExactValue() {
    // The contrast the exact-equality test pins: the Double route is lossy for
    // a real rate, which is why the client decodes the raw number token.
    #expect(Decimal(1.08107664) != decimal("1.08107664"))
}

// MARK: - Shared wire->RateSource mapping (trap 2)

@Test func wireSourceMapsAllFourStringsPlusUnknown() {
    #expect(RateSource.wire("ecb") == .ecb)
    #expect(RateSource.wire("cis") == .cis)
    #expect(RateSource.wire("ecb:carried-forward") == .ecb)
    #expect(RateSource.wire("cis:carried-forward") == .cis)
    #expect(RateSource.wire("some-future-source") == .ecb)
}

@Test func seedDecoderMapsCarriedForwardCISNotECB() throws {
    let body = """
    {"packVersion":1,"rates":[
      {"date":"2026-08-21","base":"EUR","quote":"RUB","rate":"90.1234","source":"cis:carried-forward"},
      {"date":"2026-08-21","base":"EUR","quote":"PLN","rate":"4.2","source":"ecb:carried-forward"}
    ]}
    """
    let seed = try RateSeedStore.decode(data: Data(body.utf8), calendar: utcCalendar)
    #expect(seed.first { $0.quote == .rub }?.source == .cis)
    #expect(seed.first { $0.quote == .pln }?.source == .ecb)
}

@Test func packDecoderMapsCarriedForwardCISNotECB() throws {
    let body = """
    {"base":"EUR","rates":[
      {"date":"2026-08-21","quote":"RUB","rate":90.1234,"source":"cis:carried-forward"},
      {"date":"2026-08-21","quote":"PLN","rate":4.2,"source":"ecb:carried-forward"}
    ]}
    """
    let rates = try RemoteRateFetcher.decodePack(Data(body.utf8))
    #expect(rates.first { $0.quote == .rub }?.source == .cis)
    #expect(rates.first { $0.quote == .pln }?.source == .ecb)
}

// MARK: - Query construction

@Test func fetchPackBuildsFromToBaseQuery() async throws {
    let transport = RecordingTransport()
    transport.script([TankbookHTTPResponse(status: 200, body: Data(#"{"base":"EUR","rates":[]}"#.utf8))])
    let fetcher = RemoteRateFetcher(director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! }, report: { _ in }),
                                    transport: transport, tokenProvider: NoAuthTokenProvider())

    _ = try await fetcher.fetchPack(from: day(2026, 8, 1), to: day(2026, 8, 27), base: .eur)

    let sent = transport.receivedRequests()
    #expect(sent.count == 1)
    let components = URLComponents(url: sent[0].url, resolvingAgainstBaseURL: false)
    #expect(components?.path == "/v1/rates/pack")
    let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["from"] == "2026-08-01")
    #expect(query["to"] == "2026-08-27")
    #expect(query["base"] == "EUR")
}

// MARK: - Allowlist

@Test func nonAllowlistedHostIsRefusedBeforeAnyIO() async {
    let transport = RecordingTransport()
    let fetcher = RemoteRateFetcher(director: ConfigTransportDirector(baseURL: { URL(string: "https://evil.com")! }, report: { _ in }),
                                    transport: transport, tokenProvider: NoAuthTokenProvider())

    await #expect(throws: RateFetchError.transportUnavailable) {
        _ = try await fetcher.fetchPack(from: day(2026, 8, 1), to: day(2026, 8, 27), base: .eur)
    }
    #expect(transport.receivedRequests().isEmpty,
            "a non-allowlisted host must never reach the transport")
}

// MARK: - Every failure is silent

private struct FetchFailure: Error {}

@Test func everyFetchFailureIsSilentAndLeavesCacheAndEntriesUntouched() async throws {
    let seed = ExchangeRate(base: .eur, quote: .pln, date: day(2026, 8, 1),
                            rate: decimal("4.2"), source: .ecb)
    let pending = Money(amount: decimal("289.50"), currency: .usd, homeCurrency: .eur)

    let problemJSON = #"{"type":"t","title":"x","status":400,"detail":"d"}"#
    let failures: [(String, ScriptedTransport)] = [
        ("transport error", ScriptedTransport(error: FetchFailure())),
        ("500", ScriptedTransport(status: 500, body: nil)),
        ("400 problem+json", ScriptedTransport(status: 400, body: Data(problemJSON.utf8))),
        ("malformed body", ScriptedTransport(status: 200, body: Data("not-json".utf8))),
    ]

    for (_, transport) in failures {
        let fetcher = RemoteRateFetcher(
            director: ConfigTransportDirector(
                baseURL: { URL(string: "https://api.tankbook.live")! }, report: { _ in }),
            transport: transport, tokenProvider: NoAuthTokenProvider())
        let store = RateStore(seed: [seed], fetcher: fetcher, calendar: utcCalendar)

        await store.refresh() // must not throw

        // The cache is byte-for-byte the seed - nothing fetched, nothing merged.
        #expect(store.allRates() == [seed])
        // A pair with no rate in the cache is still pending - a miss is not an
        // error, the entry stays rate-pending (F9).
        #expect(store.convert(pending, on: day(2026, 8, 21)).homeAmount == nil)
    }
}
