import CryptoKit
import Foundation
import os
import Testing
@testable import TankbookCore

// RV.59 - one logical action fires the same request twice (the duplicate-
// request family after RV.6 and RV.18). Every assertion here is a REQUEST
// COUNT over a recording/double transport, never a success assertion: "the
// sync succeeded" and "config loaded" both pass against these bugs.
//
// Four shapes, each pinned at the seam where the count is observable:
//   1. Config is refreshed twice at launch (the `.task` and the launch `.active`
//      transition). Pinned in `ConfigStore`: two concurrent refreshes for one
//      logical foreground collapse to ONE fetch, and a genuine foreground after
//      the 6-hour window still fetches exactly once.
//   2. `/rates/pack` doubles the same way. Pinned in `RateStore`: two launch
//      triggers collapse to ONE pack fetch.
//   3/4. A cold start fires authenticated calls that cannot succeed before one
//      `auth/refresh`. Pinned in `TankbookHTTPClient`: a KNOWN-expired bearer
//      refreshes BEFORE the first I/O (one refresh, one pull, no 401), a valid
//      bearer is never pre-refreshed (one pull, zero refreshes - an unnecessary
//      rotation is not free), and a mid-flight 401 refreshes once and replays
//      once with no further request.

// MARK: - Key and signing (fixture-derived, bytes 0x01..0x20 - the same seed
// documented by Fixtures/config/README.md and used by ConfigStoreTests)

private let signingSeed = Data((1...32).map { UInt8($0) })
private let signingKey: Curve25519.Signing.PrivateKey = {
    try! Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed)
}()

private func fixtureVerifier() -> ConfigSignatureVerifier {
    ConfigSignatureVerifier(publicKey: signingKey.publicKey.rawRepresentation)
}

private func sign(_ document: Data) -> String {
    let canonical = try! ConfigCanonicalizer.canonicalize(document)
    return try! signingKey.signature(for: canonical).base64EncodedString()
}

private func makeDocument(tier3: Bool = true) -> Data {
    let fields = [
        "\"version\": 7",
        "\"issuedAt\": \"2026-01-01T00:00:00Z\"",
        "\"notAfter\": \"2099-01-01T00:00:00Z\"",
        "\"apiBaseUrl\": \"https://api.tankbook.live\"",
        "\"tier2OnDeviceLLM\": true",
        "\"tier3CloudFallback\": \(tier3)",
        "\"llmQuota\": {\"onDeviceLLM\": 200, \"cloudFallback\": 50}",
        "\"ocrConfidenceThreshold\": 0.75",
        "\"minSchemaVersion\": 1",
        "\"referencePacks\": {\"rates\": 1, \"catalog\": 1}",
        "\"rolloutSalt\": \"rv59-salt\""
    ]
    return Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
}

private func makeBundled() -> AppConfig {
    let document = try! ConfigDocument.parse(makeDocument())
    return AppConfig(document: document, apiBaseURL: document.apiBaseURL!)
}

/// A valid, signed document for a fetcher that must commit `fetchedAt`.
private func signedResult() -> ConfigFetchResult {
    let document = makeDocument()
    return ConfigFetchResult(document: document, signature: sign(document), etag: nil)
}

// MARK: - Config doubles

private final class MutableClock: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_760_000_000))
    func now() -> Date { lock.withLock { $0 } }
    func advance(by interval: TimeInterval) {
        lock.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

private final class InMemoryConfigRollbackFloor: ConfigRollbackFloorStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var floor: Int?
    func highestSeenVersion() -> Int? {
        lock.lock(); defer { lock.unlock() }
        return floor
    }
    func record(version: Int) {
        lock.lock(); defer { lock.unlock() }
        floor = max(floor ?? Int.min, version)
    }
}

