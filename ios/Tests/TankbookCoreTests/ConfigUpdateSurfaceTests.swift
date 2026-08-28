import CryptoKit
import Foundation
import Testing
@testable import TankbookCore

// P6.18b: the update requirement's SURFACE contract, pinned at the store
// boundary (docs/CONFIG.md -> "App version and the update notice" and
// "Delivery"). The app's `AppConfigService` derives its requirement from the
// store's HELD snapshot (live, else cache, else bundled) - never from a fetch
// in flight - and no screen waits on a response to decide what to draw.
//
// The two invariants, each with the named mutation that must break it:
// 1. A cache holding an `appUpdate` document carries the requirement the moment
//    the store is constructed - no refresh awaited, no fetch involved. A cold
//    start with a cached document shows the notice instantly. Evaluating
//    against a fetch (awaiting it, or reading a pending result) would leave the
//    notice missing until a network round trip.
// 2. While a refresh is in flight, the requirement derived from the held
//    snapshot is unchanged - the fetched document only governs once committed.
//    "Evaluate the requirement against the in-flight fetch instead of the held
//    snapshot" is the exact mutation that breaks this test.

// MARK: - Fixture signing (same seed as ConfigStoreTests:
// Fixtures/config/README.md documents bytes 0x01..0x20)

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

private let referenceNow = isoDate("2026-08-15T00:00:00Z")

private func isoDate(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

// MARK: - Document builder

/// A complete, schema-valid config document, with or without `appUpdate`. The
/// thresholds are docs/CONFIG.md's own example values (min 1.2.0, latest 1.4.0),
/// so a 1.1.0 build resolves `.required` and a 1.3.0 build `.recommended`.
private func makeDocument(appUpdate: String? = nil, apiBaseURL: String = "https://api.tankbook.live") -> Data {
    var fields: [String] = [
        "\"version\": 7",
        "\"issuedAt\": \"2026-01-01T00:00:00Z\"",
        "\"notAfter\": \"2099-01-01T00:00:00Z\"",
        "\"apiBaseUrl\": \"\(apiBaseURL)\"",
        "\"tier2OnDeviceLLM\": true",
        "\"tier3CloudFallback\": true",
        "\"llmQuota\": {\"onDeviceLLM\": 200, \"cloudFallback\": 50}",
        "\"ocrConfidenceThreshold\": 0.75",
        "\"minSchemaVersion\": 1",
        "\"referencePacks\": {\"rates\": 1, \"catalog\": 1}",
        "\"rolloutSalt\": \"surface-test-salt\""
    ]
    if let appUpdate { fields.append("\"appUpdate\": \(appUpdate)") }
    return Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
}

private func canonicalAppUpdateJSON() -> String {
    "{\"minSupportedVersion\": \"1.2.0\", \"latestVersion\": \"1.4.0\"}"
}

// MARK: - Test doubles

private final class InMemoryConfigRollbackFloor: ConfigRollbackFloorStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var floor: Int?

    func highestSeenVersion() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return floor
    }

    func record(version: Int) {
        lock.lock()
        defer { lock.unlock() }
        floor = max(floor ?? Int.min, version)
    }
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("configsurface-\(UUID().uuidString)")
}

private func makeStore(
    bundled: AppConfig,
    directory: URL,
    fetcher: (any ConfigFetcher)? = nil
) -> ConfigStore {
    ConfigStore(
        bundled: bundled,
        cacheDirectory: directory,
        verifier: fixtureVerifier(),
        keychain: InMemoryConfigRollbackFloor(),
        clock: { referenceNow },
        deviceIdentifier: "surface-test-device",
        fetcher: fetcher
    )
}

