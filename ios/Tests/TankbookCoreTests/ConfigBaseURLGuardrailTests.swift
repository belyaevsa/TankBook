import CryptoKit
import Foundation
import os
import Testing
@testable import TankbookCore

// P0.12c: the apiBaseUrl guardrails in ConfigStore (docs/CONFIG.md ->
// "Guardrails on apiBaseUrl" + "Auto-revert on sustained failure"). The store
// treats a document's apiBaseUrl as a *candidate*: allowlist-checked, health
// gated, promoted only on success, and reverted to the bundled default after N
// consecutive transport failures. Documents are signed at runtime with the
// fixture key (bytes 0x01..0x20, see Fixtures/config/README.md).

// MARK: - Key and signing (fixture-derived)

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

// MARK: - Document builder

private func makeDocument(
    version: Int = 7,
    tier3: Bool = true,
    apiBaseURL: String? = nil,
    rolloutSalt: String = "test-salt"
) -> Data {
    var fields: [String] = [
        "\"version\": \(version)",
        "\"issuedAt\": \"2026-01-01T00:00:00Z\"",
        "\"notAfter\": \"2099-01-01T00:00:00Z\"",
        "\"tier2OnDeviceLLM\": true",
        "\"tier3CloudFallback\": \(tier3)",
        "\"llmQuota\": {\"onDeviceLLM\": 200, \"cloudFallback\": 50}",
        "\"ocrConfidenceThreshold\": 0.75",
        "\"minSchemaVersion\": 1",
        "\"referencePacks\": {\"rates\": 1, \"catalog\": 1}",
        "\"rolloutSalt\": \"\(rolloutSalt)\"",
    ]
    if let apiBaseURL { fields.append("\"apiBaseUrl\": \"\(apiBaseURL)\"") }
    return Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
}

/// A bundled layer with `tier3CloudFallback == true` and the real bundled base URL.
private func makeBundled() -> AppConfig {
    let data = makeDocument(apiBaseURL: "https://api.tankbook.live")
    let document = try! ConfigDocument.parse(data)
    return AppConfig(document: document, apiBaseURL: document.apiBaseURL!)
}

// MARK: - Test doubles

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

private final class StubConfigFetcher: ConfigFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Result<ConfigFetchResult?, any Error>.success(nil))

    init(result: Result<ConfigFetchResult?, any Error>) {
        lock.withLock { $0 = result }
    }

    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult? {
        try lock.withLock { $0 }.get()
    }
}

private func successFetcher(document: Data, signature: String) -> StubConfigFetcher {
    StubConfigFetcher(result: .success(ConfigFetchResult(document: document, signature: signature, etag: nil)))
}

/// A health prober whose results are scripted per call; when the script is
/// empty it falls back to `defaultResult`.
private final class StubHealthProber: HealthProber, @unchecked Sendable {
    private struct State {
        var results: [Bool] = []
        var probed: [URL] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let defaultResult: Bool

    init(defaultResult: Bool = true) { self.defaultResult = defaultResult }

    func set(results: [Bool]) {
        lock.withLock { $0.results = results }
    }

    func probe(baseURL: URL) async -> Bool {
        lock.withLock { state in
            state.probed.append(baseURL)
            if state.results.isEmpty { return defaultResult }
            return state.results.removeFirst()
        }
    }

    func probedURLs() -> [URL] {
        lock.withLock { $0.probed }
    }
}

// MARK: - Store factory

private func makeStore(
    bundled: AppConfig,
    directory: URL,
    fetcher: (any ConfigFetcher)? = nil,
    healthProber: (any HealthProber)? = nil,
    maxConsecutiveFailures: Int = 5,
    log: TankbookLog? = nil
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
        maxConsecutiveFailures: maxConsecutiveFailures,
        log: log
    )
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("config-baseurl-\(UUID().uuidString)")
}

@Suite("ConfigStore apiBaseUrl guardrails (P0.12c)")
struct ConfigBaseURLGuardrailTests {

    // MARK: 1. Brick-proof