/// Holds a `ConfigFetcher.fetch` until `open()` - "a fetch in flight" becomes
/// an observable, deterministic state rather than a timing accident.
private actor ConfigGate {
    private var hasStarted = false
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signalStarted() { hasStarted = true }
    var started: Bool { hasStarted }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Counts fetches, can stall them on a gate, and can switch between a document
/// (200) and nil (304) between calls.
private final class CountingConfigFetcher: ConfigFetcher, @unchecked Sendable {
    private struct State {
        var count = 0
        var result: Result<ConfigFetchResult?, any Error>
    }
    private let lock = OSAllocatedUnfairLock(initialState: State(result: .success(nil)))
    private let gate: ConfigGate?

    init(result: Result<ConfigFetchResult?, any Error> = .success(nil), gate: ConfigGate? = nil) {
        lock.withLock { $0.result = result }
        self.gate = gate
    }

    func set(result: Result<ConfigFetchResult?, any Error>) {
        lock.withLock { $0.result = result }
    }

    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult? {
        lock.withLock { $0.count += 1 }
        await gate?.signalStarted()
        await gate?.wait()
        return try lock.withLock { try $0.result.get() }
    }

    func callCount() -> Int { lock.withLock { $0.count } }
}

private func makeConfigStore(directory: URL, clock: MutableClock,
                             fetcher: any ConfigFetcher) -> ConfigStore {
    ConfigStore(
        bundled: makeBundled(),
        cacheDirectory: directory,
        verifier: fixtureVerifier(),
        keychain: InMemoryConfigRollbackFloor(),
        clock: { clock.now() },
        deviceIdentifier: "rv59-config-device",
        fetcher: fetcher
    )
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("rv59-\(UUID().uuidString)")
}

// MARK: - Rate doubles

private actor RateGate {
    private var hasStarted = false
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signalStarted() { hasStarted = true }
    var started: Bool { hasStarted }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Counts `/rates/pack` fetches, optionally stalling them on a gate.
private final class CountingRateFetcher: RateFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private let gate: RateGate?

    init(gate: RateGate? = nil) { self.gate = gate }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        lock.withLock { $0 += 1 }
        await gate?.signalStarted()
        await gate?.wait()
        return []
    }

    func callCount() -> Int { lock.withLock { $0 } }
}

// MARK: - Auth doubles (JWT fabrication)

private struct StaleTokenProvider: AuthorizationTokenProvider {
    let tokenValue: String
    func token() -> String? { tokenValue }
}

private func makeSession(accessToken: String, refreshToken: String = "old-rt") -> AuthSession {
    AuthSession(accessToken: accessToken, refreshToken: refreshToken,
                accountId: "acc", deviceId: "dev", provider: .apple)
}

private func refreshPairBody(_ access: String = "new-at", _ refresh: String = "new-rt") -> Data {
    Data("""
    {"accessToken":"\(access)","refreshToken":"\(refresh)"}
    """.utf8)
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A three-segment JWT whose payload carries the given `exp` (Unix seconds).
/// The signature segment is deliberately garbage - `JWTAccessToken` reads the
/// payload WITHOUT verifying, which is exactly the seam under test, and no
/// server ever validates these tokens.
private func jwt(exp expDate: Date) -> String {
    let header = Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8)
    let now = Int(Date().timeIntervalSince1970)
    let payloadText = "{\"iss\":\"tankbook\",\"aud\":\"tankbook\",\"sub\":\"acc\","
        + "\"device_id\":\"dev\",\"iat\":\(now),"
        + "\"exp\":\(Int(expDate.timeIntervalSince1970))}"
    let payload = Data(payloadText.utf8)
    return "\(base64URL(header)).\(base64URL(payload)).signature"
}

// MARK: - 1. Config: one logical foreground, one fetch

@Suite("RV.59 config launch double-fire")
struct RV59ConfigDoubleFireTests {

    @Test func aLaunchDoubleFireIssuesOneConfigFetchAndARealForegroundFetchesAgain() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableClock()
        let gate = ConfigGate()
        let fetcher = CountingConfigFetcher(result: .success(signedResult()), gate: gate)
        let store = makeConfigStore(directory: directory, clock: clock, fetcher: fetcher)

        // The launch shape: the `.task` and the launch `.active` transition both
        // call refresh() while the first is still on the wire. Both must complete
        // with ONE fetch between them.
        async let first: Void = store.refresh()
        while await !gate.started { try await Task.sleep(for: .milliseconds(1)) }
        async let second: Void = store.refresh()
        await gate.open()
        await first
        await second