/// A fetcher whose result is held behind a gate: `fetch()` blocks until the
/// gate opens, which makes "a fetch in flight" an observable, deterministic
/// state rather than a timing accident.
private actor FetchGate {
    private var isOpen: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(openingImmediately: Bool = false) {
        isOpen = openingImmediately
    }

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

private final class GatedConfigFetcher: ConfigFetcher, @unchecked Sendable {
    private let gate: FetchGate
    private let result: Result<ConfigFetchResult, any Error>

    init(gate: FetchGate, result: Result<ConfigFetchResult, any Error>) {
        self.gate = gate
        self.result = result
    }

    func fetch() async throws -> ConfigFetchResult {
        await gate.wait()
        return try result.get()
    }
}

// MARK: - 1. A cached document carries the requirement at cold start

@Test func cachedDocumentCarriesTheRequirementAtColdStart() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try ConfigDefaults.bundledAppConfig()
    let document = makeDocument(appUpdate: canonicalAppUpdateJSON())
    let record = ConfigCacheRecord(document: document, signature: sign(document), etag: nil,
                                   fetchedAt: referenceNow, activeBaseURL: nil, consecutiveFailures: 0)
    try ConfigCacheFile.write(record, directory: directory)

    // The store's init performs the cold-start cache read; nothing here awaits a
    // refresh. The requirement must be derivable synchronously - the notice
    // appears instantly on a launch with a cached document (docs/CONFIG.md ->
    // "Delivery": no screen has ever waited for a response to decide what to
    // draw).
    let store = makeStore(bundled: bundled, directory: directory)

    #expect(store.current.appUpdate != nil, "the cached document must apply on the cold-start read")
    #expect(store.current.updateRequirement(runningVersion: "1.1.0") == .required)
    #expect(store.current.updateRequirement(runningVersion: "1.3.0") == .recommended)
    #expect(store.current.updateRequirement(runningVersion: "1.4.0") == .none)
}

@Test func noCacheMeansNoRequirementEvenForAnAncientBuild() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // A cold start with no cached document shows nothing, which is correct
    // (docs/CONFIG.md): the bundled default carries no appUpdate.
    let bundled = try ConfigDefaults.bundledAppConfig()
    let store = makeStore(bundled: bundled, directory: directory)

    #expect(store.current.appUpdate == nil)
    #expect(store.current.updateRequirement(runningVersion: "0.1.0") == .none)
}

// MARK: - 2. The requirement is the held snapshot, never the in-flight fetch

/// A health prober held behind a gate: `refresh()` fetches and validates a
/// candidate document, then stalls awaiting the probe. That stall is the
/// "in flight" window - the document has been fetched but not committed - and
/// it is observable, unlike the fetch await itself.
private actor ProbeGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

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

private final class GatedHealthProber: HealthProber, @unchecked Sendable {
    private let gate: ProbeGate
    private let result: Bool

    init(gate: ProbeGate, result: Bool) {
        self.gate = gate
        self.result = result
    }

    func probe(baseURL: URL) async -> Bool {
        await gate.wait()
        return result
    }
}

private func makeStore(
    bundled: AppConfig,
    directory: URL,
    fetcher: (any ConfigFetcher)? = nil,
    healthProber: (any HealthProber)? = nil
) -> ConfigStore {
    ConfigStore(
        bundled: bundled,
        cacheDirectory: directory,
        verifier: fixtureVerifier(),
        keychain: InMemoryConfigRollbackFloor(),
        clock: { referenceNow },
        deviceIdentifier: "surface-test-device",
        fetcher: fetcher,
        healthProber: healthProber
    )
}