    @Test func unreachableBaseURLAutoRevertsToBundledAndRecovers() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let prober = StubHealthProber(defaultResult: true)
        let dead = "https://dead.tankbook.live"
        let document = makeDocument(apiBaseURL: dead)
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: prober,
            maxConsecutiveFailures: 5
        )

        await store.refresh()
        #expect(store.current.apiBaseURL == URL(string: dead)!, "the candidate is promoted while healthy")

        // The host goes dark: N simulated transport failures.
        for _ in 0..<5 {
            await store.recordRequestOutcome(.transportFailure)
        }

        // Recovery, not just "the counter reached 5": the store reverts to the
        // bundled default and a subsequent request against it succeeds.
        #expect(store.current.apiBaseURL == bundled.apiBaseURL, "must revert to the bundled default")
        #expect(store.consecutiveFailureCount == 0, "the counter resets on revert")
        #expect(prober.probedURLs().contains(bundled.apiBaseURL), "the revert re-probes the bundled default")

        let transport = RecordingTransportForRecovery()
        let client = TankbookHTTPClient(
            transport: transport,
            tokenProvider: RecordingTokenProviderForRecovery(token: "recovered")
        )
        let response = try await client.send(TankbookHTTPRequest(url: bundled.apiBaseURL))
        #expect(response.status == 200, "a request against the bundled URL succeeds after revert")
        #expect(transport.receivedRequests().first?.url == bundled.apiBaseURL)
    }

    // MARK: 4. Failing candidate discarded

    @Test func failingCandidateIsDiscardedAndPreviousValueStands() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let prober = StubHealthProber(defaultResult: false)
        let document = makeDocument(apiBaseURL: "https://new.tankbook.live")
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: prober
        )

        await store.refresh()

        #expect(store.current.apiBaseURL == bundled.apiBaseURL, "a failed health probe keeps the previous URL")
        #expect(store.activeBaseURLValue == nil, "a failed candidate is never promoted")
    }

    // MARK: 5. Health-gate success promotes and persists

    @Test func healthyCandidateIsPromotedAndPersisted() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let document = makeDocument(apiBaseURL: "https://new.tankbook.live")
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(defaultResult: true)
        )

        await store.refresh()

        #expect(store.current.apiBaseURL == URL(string: "https://new.tankbook.live")!)
        #expect(store.activeBaseURLValue == "https://new.tankbook.live")

        let record = try #require(ConfigCacheFile.read(directory: directory))
        #expect(record.activeBaseURL == "https://new.tankbook.live", "the promoted value is persisted")
    }

    // MARK: 6. Failure count survives a restart

    @Test func consecutiveFailureCountSurvivesAStoreRestart() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let document = makeDocument(apiBaseURL: "https://new.tankbook.live")
        let first = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(defaultResult: true),
            maxConsecutiveFailures: 10
        )
        await first.refresh()
        for _ in 0..<3 {
            await first.recordRequestOutcome(.transportFailure)
        }
        #expect(first.consecutiveFailureCount == 3)

        // A new store over the same directory carries the count forward, which
        // is what makes "across at least two app sessions" true.
        let second = makeStore(bundled: bundled, directory: directory, maxConsecutiveFailures: 10)
        #expect(second.consecutiveFailureCount == 3, "the failure count must survive a restart")
        #expect(second.current.apiBaseURL == URL(string: "https://new.tankbook.live")!,
                "the promoted URL also survives the restart")
    }

    // MARK: 7. Success resets the counter

    @Test func aResponseResetsTheCounterToZero() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let document = makeDocument(apiBaseURL: "https://new.tankbook.live")
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(defaultResult: true),
            maxConsecutiveFailures: 5
        )
        await store.refresh()

        for _ in 0..<4 {
            await store.recordRequestOutcome(.transportFailure)
        }
        #expect(store.consecutiveFailureCount == 4)

        await store.recordRequestOutcome(.response(status: 200))
        #expect(store.consecutiveFailureCount == 0, "a device that fails 4 times and succeeds must not carry 4 forward")
    }

    // MARK: 8. Transport failure vs HTTP error

    @Test func httpErrorDoesNotCountTowardRevertButTransportFailureDoes() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        let document = makeDocument(apiBaseURL: "https://new.tankbook.live")
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(defaultResult: true),
            maxConsecutiveFailures: 3
        )
        await store.refresh()

        // A 500 is a response (the host answered): it never counts toward revert.
        await store.recordRequestOutcome(.response(status: 500))
        #expect(store.consecutiveFailureCount == 0)

        await store.recordRequestOutcome(.transportFailure)
        #expect(store.consecutiveFailureCount == 1)

        // A 500 after a failure resets the streak (the host is reachable) and
        // can never trigger the revert by itself.
        await store.recordRequestOutcome(.response(status: 500))
        #expect(store.consecutiveFailureCount == 0)

        await store.recordRequestOutcome(.response(status: 500))
        await store.recordRequestOutcome(.response(status: 503))
        #expect(store.current.apiBaseURL == URL(string: "https://new.tankbook.live")!,
                "any number of 5xx responses must not revert the base URL")
    }

    // MARK: 10. Bad apiBaseUrl applies its other keys

    @Test func aBadAPIBaseURLStillAppliesTheDocumentsOtherKeys() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled() // tier3CloudFallback == true
        let document = makeDocument(tier3: false, apiBaseURL: "https://evil.com")
        let store = makeStore(
            bundled: bundled,
            directory: directory,
            fetcher: successFetcher(document: document, signature: sign(document)),
            healthProber: StubHealthProber(defaultResult: true)
        )

        await store.refresh()

        // Key-level rejection: the bad apiBaseUrl is refused, the previous URL
        // stands, and the rest of the document still applies.
        #expect(store.current.apiBaseURL == bundled.apiBaseURL, "the previous base URL stands")
        #expect(store.current.tier3CloudFallback == false, "the valid keys still apply")
        #expect(store.current.version == 7, "the document is otherwise adopted")
    }

    // MARK: Bonus: a tampered activeBaseURL in the cache is dropped on read

    @Test func aNonAllowlistedActiveBaseURLInTheCacheFallsBackToBundled() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = makeBundled()
        // A validly-signed document, but the persisted activeBaseURL points at
        // an attacker's host (as a tampered cache could write it).
        let document = makeDocument(tier3: false)
        let record = ConfigCacheRecord(
            document: document,
            signature: sign(document),
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            activeBaseURL: "https://evil.com",
            consecutiveFailures: 2
        )
        try ConfigCacheFile.write(record, directory: directory)

        let store = makeStore(bundled: bundled, directory: directory)

        #expect(store.current.apiBaseURL == bundled.apiBaseURL,
                "a tampered activeBaseURL must not become the resolved URL")
        #expect(store.current.tier3CloudFallback == false, "the valid document still applies")
    }
}

// MARK: - Recovery doubles (for the brick-proof test)

private final class RecordingTransportForRecovery: TankbookHTTPTransport, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [TankbookHTTPRequest]())

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { $0.append(request) }
        return TankbookHTTPResponse(status: 200)
    }

    func receivedRequests() -> [TankbookHTTPRequest] {
        lock.withLock { $0 }
    }
}

private struct RecordingTokenProviderForRecovery: AuthorizationTokenProvider, Sendable {
    private let tokenValue: String
    init(token: String) { self.tokenValue = token }
    func token() -> String? { tokenValue }
}
