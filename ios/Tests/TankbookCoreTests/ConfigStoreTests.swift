import CryptoKit
import Foundation
import os
import Testing
@testable import TankbookCore

// P0.12b: config storage, resolution and ConfigStore (docs/CONFIG.md).
//
// These tests build their own signed documents at runtime from the fixture key
// (Fixtures/config/README.md documents the signing seed, bytes 0x01..0x20), so
// a document with any shape can be signed and presented to the store without
// inventing new fixture files. The canonicalizer and signature verifier from
// P0.12a are used as-is; nothing here re-verifies them.
//
// The cache directory is injected per test and is a fresh temp directory, never
// the real Application Support path; the real Keychain is replaced by an
// in-memory double (the real Keychain is unavailable in a plain `swift test`
// process, docs/CONFIG.md -> "Rollback floor in the Keychain").

// MARK: - Key and signing (fixture-derived)

private let signingSeed = Data((1...32).map { UInt8($0) })
private let signingKey: Curve25519.Signing.PrivateKey = {
    try! Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed)
}()

/// A structurally valid Ed25519 public key that does NOT match the fixture key,
/// used to prove verification runs on the read path against the injected key.
private let foreignPublicKeyBase64 = "Q83AI9ItX54QfRoGk0V9NdHRDrfSHHIRkvVvXeQGZdM="

private func fixtureVerifier() -> ConfigSignatureVerifier {
    ConfigSignatureVerifier(publicKey: signingKey.publicKey.rawRepresentation)
}

private func sign(_ document: Data) -> String {
    let canonical = try! ConfigCanonicalizer.canonicalize(document)
    return try! signingKey.signature(for: canonical).base64EncodedString()
}

private func isoDate(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

// MARK: - Document builder

/// Builds a complete, schema-valid config document as JSON bytes, with control
/// over every remote-configurable key's presence (docs/CONFIG.md -> "What may be
/// configured remotely"). Optional keys are omitted unless passed, which is what
/// makes the sparse-override tests meaningful.
private func makeDocument(
    version: Int = 7,
    issuedAt: String = "2026-01-01T00:00:00Z",
    notAfter: String = "2099-01-01T00:00:00Z",
    tier2: Bool = true,
    tier3: Bool = true,
    apiBaseURL: String? = nil,
    maintenance: String? = nil,
    appUpdate: String? = nil,
    flags: String? = nil,
    rolloutSalt: String = "test-salt",
    extra: [String: String] = [:]
) -> Data {
    var fields: [String] = [
        "\"version\": \(version)",
        "\"issuedAt\": \"\(issuedAt)\"",
        "\"notAfter\": \"\(notAfter)\"",
        "\"tier2OnDeviceLLM\": \(tier2)",
        "\"tier3CloudFallback\": \(tier3)",
        "\"llmQuota\": {\"onDeviceLLM\": 200, \"cloudFallback\": 50}",
        "\"ocrConfidenceThreshold\": 0.75",
        "\"minSchemaVersion\": 1",
        "\"referencePacks\": {\"rates\": 1, \"catalog\": 1}",
        "\"rolloutSalt\": \"\(rolloutSalt)\"",
    ]
    if let apiBaseURL { fields.append("\"apiBaseUrl\": \"\(apiBaseURL)\"") }
    if let maintenance { fields.append("\"maintenance\": \(maintenance)") }
    if let appUpdate { fields.append("\"appUpdate\": \(appUpdate)") }
    if let flags { fields.append("\"flags\": \(flags)") }
    for (key, value) in extra { fields.append("\"\(key)\": \(value)") }
    return Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
}

/// A fabricated bundled layer with distinctive values, so fall-through and
/// override are distinguishable in assertions.
private func makeBundled() -> AppConfig {
    let flags = "{\"pumpPhoto\":{\"enabled\":false,\"rolloutPercent\":0},"
        + "\"extraFlag\":{\"enabled\":true,\"rolloutPercent\":100}}"
    let data = makeDocument(
        apiBaseURL: "https://api.tankbook.live",
        maintenance: "{\"text\":\"Bundled maintenance\",\"severity\":\"info\",\"until\":\"2099-01-02T00:00:00Z\"}",
        flags: flags,
        rolloutSalt: "bundled-salt"
    )
    let document = try! ConfigDocument.parse(data)
    return AppConfig(document: document, apiBaseURL: document.apiBaseURL!)
}

// MARK: - Test doubles

private struct StubError: Error {}

private final class StubConfigFetcher: ConfigFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Result<ConfigFetchResult?, any Error>.success(nil))

    init(result: Result<ConfigFetchResult?, any Error>) {
        lock.withLock { $0 = result }
    }

    func set(result: Result<ConfigFetchResult?, any Error>) {
        lock.withLock { $0 = result }
    }

    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult? {
        let result = lock.withLock { $0 }
        return try result.get()
    }
}

