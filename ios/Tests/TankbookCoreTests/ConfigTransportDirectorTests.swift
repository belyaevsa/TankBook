import CryptoKit
import Foundation
import os
import Testing
@testable import TankbookCore

// PR.3b: the transports actually feed the apiBaseUrl guardrails (docs/CONFIG.md
// -> "Base URL per operation" + "Auto-revert on sustained failure"). Before this
// slice every transport captured its base URL once at construction and nothing
// called `recordRequestOutcome`, so a health-gated promotion changed nothing and
// auto-revert was unreachable in the shipping app.
//
// These tests drive a real `RemoteSyncTransport` (built over a `ConfigStore` and
// a scripted transport double) and prove the two halves: the base URL is read
// per operation, and every request's outcome reaches `recordRequestOutcome` with
// the transport/response distinction auto-revert depends on.

// MARK: - Signing and store factory

private let signingKey = Curve25519.Signing.PrivateKey()

private func fixtureVerifier() -> ConfigSignatureVerifier {
    ConfigSignatureVerifier(publicKey: signingKey.publicKey.rawRepresentation)
}

private func sign(_ document: Data) -> String {
    let canonical = try! ConfigCanonicalizer.canonicalize(document)
    return try! signingKey.signature(for: canonical).base64EncodedString()
}

private func makeDocument(version: Int = 7, apiBaseURL: String? = nil) -> Data {
    var fields: [String] = [
        "\"version\": \(version)",
        "\"issuedAt\": \"2026-01-01T00:00:00Z\"",
        "\"notAfter\": \"2099-01-01T00:00:00Z\"",
        "\"tier2OnDeviceLLM\": true",
        "\"tier3CloudFallback\": true",
        "\"llmQuota\": {\"onDeviceLLM\": 200, \"cloudFallback\": 50}",
        "\"ocrConfidenceThreshold\": 0.75",
        "\"minSchemaVersion\": 1",
        "\"referencePacks\": {\"rates\": 1, \"catalog\": 1}",
        "\"rolloutSalt\": \"test-salt\""
    ]
    if let apiBaseURL { fields.append("\"apiBaseUrl\": \"\(apiBaseURL)\"") }
    return Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
}

private func makeBundled() -> AppConfig {
    try! ConfigDefaults.bundledAppConfig()
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

private struct StubConfigFetcher: ConfigFetcher {
    let result: ConfigFetchResult?
    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult? { result }
}

private func successFetcher(document: Data, signature: String) -> StubConfigFetcher {
    StubConfigFetcher(result: ConfigFetchResult(document: document, signature: signature, etag: nil))
}

private struct StubHealthProber: HealthProber {
    let accepts: Bool
    func probe(baseURL: URL) async -> Bool { accepts }
}

private func makeStore(
    bundled: AppConfig,
    directory: URL,
    fetcher: (any ConfigFetcher)? = nil,
    healthProber: (any HealthProber)? = nil,
    maxConsecutiveFailures: Int = 5
) -> ConfigStore {
    ConfigStore(
        bundled: bundled,
        cacheDirectory: directory,
        verifier: fixtureVerifier(),
        keychain: InMemoryConfigRollbackFloor(),
        clock: { Date(timeIntervalSince1970: 1_760_000_000) },
        deviceIdentifier: "device-test-1",
        fetcher: fetcher,
        healthProber: healthProber,
        maxConsecutiveFailures: maxConsecutiveFailures
    )
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("config-director-\(UUID().uuidString)")
}

// MARK: - Transport doubles

private final class DirectorScriptedTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var requests: [TankbookHTTPRequest] = []
        var responses: [TankbookHTTPResponse] = []
        var shouldFail = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0.responses = responses }
    }

    func fail() {
        lock.withLock { $0.shouldFail = true }
    }

    func receivedRequests() -> [TankbookHTTPRequest] {
        lock.withLock { $0.requests }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        try lock.withLock { state in
            state.requests.append(request)
            if state.shouldFail { throw URLError(.notConnectedToInternet) }
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200, body: Self.emptyPullBody) }
            return state.responses.removeFirst()
        }
    }

    private static let emptyPullBody = Data(#"{"records":[],"nextSince":0,"more":false}"#.utf8)
}

private final class RecordingDirector: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [ConfigTransportOutcome]())

    func report(_ outcome: ConfigTransportOutcome) async {
        lock.withLock { $0.append(outcome) }
    }

    func outcomes() -> [ConfigTransportOutcome] {
        lock.withLock { $0 }
    }
}

private struct StaticTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { "test-token" }
}

// MARK: - The tests

@Suite("Config transports feed the guardrails (PR.3b)")
struct ConfigTransportDirectorTests {