        #expect(fetcher.callCount() == 1,
                "two launch triggers for one foreground event must issue ONE GET /v1/config")

        // A genuine foreground AFTER the 6-hour window must still fetch exactly
        // once - collapsing launch into "config loads once ever" is a worse bug.
        clock.advance(by: ConfigStore.automaticRefreshInterval + 1)
        await store.refresh()
        #expect(fetcher.callCount() == 2,
                "a real foreground after the window must issue exactly one more fetch")
    }

    @Test func aSecondForegroundInsideTheWindowIsThrottledToZeroFetches() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableClock()
        let fetcher = CountingConfigFetcher(result: .success(signedResult()))
        let store = makeConfigStore(directory: directory, clock: clock, fetcher: fetcher)

        await store.refresh()
        #expect(fetcher.callCount() == 1)

        // Foreground again while the 6-hour window is open: no request. This is
        // the config cadence docs/CONFIG.md -> Delivery promises; it is what the
        // wiring-level dedupe must never break.
        await store.refresh()
        #expect(fetcher.callCount() == 1)
    }

    @Test func a304AnswerReArmsTheSixHourWindow() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableClock()
        let fetcher = CountingConfigFetcher(result: .success(signedResult()))
        let store = makeConfigStore(directory: directory, clock: clock, fetcher: fetcher)

        // First check delivers a document and arms the window.
        await store.refresh()
        #expect(fetcher.callCount() == 1)

        // After the window, the server answers 304 ("nothing changed"). That IS a
        // successful check - it must re-arm the window, or a string of unchanged
        // configs makes every foreground fetch (the throttle never engages).
        clock.advance(by: ConfigStore.automaticRefreshInterval + 1)
        fetcher.set(result: .success(nil))
        await store.refresh()
        #expect(fetcher.callCount() == 2, "the 304 is one check, issued once")

        await store.refresh()
        #expect(fetcher.callCount() == 2,
                "a 304 must re-arm the window - the next foreground is throttled, not a second request")
    }
}

// MARK: - 2. Rates: one logical foreground, one pack fetch

@Suite("RV.59 rate pack launch double-fire")
struct RV59RateDoubleFireTests {

    @Test func aLaunchDoubleFireIssuesOneRatePackFetch() async throws {
        let gate = RateGate()
        let fetcher = CountingRateFetcher(gate: gate)
        let store = RateStore(seed: [], fetcher: fetcher)

        // The two launch triggers that used to fire `/rates/pack` twice (the
        // root's foreground pass and Home's own first-load trigger).
        async let first: Bool = store.refresh()
        while await !gate.started { try await Task.sleep(for: .milliseconds(1)) }
        async let second: Bool = store.refresh()
        await gate.open()
        let (firstResult, secondResult) = await (first, second)

        #expect(firstResult && secondResult, "neither trigger reports a deferral")
        #expect(fetcher.callCount() == 1,
                "two launch triggers must issue ONE /rates/pack request")
    }

    @Test func aRefreshAfterTheFirstCompletesStillFetches() async throws {
        let fetcher = CountingRateFetcher()
        let store = RateStore(seed: [], fetcher: fetcher)

        await store.refresh()
        #expect(fetcher.callCount() == 1)

        // A LATER foreground (the in-flight task has finished) must still fetch:
        // single-flight is a control-flow dedupe, never a throttle.
        await store.refresh()
        #expect(fetcher.callCount() == 2)
    }
}

// MARK: - 3 & 4. Auth: refresh a known-expired bearer BEFORE the first I/O

@Suite("RV.59 known-expired bearer")
struct RV59KnownExpiredBearerTests {

    private static let baseURL = URL(string: "https://api.tankbook.live")!
    private static let pullURL = URL(string: "https://api.tankbook.live/v1/sync/pull")!

    private func makeRefresher(transport: AuthRecordingTransport,
                               store: InMemorySessionStore) -> SessionRefresher {
        SessionRefresher(baseURLProvider: { Self.baseURL }, transport: transport, sessionStore: store)
    }