private func successFetcher(document: Data, signature: String, etag: String? = nil) -> StubConfigFetcher {
    StubConfigFetcher(result: .success(ConfigFetchResult(document: document, signature: signature, etag: etag)))
}

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

// MARK: - Store factory

private let referenceNow = isoDate("2026-08-15T00:00:00Z")

private func makeStore(
    bundled: AppConfig,
    directory: URL,
    verifier: ConfigSignatureVerifier = fixtureVerifier(),
    keychain: any ConfigRollbackFloorStoring = InMemoryConfigRollbackFloor(),
    now: Date = referenceNow,
    deviceIdentifier: String = "device-test-1",
    fetcher: (any ConfigFetcher)? = nil,
    log: TankbookLog? = nil
) -> ConfigStore {
    ConfigStore(
        bundled: bundled,
        cacheDirectory: directory,
        verifier: verifier,
        keychain: keychain,
        clock: { now },
        deviceIdentifier: deviceIdentifier,
        fetcher: fetcher,
        log: log
    )
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("configstore-\(UUID().uuidString)")
}

private func cacheFileURL(directory: URL) -> URL {
    directory.appendingPathComponent("config.cache.json")
}

// MARK: - 1. Bootstrap

@Test func bootstrapWithNoCacheAndNoNetworkUsesBundledDefaults() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try ConfigDefaults.bundledAppConfig()
    let store = makeStore(bundled: bundled, directory: directory)

    #expect(store.current == bundled)
    #expect(store.current.apiBaseURL == URL(string: "https://api.tankbook.live")!)
    #expect(store.current.tier2OnDeviceLLM)
    #expect(store.current.tier3CloudFallback)
    #expect(store.current.minSchemaVersion == 1)
    #expect(store.current.maintenance == nil)
    // The bundled pump-photo flag is off, so the app is usable without rollout.
    #expect(store.isEnabled(.pumpPhoto) == false)
}

// MARK: - 2 and 3. Tampered document / signature rejected ON READ

@Test func tamperedDocumentIsRejectedOnReadAndFallsBackToBundled() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled() // tier3CloudFallback == true
    // A signed document that would set tier3 to false if accepted.
    let original = makeDocument(tier3: false)
    let signature = sign(original)
    // Tamper a field the code reads: flip tier3 back to true.
    let tamperedText = String(decoding: original, as: UTF8.self)
        .replacingOccurrences(of: "\"tier3CloudFallback\": false", with: "\"tier3CloudFallback\": true")
    #expect(tamperedText != String(decoding: original, as: UTF8.self))
    let tampered = Data(tamperedText.utf8)

    // Seed the cache with the tampered document and the ORIGINAL signature.
    let record = ConfigCacheRecord(document: tampered, signature: signature, etag: nil,
                                   fetchedAt: referenceNow, activeBaseURL: nil, consecutiveFailures: 0)
    try ConfigCacheFile.write(record, directory: directory)

    let store = makeStore(bundled: bundled, directory: directory)

    // Signature no longer matches the tampered bytes, so the document is
    // rejected whole and the bundled value stands.
    #expect(store.current.tier3CloudFallback == true)
}

