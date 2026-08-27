import Foundation
import os
import Testing
@testable import TankbookCore

// P5.7 - vehicle catalog client updater (docs/SYNC.md -> Reference data,
// docs/ERRORS.md -> Vehicle catalog updates): the cached layer, three-layer
// resolution, validation whole-or-not-at-all, rollback protection, the silent
// failure contract, the atomic cache write, backup exclusion and the curation
// miss counter. Every test runs on macOS with no sockets (an injected
// transport/fetcher double stands in for URLSession) and uses a real temp
// directory for the cache - never a mocked filesystem.

// MARK: - Test doubles

private struct NoAuthTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}

/// A fetcher double that returns scripted packs (or throws) and records the
/// `since_version` each call asked for.
private final class StubCatalogFetcher: VehicleCatalogFetcher, @unchecked Sendable {
    struct Call: Equatable {
        let sinceVersion: Int
    }

    private let lock = OSAllocatedUnfairLock(
        initialState: (scripts: [Result<VehicleCatalogPack?, any Error>](), calls: [Call]()))

    func script(_ result: Result<VehicleCatalogPack?, any Error>) {
        lock.withLock { $0.scripts.append(result) }
    }

    func script(_ pack: VehicleCatalogPack?) {
        script(.success(pack))
    }

    func fetchPack(sinceVersion: Int) async throws -> VehicleCatalogPack? {
        let result: Result<VehicleCatalogPack?, any Error> = lock.withLock { state in
            state.calls.append(Call(sinceVersion: sinceVersion))
            return state.scripts.isEmpty ? .success(nil) : state.scripts.removeFirst()
        }
        return try result.get()
    }

    func calls() -> [Call] {
        lock.withLock { $0.calls }
    }

    func clearCalls() {
        lock.withLock { $0.calls = [] }
    }
}

/// A transport double for the fetcher-level tests.
private final class RecordingTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(
        initialState: (received: [TankbookHTTPRequest](), responses: [TankbookHTTPResponse]()))

    func script(_ response: TankbookHTTPResponse) {
        lock.withLock { $0.responses.append(response) }
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

/// A mutable clock so the throttle can be advanced deterministically.
private final class ClockBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))

    func set(_ date: Date) {
        lock.withLock { $0 = date }
    }

    var now: Date {
        lock.withLock { $0 }
    }
}

// MARK: - Helpers

private func tempCacheDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tankbook-catalog-tests-\(UUID().uuidString)")
}

private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// A fabricated bundled seed, version 2 like the shipped pack, with a Volvo V60
/// (tank 71) so tests assert the replaced FIELD value, not just counts.
private func makeBundledSeed() -> [VehicleCatalogEntry] {
    [
        VehicleCatalogEntry(make: "Volvo", model: "V60", generation: "SPA",
                            years: [2018, nil], powertrain: .ice,
                            fuelKinds: [.petrol95, .diesel], tankCapacityL: 71,
                            batteryCapacityKWh: nil, packVersion: 2),
        VehicleCatalogEntry(make: "Volvo", model: "XC60", generation: "SPA",
                            years: [2017, nil], powertrain: .ice,
                            fuelKinds: [.petrol95, .diesel], tankCapacityL: 71,
                            batteryCapacityKWh: nil, packVersion: 2),
        VehicleCatalogEntry(make: "Toyota", model: "Corolla", generation: "E210",
                            years: [2018, nil], powertrain: .hybrid,
                            fuelKinds: [.petrol95, .electricity], tankCapacityL: 43,
                            batteryCapacityKWh: nil, packVersion: 2)
    ]
}

/// A corrected V60 from a hypothetical server pack: same model-line identity as
/// the seed, corrected figures. This is what the master rule must substitute in.
private func correctedV60(tank: Double, id: String = "11111111-1111-1111-1111-111111111111",
                          version: Int) -> VehicleCatalogEntry {
    VehicleCatalogEntry(id: id, make: "Volvo", model: "V60", generation: "SPA",
                        years: [2018, 2024], powertrain: .ice,
                        fuelKinds: [.petrol95, .diesel], tankCapacityL: tank,
                        batteryCapacityKWh: nil, packVersion: version)
}

private func makeLog() -> (TankbookLog, InMemorySink) {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-test-0001", appVersion: "9.9.9-test", platform: "ios")
    })
    return (log, sink)
}