@Test func requirementResolvesFromTheHeldSnapshotNotAnInFlightFetch() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try ConfigDefaults.bundledAppConfig()

    // The held snapshot at cold start: a CACHED document whose thresholds make
    // a 1.3.0 build `.recommended` (min 1.2.0, latest 1.4.0).
    let cached = makeDocument(appUpdate: canonicalAppUpdateJSON())
    let record = ConfigCacheRecord(document: cached, signature: sign(cached), etag: nil,
                                   fetchedAt: referenceNow, activeBaseURL: nil, consecutiveFailures: 0)
    try ConfigCacheFile.write(record, directory: directory)

    // The fetch WILL deliver thresholds that make the same 1.3.0 build
    // `.required` (min 9.0.0, latest 9.1.0), on a different allowlisted host so
    // the health gate stalls the commit.
    let pending = makeDocument(appUpdate: "{\"minSupportedVersion\": \"9.0.0\", \"latestVersion\": \"9.1.0\"}",
                               apiBaseURL: "https://cdn.tankbook.live")
    let gate = ProbeGate()
    let fetcher = GatedConfigFetcher(
        gate: FetchGate(openingImmediately: true),
        result: .success(ConfigFetchResult(document: pending, signature: sign(pending), etag: nil)))
    let prober = GatedHealthProber(gate: gate, result: true)
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher, healthProber: prober)

    let before = store.snapshot().updateRequirement(runningVersion: "1.3.0")
    #expect(before == .recommended, "the cached document governs at cold start")

    let refresh = Task { await store.refresh() }
    // Give refresh time to fetch + validate, so it is now stalled on the probe
    // with the new document fetched but NOT committed.
    try await Task.sleep(for: .milliseconds(150))

    let during = store.snapshot().updateRequirement(runningVersion: "1.3.0")
    #expect(during == before,
            "a fetched-but-uncommitted document must not change the held snapshot")

    await gate.open()
    await refresh.value

    let after = store.snapshot().updateRequirement(runningVersion: "1.3.0")
    #expect(after == .required, "once committed, the fetched document governs")
}

@Test func requirementIsStableWhileAFetchIsInFlight() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try ConfigDefaults.bundledAppConfig()
    // The fetch WILL deliver a document that makes a 1.1.0 build `.required` -
    // but only once its gate opens. While it is in flight, the held snapshot
    // must keep governing.
    let gate = FetchGate()
    let document = makeDocument(appUpdate: canonicalAppUpdateJSON())
    let fetcher = GatedConfigFetcher(gate: gate, result: .success(
        ConfigFetchResult(document: document, signature: sign(document), etag: nil)))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    let before = store.snapshot().updateRequirement(runningVersion: "1.1.0")
    #expect(before == .none, "a fresh store with no cache holds the bundled snapshot")

    let refresh = Task { await store.refresh() }
    // Give the fetch a moment to enter `fetch()` and block on the gate. The
    // assertion holds even if it has not: either way, `snapshot()` returns the
    // held value.
    try await Task.sleep(for: .milliseconds(100))

    let during = store.snapshot().updateRequirement(runningVersion: "1.1.0")
    #expect(during == before,
            "an in-flight fetch must not change the requirement the surface derives from the held snapshot")

    await gate.open()
    await refresh.value

    let after = store.snapshot().updateRequirement(runningVersion: "1.1.0")
    #expect(after == .required, "once committed, the fetched document governs")
}

@Test func snapshotTakenBeforeRefreshIsUnaffectedForTheRequirement() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try ConfigDefaults.bundledAppConfig()
    let gate = FetchGate()
    let document = makeDocument(appUpdate: canonicalAppUpdateJSON())
    let fetcher = GatedConfigFetcher(gate: gate, result: .success(
        ConfigFetchResult(document: document, signature: sign(document), etag: nil)))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    // A snapshot taken before a refresh is taken at the start of an operation
    // and used throughout (docs/CONFIG.md -> "How code consumes it", rule 1):
    // the sync/capture code that checks `allowsServerBacked` must not observe
    // the requirement flipping mid-flight.
    let before = store.snapshot()
    let refresh = Task { await store.refresh() }
    try await Task.sleep(for: .milliseconds(100))
    let during = store.snapshot()
    #expect(before.updateRequirement(runningVersion: "1.1.0")
            == during.updateRequirement(runningVersion: "1.1.0"))
    await gate.open()
    await refresh.value
}