@Test func tamperedSignatureIsRejectedOnReadAndFallsBackToBundled() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let document = makeDocument(tier3: false)
    let signatureBytes = Data(base64Encoded: sign(document))!
    var flipped = [UInt8](signatureBytes)
    flipped[0] ^= 0x01

    let record = ConfigCacheRecord(document: document, signature: Data(flipped).base64EncodedString(),
                                   etag: nil, fetchedAt: referenceNow, activeBaseURL: nil, consecutiveFailures: 0)
    try ConfigCacheFile.write(record, directory: directory)

    let store = makeStore(bundled: bundled, directory: directory)

    #expect(store.current.tier3CloudFallback == true)
}

// MARK: - 4, 5, 6. Rollback floor

@Test func versionBelowKeychainFloorIsRejectedEvenWhenValidlySigned() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let keychain = InMemoryConfigRollbackFloor()
    keychain.record(version: 7)

    let oldDocument = makeDocument(version: 5, tier3: false)
    let fetcher = successFetcher(document: oldDocument, signature: sign(oldDocument))
    let store = makeStore(bundled: bundled, directory: directory, keychain: keychain, fetcher: fetcher)

    await store.refresh()

    #expect(store.current.tier3CloudFallback == true, "a document below the floor must not apply")
    #expect(store.current.version == bundled.version)
}

@Test func cacheDeletedThenOldValidlySignedDocumentRejectedByFloor() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let keychain = InMemoryConfigRollbackFloor()

    // Step 1: a fresh install accepts version 7, which raises the floor.
    let v7 = makeDocument(version: 7, tier3: false)
    let fetcher = successFetcher(document: v7, signature: sign(v7))
    let first = makeStore(bundled: bundled, directory: directory, keychain: keychain, fetcher: fetcher)
    await first.refresh()
    #expect(first.current.tier3CloudFallback == false)

    // Step 2: the cache is deleted, but the Keychain floor survives.
    try FileManager.default.removeItem(at: cacheFileURL(directory: directory))
    #expect(ConfigCacheFile.read(directory: directory) == nil)

    // Step 3: a stale-but-validly-signed document is presented; the floor rejects it.
    let v5 = makeDocument(version: 5, tier3: true)
    let secondFetcher = successFetcher(document: v5, signature: sign(v5))
    let second = makeStore(bundled: bundled, directory: directory, keychain: keychain, fetcher: secondFetcher)
    await second.refresh()

    #expect(second.current.tier3CloudFallback == true, "a deleted cache must not reset the floor")
}

@Test func freshInstallAcceptsAValidDocument() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let v7 = makeDocument(version: 7, tier3: false)
    let fetcher = successFetcher(document: v7, signature: sign(v7))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    await store.refresh()

    #expect(store.current.tier3CloudFallback == false, "a fresh install has no floor and accepts the document")
    #expect(store.current.version == 7)
}

// MARK: - 7. Expiry

@Test func expiredDocumentIsRejectedAndBundledUsed() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    // notAfter is in the past relative to the injected clock (referenceNow).
    let expired = makeDocument(notAfter: "2026-01-01T00:00:00Z", tier3: false)
    let fetcher = successFetcher(document: expired, signature: sign(expired))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    await store.refresh()

    #expect(store.current.tier3CloudFallback == true, "an expired document must not apply")
}

// MARK: - 8. Empty-signature baseline (server migration 003)

@Test func emptySignaturePlaceholderIsRejected() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    // Migration 003 seeds config v1 with an EMPTY signature placeholder, signed
    // later at startup by ConfigBaselineSeeder. A client must reject that
    // transient unsigned state (docs/CONFIG.md; backend/…/Migrations/003_remote_config.up.sql).
    let document = makeDocument(tier3: false)
    let fetcher = successFetcher(document: document, signature: "")
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    await store.refresh()

    #expect(store.current.tier3CloudFallback == true, "an empty signature must be rejected")
}

// MARK: - 9. Unknown key ignored, retained in cache

@Test func unknownKeyIsIgnoredForResolutionAndRetainedInCache() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let document = makeDocument(
        tier3: false,
        extra: ["unknownFutureKey": "{\"nested\": {\"big\": 9007199254740993, \"list\": [1, \"2\"]}}"]
    )
    let fetcher = successFetcher(document: document, signature: sign(document))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    await store.refresh()

    // The known keys still apply.
    #expect(store.current.tier3CloudFallback == false)

    // The unknown key is retained verbatim in the cache bytes.
    let cacheBytes = try Data(contentsOf: cacheFileURL(directory: directory))
    let cacheText = String(decoding: cacheBytes, as: UTF8.self)
    #expect(cacheText.contains("unknownFutureKey"))
    #expect(cacheText.contains("9007199254740993"), "the oversized integer must survive verbatim")
}