// MARK: - Wire builders (the body as the server shipped it, camelCase)

private func packJSON(version: Int, entries: [String]) -> Data {
    Data("{ \"packVersion\": \(version), \"entries\": [\(entries.joined(separator: ","))] }".utf8)
}

private func v60EntryJSON(id: String = "11111111-1111-1111-1111-111111111111",
                          tank: String = "71", years: String = "[2018, 2024]") -> String {
    "{ \"id\": \"\(id)\", \"make\": \"Volvo\", \"model\": \"V60\", \"generation\": \"SPA\", "
        + "\"years\": \(years), \"powertrain\": \"ice\", \"fuelKinds\": [\"petrol95\",\"diesel\"], "
        + "\"tankCapacityL\": \(tank), \"batteryCapacityKwh\": null }"
}

// MARK: - 1. Day one, offline (hard rule 1)

@Test func dayOneOfflineWithoutCacheOrNetworkSeedStillAnswers() {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir)

    let suggestion = updater.suggestions(for: "volvo v60").first
    #expect(suggestion?.entry.title == "Volvo V60")
    #expect(suggestion?.entry.tankCapacityL == 71)
    #expect(updater.heldPackVersion == 2)
    // A pure-bundled cold start writes nothing to disk.
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("catalog.cache.json").path))
}

// MARK: - 2. The master rule: overlap replaces, and the replaced field proves it

@Test func serverEntryOverlappingSeedReplacesItNotMergesIt() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 60, version: 3)]))
    await updater.refresh()

    // The REPLACED FIELD VALUE, not the entry count: the corrected tank wins.
    let suggestion = try #require(updater.suggestions(for: "volvo v60").first)
    #expect(suggestion.entry.tankCapacityL == 60)
    #expect(suggestion.entry.packVersion == 3)
    #expect(suggestion.entry.id == "11111111-1111-1111-1111-111111111111")
    #expect(updater.heldPackVersion == 3)

    // Exactly one V60 - replaced in place, never merged into two.
    let v60s = updater.suggestions(for: "v60", limit: 20).filter { $0.entry.model == "V60" }
    #expect(v60s.count == 1)

    // Unchanged model lines keep the seed values.
    #expect(updater.suggestions(for: "xc60").first?.entry.tankCapacityL == 71)
}

// MARK: - 3. The master rule's limit: a corrected pack never rewrites a Vehicle

/// Encodes with `.sortedKeys`: JSONEncoder's key order is hash-ordered and
/// differs between encoder instances (a Swift runtime property), so a byte
/// comparison needs a canonical form. Sorted keys make "byte-identical" a real
/// assertion rather than a key-ordering accident.
private func deterministicEncode(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

@Test func correctedPackNeverRewritesASavedVehicleByteIdentical() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)

    // Save a car pre-filled from the seed, with the tank the USER typed over.
    let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
    let seedV60 = try #require(updater.suggestions(for: "volvo v60").first).entry
    let prefill = seedV60.prefill(currentYear: 2026)
    let saved = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "\(prefill.make) \(prefill.model)", make: prefill.make, model: prefill.model,
        year: prefill.year, plate: nil, powertrain: prefill.powertrain,
        fuelKinds: prefill.fuelKinds, tankCapacityL: 60, batteryCapacityKWh: prefill.batteryCapacityKWh,
        homeCurrency: .rub,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500)
    try repository.upsertVehicle(saved)
    let savedBytes = try deterministicEncode(saved)

    // A corrected pack changes the catalog's figure for the same model line.
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 80, version: 3)]))
    await updater.refresh()
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 80)

    // The garage is untouched: re-read and re-encode is byte-identical, and the
    // user's override (60, not the seed's 71 or the pack's 80) is intact.
    let reloaded = try #require(try repository.vehicle(id: saved.id))
    #expect(try deterministicEncode(reloaded) == savedBytes)
    #expect(reloaded == saved)
    #expect(reloaded.tankCapacityL == 60)
}

// MARK: - 4. Malformed / invalid pack rejected whole; the old pack serves

@Test func structurallyMalformedPackIsRejectedWholeAndOldPackServes() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    // A good pack v3 lands first.
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 60, version: 3)]))
    await updater.refresh()
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 60)

    // Then a structurally malformed body arrives - rejected whole.
    fetcher.script(.failure(CatalogFetchError.invalidResponse))
    await updater.refresh()

    // Re-QUERY, don't just assert no throw: the OLD pack still serves.
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 60)
    #expect(updater.heldPackVersion == 3)
}

