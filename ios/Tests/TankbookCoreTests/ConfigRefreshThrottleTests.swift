import CryptoKit
import Foundation
import os
import Testing
@testable import TankbookCore

// PR.3a: the compiled 6-hour config refresh throttle (docs/CONFIG.md ->
// "Delivery"). Two invariants, each with the named mutation that must break it:
// 1. A background/foreground refresh inside the window is skipped - removing the
//    guard so every refresh fetches must fail `backgroundRefreshIsThrottled`.
// 2. A user-initiated refresh bypasses the window - making the throttle swallow
//    a user-initiated refresh too must fail `userInitiatedRefreshBypassesTheThrottle`.

// MARK: - Key and signing (fixture-derived, bytes 0x01..0x20)

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
        "\"rolloutSalt\": \"throttle-salt\"",
    ]
    return Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
}

private func makeBundled() -> AppConfig {
    let document = try! ConfigDocument.parse(makeDocument())
    return AppConfig(document: document, apiBaseURL: document.apiBaseURL!)
}

// MARK: - Doubles

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

private final class CountingFetcher: ConfigFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private let result: ConfigFetchResult?

    init(result: ConfigFetchResult?) { self.result = result }

    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult? {
        lock.withLock { $0 += 1 }
        return result
    }

    func callCount() -> Int { lock.withLock { $0 } }
}

/// A signed, valid document wrapped in a fetch result, for a fetcher that must
/// deliver a document the store accepts (so `fetchedAt` gets committed).
private func signedResult() -> ConfigFetchResult {
    let document = makeDocument()
    return ConfigFetchResult(document: document, signature: sign(document), etag: nil)
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("config-throttle-\(UUID().uuidString)")
}

private func makeStore(
    directory: URL,
    clock: MutableClock,
    fetcher: any ConfigFetcher
) -> ConfigStore {
    ConfigStore(
        bundled: makeBundled(),
        cacheDirectory: directory,
        verifier: fixtureVerifier(),
        keychain: InMemoryConfigRollbackFloor(),
        clock: { clock.now() },
        deviceIdentifier: "throttle-test-device",
        fetcher: fetcher
    )
}

@Suite("ConfigStore refresh throttle (PR.3a)")
struct ConfigRefreshThrottleTests {

    @Test func backgroundRefreshIsThrottledWithinTheWindow() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableClock()
        let fetcher = CountingFetcher(result: signedResult())
        let store = makeStore(directory: directory, clock: clock, fetcher: fetcher)

        await store.refresh()
        #expect(fetcher.callCount() == 1, "the first refresh must fetch")

        await store.refresh()
        #expect(fetcher.callCount() == 1, "a background refresh inside the 6 h window must not fetch")
    }

    @Test func backgroundRefreshFetchesAgainAfterTheWindow() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableClock()
        let fetcher = CountingFetcher(result: signedResult())
        let store = makeStore(directory: directory, clock: clock, fetcher: fetcher)

        await store.refresh()
        #expect(fetcher.callCount() == 1)

        clock.advance(by: ConfigStore.automaticRefreshInterval + 1)
        await store.refresh()
        #expect(fetcher.callCount() == 2, "a background refresh after the window must fetch again")
    }

    @Test func userInitiatedRefreshBypassesTheThrottle() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableClock()
        let fetcher = CountingFetcher(result: signedResult())
        let store = makeStore(directory: directory, clock: clock, fetcher: fetcher)

        await store.refresh()
        #expect(fetcher.callCount() == 1)

        await store.refresh(userInitiated: true)
        #expect(fetcher.callCount() == 2,
                "a user-initiated refresh must fetch even inside the window")
    }

    @Test func theThrottlePersistsAcrossAStoreRestart() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // The first store commits a fetch at its clock's t0 and persists
        // `fetchedAt`. The second store over the same directory restores that
        // `fetchedAt` on its cold-start read, so one second later it must still
        // be inside the window and skip its own fetch.
        let clockA = MutableClock()
        let first = makeStore(directory: directory, clock: clockA,
                              fetcher: CountingFetcher(result: signedResult()))
        await first.refresh()

        let clockB = MutableClock()
        clockB.advance(by: 1)
        let fetcherB = CountingFetcher(result: signedResult())
        let second = makeStore(directory: directory, clock: clockB, fetcher: fetcherB)
        await second.refresh()

        #expect(fetcherB.callCount() == 0,
                "a store one second after the cached fetch must still be throttled")
    }
}