// MARK: - 10. Sparse override

@Test func sparseOverrideChangesOnlyPresentKeys() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    // A valid document that omits apiBaseUrl, maintenance and flags, and flips
    // tier3 + rolloutSalt. Those two keys override; everything absent falls
    // through to bundled.
    let document = makeDocument(tier3: false, rolloutSalt: "remote-salt")
    let fetcher = successFetcher(document: document, signature: sign(document))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    await store.refresh()

    #expect(store.current.tier3CloudFallback == false, "present key overrides")
    #expect(store.current.rolloutSalt == "remote-salt", "present key overrides")
    #expect(store.current.apiBaseURL == bundled.apiBaseURL, "absent apiBaseUrl falls through")
    #expect(store.current.maintenance == bundled.maintenance, "absent maintenance falls through")
    #expect(store.current.flags == bundled.flags, "absent flags falls through")
    #expect(store.current.tier2OnDeviceLLM == bundled.tier2OnDeviceLLM)
    #expect(store.current.llmQuota == bundled.llmQuota)
    #expect(store.current.ocrConfidenceThreshold == bundled.ocrConfidenceThreshold)
    #expect(store.current.minSchemaVersion == bundled.minSchemaVersion)
    #expect(store.current.referencePacks == bundled.referencePacks)
}

// MARK: - 11. Corrupt cache

@Test func truncatedCorruptCacheFallsBackCleanly() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{\"document\":{\"version\":".utf8).write(to: cacheFileURL(directory: directory))

    let store = makeStore(bundled: bundled, directory: directory)

    #expect(store.current == bundled, "a corrupt cache must fall back to bundled without crashing")
}

// MARK: - 12. Atomic write

@Test func atomicWriteProducesAParseableCacheAndLeavesNoTemp() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let document = makeDocument(tier3: false, extra: ["zMystery": "{\"token\": 1e3}"])
    let record = ConfigCacheRecord(document: document, signature: sign(document), etag: "etag-1",
                                   fetchedAt: referenceNow, activeBaseURL: nil, consecutiveFailures: 0)
    try ConfigCacheFile.write(record, directory: directory)

    // The live cache parses and preserves the document byte-for-byte.
    let decoded = try #require(ConfigCacheFile.read(directory: directory))
    #expect(decoded.document == document)
    #expect(decoded.signature == record.signature)
    #expect(decoded.etag == "etag-1")
    #expect(decoded.fetchedAt == referenceNow)
    #expect(decoded.consecutiveFailures == 0)

    // No leftover temp file: the atomic rename consumed it.
    let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(contents == ["config.cache.json"], "unexpected files: \(contents)")
}

@Test func cacheCodecRoundTripsDocumentBytesVerbatim() throws {
    let document = makeDocument(extra: ["unknownFutureKey": "{\"nested\": 9007199254740993}", "zExp": "1e3"])
    let record = ConfigCacheRecord(document: document, signature: "abc", etag: nil,
                                   fetchedAt: referenceNow, activeBaseURL: "https://api.tankbook.live", consecutiveFailures: 3)

    let decoded = try ConfigCacheCodec.decode(ConfigCacheCodec.encode(record))

    #expect(decoded.document == document, "the document must round-trip byte-for-byte")
    #expect(decoded.signature == "abc")
    #expect(decoded.activeBaseURL == "https://api.tankbook.live")
    #expect(decoded.consecutiveFailures == 3)
}

// MARK: - 13. Snapshot semantics