    @Test func coldStartWithAnExpiredBearerRefreshesOnceThenPullsOnce() async throws {
        let transport = AuthRecordingTransport()
        let expired = jwt(exp: Date().addingTimeInterval(-300))
        let store = InMemorySessionStore(session: makeSession(accessToken: expired))
        let refresher = makeRefresher(transport: transport, store: store)
        let client = TankbookHTTPClient(transport: transport,
                                        tokenProvider: StaleTokenProvider(tokenValue: expired),
                                        refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 200, body: refreshPairBody()),
            TankbookHTTPResponse(status: 200, body: Data("ok".utf8))
        ])

        let response = try await client.send(TankbookHTTPRequest(url: Self.pullURL))

        #expect(response.status == 200)
        let sent = transport.receivedRequests()
        #expect(sent.count == 2,
                "an expired bearer costs ONE auth/refresh and ONE sync/pull - no doomed 401")
        #expect(sent[0].url.path == "/v1/auth/refresh",
                "the refresh must come BEFORE the first request, not after a rejection")
        #expect(sent[1].url.path == "/v1/sync/pull")
        #expect(sent[1].headers["Authorization"] == "Bearer new-at",
                "the pull must carry the rotated bearer, never the expired one")
    }

    @Test func aValidBearerIsNeverPreemptivelyRefreshed() async throws {
        let transport = AuthRecordingTransport()
        let valid = jwt(exp: Date().addingTimeInterval(3600))
        let store = InMemorySessionStore(session: makeSession(accessToken: valid))
        let refresher = makeRefresher(transport: transport, store: store)
        let client = TankbookHTTPClient(transport: transport,
                                        tokenProvider: StaleTokenProvider(tokenValue: valid),
                                        refresher: refresher)
        transport.script([TankbookHTTPResponse(status: 200, body: Data("ok".utf8))])

        _ = try await client.send(TankbookHTTPRequest(url: Self.pullURL))

        let sent = transport.receivedRequests()
        #expect(sent.count == 1, "a valid bearer goes out directly - no refresh")
        #expect(sent[0].url.path == "/v1/sync/pull")
    }

    @Test func anExpiredBearerThatCannotRefreshFailsWithAuthExpiredWithoutSendingTheRequest() async throws {
        let transport = AuthRecordingTransport()
        let expired = jwt(exp: Date().addingTimeInterval(-300))
        let store = InMemorySessionStore(session: makeSession(accessToken: expired))
        let refresher = makeRefresher(transport: transport, store: store)
        let client = TankbookHTTPClient(transport: transport,
                                        tokenProvider: StaleTokenProvider(tokenValue: expired),
                                        refresher: refresher)
        // The refresh token is dead: the refresh itself answers 401.
        transport.script([TankbookHTTPResponse(status: 401)])

        await #expect(throws: SessionRefresherError.authExpired) {
            _ = try await client.send(TankbookHTTPRequest(url: Self.pullURL))
        }

        let sent = transport.receivedRequests()
        #expect(sent.count == 1,
                "a dead session must not also send the doomed pull - one refresh, no request")
        #expect(sent[0].url.path == "/v1/auth/refresh")
        #expect(try store.load() == nil, "the rejected refresh signs the user out locally")
    }

    @Test func a401MidCycleRefreshesOnceReplaysOnceAndStops() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: makeSession(accessToken: "old-at"))
        let refresher = makeRefresher(transport: transport, store: store)
        let client = TankbookHTTPClient(transport: transport,
                                        tokenProvider: StaleTokenProvider(tokenValue: "old-at"),
                                        refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 200, body: refreshPairBody()),
            TankbookHTTPResponse(status: 200, body: Data("ok".utf8))
        ])

        let response = try await client.send(TankbookHTTPRequest(url: Self.pullURL))

        #expect(response.status == 200)
        let sent = transport.receivedRequests()
        #expect(sent.count == 3, "original, refresh, replay - and nothing after")
        #expect(sent[0].url.path == "/v1/sync/pull")
        #expect(sent[1].url.path == "/v1/auth/refresh")
        #expect(sent[2].url.path == "/v1/sync/pull")
        #expect(sent[2].headers["Authorization"] == "Bearer new-at",
                "the replay carries the rotated bearer")
        #expect(sent[0].headers["Authorization"] == "Bearer old-at")
    }
}