@Test func semanticallyInvalidPackIsRejectedWholeAndOldPackServes() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 60, version: 3)]))
    await updater.refresh()

    // A pack that decodes but has no model name is not a plausible catalog: it
    // must be rejected WHOLE by validation, never partially applied.
    let noName = VehicleCatalogEntry(id: "22222222-2222-2222-2222-222222222222",
                                     make: "Volvo", model: "", generation: "SPA",
                                     years: [2018, 2024], powertrain: .ice,
                                     fuelKinds: [.petrol95], tankCapacityL: 55,
                                     batteryCapacityKWh: nil, packVersion: 4)
    fetcher.script(VehicleCatalogPack(packVersion: 4, entries: [noName]))
    await updater.refresh()

    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 60)
    #expect(updater.heldPackVersion == 3)
}

@Test func negativeCapacityRejectsTheWholePack() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    let absurd = VehicleCatalogEntry(id: "22222222-2222-2222-2222-222222222222",
                                     make: "Volvo", model: "V60", generation: "SPA",
                                     years: [2018, 2024], powertrain: .ice,
                                     fuelKinds: [.petrol95], tankCapacityL: -5,
                                     batteryCapacityKWh: nil, packVersion: 4)
    fetcher.script(VehicleCatalogPack(packVersion: 4, entries: [absurd]))
    await updater.refresh()

    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 71)
    #expect(updater.heldPackVersion == 2)
}

// MARK: - 5. Rollback protection: lower AND equal are both ignored

@Test func olderAndEqualPacksAreIgnoredRollbackProtection() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 5, entries: [correctedV60(tank: 55, version: 5)]))
    await updater.refresh()
    #expect(updater.heldPackVersion == 5)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 55)

    // A LOWER version is a rollback and is ignored.
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 40, version: 3)]))
    await updater.refresh()
    #expect(updater.heldPackVersion == 5)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 55)

    // An EQUAL version is ignored too - `>` vs `>=` is the likely bug.
    fetcher.script(VehicleCatalogPack(packVersion: 5, entries: [correctedV60(tank: 30, version: 5)]))
    await updater.refresh()
    #expect(updater.heldPackVersion == 5)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 55)
}

@Test func honestEmptyDeltaIsNotAnErrorAndChangesNothing() async throws {
    // `since_version` at or above the current version answers an honest empty
    // delta `{ packVersion, entries: [] }` - not an error, not an empty catalog.
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 2, entries: []))
    await updater.refresh()

    // Equal version: ignored (rollback protection). The seed still serves.
    #expect(updater.heldPackVersion == 2)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 71)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.packVersion == 2)
}

// MARK: - 6. Truncated cache falls back to the seed pack

@Test func truncatedCacheFallsBackToSeedPack() {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // A truncated file - exactly what a crash mid-write must never leave behind.
    let url = dir.appendingPathComponent("catalog.cache.json")
    try? Data(#"{"packVersion": 9, "entries": [{"make":"Volvo""#.utf8).write(to: url)

    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 71)
    // The seed version is held, not the truncated 9.
    #expect(updater.heldPackVersion == 2)
}

@Test func cacheWithWrongShapeFallsBackToSeedPack() {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Valid JSON, but not a catalog cache envelope.
    let url = dir.appendingPathComponent("catalog.cache.json")
    try? Data(#"{"whatever": true}"#.utf8).write(to: url)

    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 71)
    #expect(updater.heldPackVersion == 2)
}

// MARK: - 7. Atomic write: temp is never the final path

@Test func cacheIsWrittenAtomicallyAndTheTempPathIsNeverFinal() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 60, version: 3)]))
    await updater.refresh()

    let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    // No `.tmp-*` residue: the temp file was renamed over the final, never left.
    #expect(contents.allSatisfy { !$0.contains(".tmp-") })
    #expect(contents.contains("catalog.cache.json"))

    // The final file parses and round-trips the applied pack.
    let record = try #require(VehicleCatalogCacheFile.read(directory: dir))
    #expect(record.packVersion == 3)
    #expect(record.entries.first { $0.model == "V60" }?.tankCapacityL == 60)
}