@Test func snapshotTakenBeforeRefreshIsUnaffected() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let docA = makeDocument(tier3: false)
    let fetcher = successFetcher(document: docA, signature: sign(docA))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)

    await store.refresh()
    #expect(store.current.tier3CloudFallback == false)
    let before = store.snapshot()

    let docB = makeDocument(tier3: true)
    fetcher.set(result: .success(ConfigFetchResult(document: docB, signature: sign(docB), etag: nil)))
    // User-initiated: this test is about snapshot semantics, not the throttle,
    // so it bypasses the 6 h automatic-refresh window (the injected clock is
    // fixed at `referenceNow` and would otherwise skip the second fetch).
    await store.refresh(userInitiated: true)

    #expect(before.tier3CloudFallback == false, "the taken snapshot is the pre-refresh value")
    #expect(store.current.tier3CloudFallback == true, "the refreshed store reflects the new document")
}

// MARK: - 14. Rollout

@Test func rolloutIsStableAndZeroAndHundredAreExact() throws {
    // The pure rollout mechanism (docs/CONFIG.md -> "rolloutSalt + per-flag
    // rollout percentage"). Tested against ConfigRollout directly, because
    // `isEnabled(.pumpPhoto)` is additionally gated by PumpPhotoGate (P2.7) and
    // its shipped state is off.
    let offDoc = try ConfigDocument.parse(makeDocument(
        flags: "{\"pumpPhoto\":{\"enabled\":true,\"rolloutPercent\":0}}"))
    let offFeature = offDoc.flags["pumpPhoto"]!
    #expect(ConfigRollout.isEnabled(offFeature, salt: "s", deviceIdentifier: "d", flagName: "pumpPhoto") == false,
            "0% disables even when enabled=true")

    let onDoc = try ConfigDocument.parse(makeDocument(
        flags: "{\"pumpPhoto\":{\"enabled\":true,\"rolloutPercent\":100}}"))
    let onFeature = onDoc.flags["pumpPhoto"]!
    #expect(ConfigRollout.isEnabled(onFeature, salt: "s", deviceIdentifier: "d", flagName: "pumpPhoto") == true,
            "100% enables")

    // Stability: the same salt + device + flag lands in the same bucket.
    let midDoc = try ConfigDocument.parse(makeDocument(
        flags: "{\"pumpPhoto\":{\"enabled\":true,\"rolloutPercent\":50}}"))
    let midFeature = midDoc.flags["pumpPhoto"]!
    let results = (0..<20).map { _ in
        ConfigRollout.isEnabled(midFeature, salt: "s", deviceIdentifier: "d", flagName: "pumpPhoto")
    }
    #expect(Set(results).count == 1, "rollout must be stable across calls")
}

// MARK: - P2.7: the pump-photo accuracy gate is not remotely flippable

@Test func pumpPhotoShipsOffInTheBundledDefault() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try ConfigDefaults.bundledAppConfig()
    #expect(bundled.flags["pumpPhoto"]?.enabled == false,
            "the bundled default must ship pumpPhoto off")

    let store = makeStore(bundled: bundled, directory: directory)
    #expect(store.isEnabled(.pumpPhoto) == false)
}

@Test func remoteConfigCannotEnablePumpPhotoWhileTheGateFails() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // A config that tries to enable pumpPhoto at 100% rollout. The accuracy gate
    // (PumpPhotoGate, measured below the precision/coverage gate) must keep the
    // flag off regardless - a remote document cannot flip an accuracy gate into
    // truth (docs/CONFIG.md -> "Config can never disable a security control").
    let onData = makeDocument(apiBaseURL: "https://api.tankbook.live",
                              flags: "{\"pumpPhoto\":{\"enabled\":true,\"rolloutPercent\":100}}")
    let onDoc = try ConfigDocument.parse(onData)
    let onBundled = AppConfig(document: onDoc, apiBaseURL: onDoc.apiBaseURL!)
    let store = makeStore(bundled: onBundled, directory: directory)

    #expect(store.isEnabled(.pumpPhoto) == false,
            "the accuracy gate must keep pumpPhoto off despite a 100% rollout")
}

// MARK: - 15. Key coverage