    @Test func aTransportBuiltBeforeAPromotionRequestsThePromotedHost() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let promoted = "https://new.tankbook.live"
        let document = makeDocument(apiBaseURL: promoted)
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(accepts: true)
        )

        // Build the transport while the store is still on the bundled URL.
        let network = DirectorScriptedTransport()
        let sync = RemoteSyncTransport(
            director: ConfigTransportDirector(
                baseURL: { store.current.apiBaseURL },
                report: { await store.recordRequestOutcome($0) }
            ),
            transport: network,
            tokenProvider: StaticTokenProvider()
        )

        // Promote AFTER the transport was built.
        await store.refresh()
        #expect(store.current.apiBaseURL == URL(string: promoted)!)

        // The next request goes against the promoted host. A transport that
        // captured its base URL once at construction would still hit the
        // bundled host here.
        _ = try await sync.pull(since: 0, limit: 10)
        #expect(network.receivedRequests().first?.url.host == "new.tankbook.live",
                "a transport must read the base URL per operation, not per construction")
    }

    @Test func fiveTransportFailuresThroughATransportAutoRevert() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let promoted = "https://dead.tankbook.live"
        let document = makeDocument(apiBaseURL: promoted)
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(accepts: true),
            maxConsecutiveFailures: 5
        )
        await store.refresh()
        #expect(store.current.apiBaseURL == URL(string: promoted)!)

        let network = DirectorScriptedTransport()
        network.fail()
        let sync = RemoteSyncTransport(
            director: ConfigTransportDirector(
                baseURL: { store.current.apiBaseURL },
                report: { await store.recordRequestOutcome($0) }
            ),
            transport: network,
            tokenProvider: StaticTokenProvider()
        )

        for _ in 0..<5 {
            _ = try? await sync.pull(since: 0, limit: 10)
        }

        // The brick-proof property, now fed by a real transport rather than by
        // a test calling recordRequestOutcome directly (docs/CONFIG.md ->
        // "Auto-revert on sustained failure").
        #expect(store.current.apiBaseURL == bundled.apiBaseURL,
                "five transport failures through a real transport must auto-revert")
        #expect(store.consecutiveFailureCount == 0)
    }

    @Test func aServerErrorIsAResponseThatResetsTheCounter() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let promoted = "https://new.tankbook.live"
        let document = makeDocument(apiBaseURL: promoted)
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(accepts: true),
            maxConsecutiveFailures: 5
        )
        await store.refresh()

        let network = DirectorScriptedTransport()
        network.script([TankbookHTTPResponse(status: 500)])
        let sync = RemoteSyncTransport(
            director: ConfigTransportDirector(
                baseURL: { store.current.apiBaseURL },
                report: { await store.recordRequestOutcome($0) }
            ),
            transport: network,
            tokenProvider: StaticTokenProvider()
        )

        // Four transport failures bring the streak to one short of the revert.
        for _ in 0..<4 {
            await store.recordRequestOutcome(.transportFailure)
        }
        #expect(store.consecutiveFailureCount == 4)

        // A 500 through the transport is a RESPONSE: it resets the streak and
        // must not be the 5th failure that reverts a good base URL.
        _ = try? await sync.pull(since: 0, limit: 10)

        #expect(store.current.apiBaseURL == URL(string: promoted)!,
                "a 500 is not evidence the base URL is wrong - it must not revert")
        #expect(store.consecutiveFailureCount == 0, "a 500 resets the failure streak")
    }

    @Test func aTransportReportsAResponseForA500AndAFailureForAThrow() async {
        let reporter = RecordingDirector()

        let network = DirectorScriptedTransport()
        network.script([TankbookHTTPResponse(status: 500)])
        let sync = RemoteSyncTransport(
            director: ConfigTransportDirector(
                baseURL: { URL(string: "https://api.tankbook.live")! },
                report: { await reporter.report($0) }
            ),
            transport: network,
            tokenProvider: StaticTokenProvider()
        )
        _ = try? await sync.pull(since: 0, limit: 10)
        #expect(reporter.outcomes() == [.response(status: 500)],
                "a 500 is a response, whatever status the host answered with")

        let failing = DirectorScriptedTransport()
        failing.fail()
        let failingSync = RemoteSyncTransport(
            director: ConfigTransportDirector(
                baseURL: { URL(string: "https://api.tankbook.live")! },
                report: { await reporter.report($0) }
            ),
            transport: failing,
            tokenProvider: StaticTokenProvider()
        )
        _ = try? await failingSync.pull(since: 0, limit: 10)
        #expect(reporter.outcomes() == [.response(status: 500), .transportFailure],
                "a thrown transport error is a transportFailure")
    }

    // MARK: RV.139b - the RATE fetcher's report mapping (docs/CONFIG.md ->
    // "Auto-revert on sustained failure")

    /// A `ConfigStore` promoted to `promoted`, on which the rate fetcher's
    /// `report` feeds the real auto-revert counter. The caller owns `directory`
    /// and must remove it when the test is done (the existing pattern).
    private func makePromotedStore(_ promoted: String, directory: URL) async -> ConfigStore {
        let bundled = makeBundled()
        let document = makeDocument(apiBaseURL: promoted)
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(accepts: true),
            maxConsecutiveFailures: 5
        )
        await store.refresh()
        return store
    }

    private struct NilRateTokenProvider: AuthorizationTokenProvider {
        func token() -> String? { nil }
    }

    /// A `hostNotAllowlisted` refusal is a security refusal, not evidence the
    /// host is down: it must not count toward the auto-revert counter that a
    /// `.transportFailure` feeds. RV.139b fixed the rate fetcher, which used to
    /// map every non-HTTP error - refusal included - to `.transportFailure`,
    /// so five silent refusals would have auto-reverted a healthy promoted URL.
    /// Five refusals at the revert threshold must leave the promoted URL in
    /// place, which is exactly what the old mapping broke.
    @Test func rateFetchAllowlistRefusalsDoNotFeedTheAutoRevertCounter() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let promoted = "https://new.tankbook.live"
        let promotedURL = URL(string: promoted)!
        let store = await makePromotedStore(promoted, directory: directory)
        #expect(store.current.apiBaseURL == promotedURL)

        // The fetcher's OWN director names a non-allowlisted host (the shape
        // that produces the refusal) while still reporting into the store.
        let network = DirectorScriptedTransport()
        let fetcher = RemoteRateFetcher(
            director: ConfigTransportDirector(
                baseURL: { URL(string: "https://evil.com")! },
                report: { await store.recordRequestOutcome($0) }
            ),
            transport: network,
            tokenProvider: NilRateTokenProvider()
        )

        for _ in 0..<5 {
            await #expect(throws: RateFetchError.self) {
                _ = try await fetcher.fetchPack(from: Date(), to: Date(), base: .eur)
            }
        }

        // A refusal is not a transport failure: the counter never moved, so the
        // promoted URL was never reverted.
        #expect(network.receivedRequests().isEmpty,
                "a non-allowlisted host must never reach the transport")
        #expect(store.consecutiveFailureCount == 0,
                "a hostNotAllowlisted refusal is not evidence the host is unreachable")
        #expect(store.current.apiBaseURL == promotedURL,
                "five refusals must not auto-revert a healthy promoted URL")
    }

    /// The genuine transport error still feeds the counter: a rate fetch whose
    /// host never answers is exactly the "host unreachable" evidence auto-revert
    /// exists for, and separating the refusal must not have silenced it.
    @Test func rateFetchTransportErrorsStillFeedTheAutoRevertCounter() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let promoted = "https://new.tankbook.live"
        let promotedURL = URL(string: promoted)!
        let store = await makePromotedStore(promoted, directory: directory)
        #expect(store.current.apiBaseURL == promotedURL)

        let network = DirectorScriptedTransport()
        network.fail()  // URLError(.notConnectedToInternet)
        let fetcher = RemoteRateFetcher(
            director: ConfigTransportDirector(
                baseURL: { URL(string: promoted)! },
                report: { await store.recordRequestOutcome($0) }
            ),
            transport: network,
            tokenProvider: NilRateTokenProvider()
        )

        await #expect(throws: RateFetchError.self) {
            _ = try await fetcher.fetchPack(from: Date(), to: Date(), base: .eur)
        }
        #expect(network.receivedRequests().count == 1, "the request reached the transport")
        #expect(store.consecutiveFailureCount == 1,
                "a genuine transport failure is evidence the host is unreachable and must count")
    }
}

// MARK: - The grep gate

@Suite("Config base URL grep gate (PR.3b)")
struct ConfigBaseURLGrepGateTests {

    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios

    /// A text scan over the app target's `.swift` files, following the
    /// `LowPowerModeTests` source-scan pattern.
    ///
    /// What this cannot see, said plainly: it matches the literal text
    /// `api.tankbook.live`. A base URL assembled from pieces
    /// (`"https://api." + "tankbook.live"`) is invisible to it, and a comment
    /// mentioning the host would trip it as though it were code. Neither is in
    /// the tree today; the legitimate home of the value is `Config.default.json`
    /// in core, which is not under `ios/App/Sources` and so is not scanned.
    @Test func appSourcesNeverHardcodeTheBundledBaseURL() throws {
        let appSources = Self.iosRoot.appendingPathComponent("App/Sources", isDirectory: true)
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: appSources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Issue.record("cannot enumerate \(appSources.path)")
            return
        }
        var offenders: [String] = []
        for element in enumerator {
            guard let url = element as? URL, url.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if contents.contains("api.tankbook.live") {
                offenders.append(url.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty,
                "the app must never hardcode the base URL; it belongs to the config layer. Offenders: \(offenders)")
    }
}