// MARK: - 8. Excluded from backups

@Test func cacheFileIsExcludedFromBackups() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 60, version: 3)]))
    await updater.refresh()

    let url = dir.appendingPathComponent("catalog.cache.json")
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
}

// MARK: - 9. Every failure is silent

@Test func everyFailureIsSilentAndTheSuggestionSurfaceKeepsWorking() async throws {
    let seed = makeBundledSeed()
    let failureModes: [(String, Result<VehicleCatalogPack?, any Error>)] = [
        ("transport", .failure(CatalogFetchError.transportUnavailable)),
        ("5xx", .failure(CatalogFetchError.badStatus(503))),
        ("malformed body", .failure(CatalogFetchError.invalidResponse)),
        ("old pack (rollback)", .success(VehicleCatalogPack(packVersion: 1,
                                                            entries: [correctedV60(tank: 30, version: 1)])))
    ]
    for (name, result) in failureModes {
        let dir = tempCacheDirectory()
        defer { remove(dir) }
        let fetcher = StubCatalogFetcher()
        let updater = VehicleCatalogUpdater(bundled: seed, cacheDirectory: dir,
                                            fetcher: fetcher, minimumFetchInterval: 0)
        fetcher.script(result)

        // refresh() never throws - there is no error surface (docs/ERRORS.md).
        await updater.refresh()

        // The suggestion surface keeps serving the seed.
        let suggestion = updater.suggestions(for: "volvo v60").first
        #expect(suggestion?.entry.title == "Volvo V60", "\(name): surface broke")
        #expect(suggestion?.entry.tankCapacityL == 71, "\(name): seed value lost")
        #expect(updater.heldPackVersion == 2, "\(name): version drifted")
    }
}

// MARK: - 10. The curation miss counter never carries the typed text

@Test func catalogMissIsCountedWithoutTheTypedText() {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let (log, sink) = makeLog()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir, log: log)

    // A search that missed. recordCatalogMiss() takes NO text - the API is
    // shaped so the typed string can never be captured (hard rule 12).
    _ = "Chevrolet Impala 2024 SS"
    updater.recordCatalogMiss()
    updater.recordCatalogMiss()

    #expect(updater.catalogMissCount == 2)
    let lines = sink.rendered()
    let missLines = lines.filter { $0.contains("catalog.miss") }
    #expect(missLines.count == 2)
    for line in missLines {
        #expect(line.contains("totalCount="), "the count is what is logged")
    }
    // The search string appears in NO rendered line at all.
    #expect(!lines.contains { $0.contains("Chevrolet") })

    // The tally survives a relaunch via the cache file.
    let reloaded = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir)
    #expect(reloaded.catalogMissCount == 2)
}

// MARK: - Layer survival across relaunch

@Test func cachedPackSurvivesRelaunchAndOutranksTheSeed() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let first = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                      fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack(packVersion: 4, entries: [correctedV60(tank: 66, version: 4)]))
    await first.refresh()

    // A second updater - a relaunch - resolves from the cache with NO fetch and
    // holds the cache's version for the next `since_version`.
    let relaunched = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir)
    #expect(relaunched.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 66)
    #expect(relaunched.heldPackVersion == 4)
}

// MARK: - 304 and the since_version query

@Test func a304MeansNothingToDo() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    fetcher.script(VehicleCatalogPack?.none)
    await updater.refresh()

    #expect(updater.heldPackVersion == 2)
    #expect(updater.suggestions(for: "volvo v60").first?.entry.tankCapacityL == 71)
    // Nothing happened, so nothing was written.
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("catalog.cache.json").path))
}

@Test func refreshSendsTheHeldVersionAsSinceVersion() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, minimumFetchInterval: 0)
    await updater.refresh()
    #expect(fetcher.calls().map(\.sinceVersion) == [2])
}

// MARK: - Background and throttled