@Test func everyRemoteConfigurableKeyMapsToAnAppConfigField() async {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    let document = makeDocument(
        version: 7,
        tier2: false,
        tier3: true,
        apiBaseURL: "https://other.tankbook.live",
        maintenance: "{\"text\":\"Scheduled\",\"severity\":\"warning\",\"until\":\"2099-01-02T00:00:00Z\"}",
        appUpdate: "{\"minSupportedVersion\": \"1.2.0\", \"latestVersion\": \"1.4.0\"}",
        flags: "{\"pumpPhoto\":{\"enabled\":true,\"rolloutPercent\":33}}",
        rolloutSalt: "salt-remote"
    )
    let fetcher = successFetcher(document: document, signature: sign(document))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher)
    await store.refresh()

    let config = store.current
    #expect(config.apiBaseURL == URL(string: "https://other.tankbook.live")!)
    #expect(config.tier2OnDeviceLLM == false)
    #expect(config.tier3CloudFallback == true)
    #expect(config.llmQuota.onDeviceLLM == 200)
    #expect(config.llmQuota.cloudFallback == 50)
    #expect(config.ocrConfidenceThreshold == 0.75)
    #expect(config.minSchemaVersion == 1)
    #expect(config.referencePacks.rates == 1)
    #expect(config.referencePacks.catalog == 1)
    #expect(config.maintenance?.severity == .warning)
    #expect(config.appUpdate == ConfigDocument.AppUpdateNotice(
        minSupportedVersion: AppVersion("1.2.0")!,
        latestVersion: AppVersion("1.4.0")!))
    #expect(config.updateRequirement(runningVersion: "1.3.0") == .recommended,
            "the store-level snapshot must carry a decidable requirement (P6.18a)")
    #expect(config.rolloutSalt == "salt-remote")
    #expect(config.flags["pumpPhoto"]?.rolloutPercent == 33)
    #expect(config.version == 7)
}

// MARK: - 16. Cold-start read verifies the signature

@Test func coldStartReadVerifiesSignatureAgainstTheInjectedKey() throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = makeBundled()
    // A perfectly valid, fixture-signed cache entry.
    let document = makeDocument(tier3: false)
    let record = ConfigCacheRecord(document: document, signature: sign(document), etag: nil,
                                   fetchedAt: referenceNow, activeBaseURL: nil, consecutiveFailures: 0)
    try ConfigCacheFile.write(record, directory: directory)

    // A store whose verifier holds a DIFFERENT public key must reject the
    // document on the cache-read path: verification runs on every read, not
    // only after a fetch.
    let store = makeStore(bundled: bundled, directory: directory,
                          verifier: ConfigSignatureVerifier(publicKeyBase64: foreignPublicKeyBase64))

    #expect(store.current.tier3CloudFallback == true,
            "a cache whose signature does not verify against the injected key must be rejected on read")
}

// MARK: - Logging (docs/CONFIG.md -> "Logging")

@Test func applyAndRejectEventsAreEmittedWithFieldNamesNotValues() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: { LogContext(deviceId: nil, appVersion: "test", platform: "ios") })

    let bundled = makeBundled()
    let document = makeDocument(tier3: false)
    let fetcher = successFetcher(document: document, signature: sign(document))
    let store = makeStore(bundled: bundled, directory: directory, fetcher: fetcher, log: log)
    await store.refresh()

    let events = sink.all().map(\.event)
    #expect(events.contains("config.apply"), "a successful refresh must emit config.apply")

    let applyText = sink.rendered().first { $0.contains("event=config.apply") && $0.contains("source=live") }
    #expect(applyText != nil, "a live apply must be logged with source=live")
    guard let applyText else { return }
    #expect(applyText.contains("version=7"))
    #expect(applyText.contains("changedKeys=") && applyText.contains("tier3CloudFallback"))
    #expect(!applyText.contains("api.tankbook"), "the log must not dump the document body")

    // A rejected document emits config.reject. User-initiated: the first store
    // above wrote a cache to this same directory, so a background refresh here
    // would be throttled (the injected clock is fixed) and never reach the
    // reject path.
    let badStore = makeStore(bundled: bundled, directory: directory,
                             fetcher: successFetcher(document: document, signature: "garbage"), log: log)
    await badStore.refresh(userInitiated: true)

    let rejectText = sink.rendered().filter { $0.contains("event=config.reject") }
    #expect(!rejectText.isEmpty, "a bad signature must emit config.reject")
    #expect(rejectText.contains { $0.contains("reason=badSignature") })
}