@Test func refreshIsThrottledAndReentrancySafe() async throws {
    let dir = tempCacheDirectory()
    defer { remove(dir) }
    let fetcher = StubCatalogFetcher()
    let clockBox = ClockBox()
    let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                        fetcher: fetcher, clock: { clockBox.now },
                                        minimumFetchInterval: 3600)
    fetcher.script(VehicleCatalogPack(packVersion: 3, entries: [correctedV60(tank: 60, version: 3)]))
    await updater.refresh()
    #expect(updater.heldPackVersion == 3)
    fetcher.clearCalls()

    // Immediately again: inside the minimum interval -> a no-op, no fetch.
    await updater.refresh()
    #expect(fetcher.calls().isEmpty)

    // Past the interval the fetch happens again.
    clockBox.set(clockBox.now.addingTimeInterval(3601))
    fetcher.script(VehicleCatalogPack(packVersion: 4, entries: [correctedV60(tank: 62, version: 4)]))
    await updater.refresh()
    #expect(fetcher.calls().count == 1)
    #expect(updater.heldPackVersion == 4)
}

// MARK: - Fetcher: the wire, exactly as the server shipped it

@Test func fetcherBuildsThePublicSinceVersionQueryAndReadsA304() async throws {
    let transport = RecordingTransport()
    transport.script(TankbookHTTPResponse(status: 304, body: nil))
    let fetcher = RemoteVehicleCatalogFetcher(baseURL: URL(string: "https://api.tankbook.app")!,
                                              transport: transport, tokenProvider: NoAuthTokenProvider())

    let pack = try await fetcher.fetchPack(sinceVersion: 7)
    #expect(pack == nil, "a 304 means nothing to do")

    let sent = transport.receivedRequests()
    #expect(sent.count == 1)
    let components = URLComponents(url: sent[0].url, resolvingAgainstBaseURL: false)
    #expect(components?.path == "/v1/catalog")
    let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["since_version"] == "7")
    #expect(sent[0].headers["Authorization"] == nil)
}

@Test func packDecodesExactlyFromTheWire() throws {
    let body = packJSON(version: 7, entries: [
        v60EntryJSON(id: "11111111-1111-1111-1111-111111111111", tank: "71", years: "[2018, 2024]"),
        // An open-ended model line arrives as years: null; generation may be null.
        #"{"id":"22222222-2222-2222-2222-222222222222","make":"Tesla","model":"Model 3","#
            + #""generation":null,"years":null,"powertrain":"ev","fuelKinds":["electricity"],"#
            + #""tankCapacityL":null,"batteryCapacityKwh":60}"#
    ])
    let pack = try RemoteVehicleCatalogFetcher.decodePack(body)
    #expect(pack.packVersion == 7)

    let v60 = try #require(pack.entries.first { $0.model == "V60" })
    #expect(v60.id == "11111111-1111-1111-1111-111111111111")
    #expect(v60.years == [2018, 2024], "inclusive pair, not half-open")
    #expect(v60.yearsEnd == 2024)
    #expect(v60.tankCapacityL == 71)

    let tesla = try #require(pack.entries.first { $0.model == "Model 3" })
    #expect(tesla.years == [nil, nil])
    #expect(tesla.yearsEnd == nil)
    #expect(tesla.generation == "")
    #expect(tesla.batteryCapacityKWh == 60)
}

@Test func unknownPowertrainOrFuelKindRejectsThePackWhole() throws {
    let unknownPowertrain = packJSON(version: 8, entries: [
        v60EntryJSON().replacingOccurrences(of: "\"powertrain\": \"ice\"",
                                            with: "\"powertrain\": \"warp\"")
    ])
    #expect(throws: CatalogFetchError.invalidResponse) {
        _ = try RemoteVehicleCatalogFetcher.decodePack(unknownPowertrain)
    }

    let unknownFuel = packJSON(version: 8, entries: [
        v60EntryJSON().replacingOccurrences(of: "[\"petrol95\",\"diesel\"]",
                                            with: "[\"hydrofluorocarbons\"]")
    ])
    #expect(throws: CatalogFetchError.invalidResponse) {
        _ = try RemoteVehicleCatalogFetcher.decodePack(unknownFuel)
    }
}

@Test func catalogFetcherRefusesNonAllowlistedHost() async throws {
    let transport = RecordingTransport()
    let fetcher = RemoteVehicleCatalogFetcher(baseURL: URL(string: "https://evil.com")!,
                                              transport: transport, tokenProvider: NoAuthTokenProvider())
    await #expect(throws: CatalogFetchError.transportUnavailable) {
        _ = try await fetcher.fetchPack(sinceVersion: 2)
    }
    #expect(transport.receivedRequests().isEmpty,
            "a non-allowlisted host must never reach the transport")
}
