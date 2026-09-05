import Foundation
import Testing
@testable import TankbookCore

// OB.4 - the "Attach diagnostics" bundle carries what docs/LOGGING.md §5
// promises: the 24 h log window (ring + OSLog, every line re-redacted), the sync
// state (last success, dirty/flagged counts, the last failure's kind + code +
// traceId) and per-table row counts - and NOTHING that would let someone profile
// the user (hard rule 12). The headline test is the privacy sweep over the whole
// rendered output, modelled on OB.2's `everyEventThisRowAddsIsFreeOfDomainValues`.

private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

private func testContext() -> LogContext {
    LogContext(deviceId: "device-ob4-0001", appVersion: "9.9.9-test", platform: "ios")
}

private func makeLog(sink: InMemorySink, breadcrumbs: Breadcrumbs? = nil) -> TankbookLog {
    TankbookLog(sink: sink, context: { testContext() }, breadcrumbs: breadcrumbs)
}

private func makeRepo() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

// MARK: - Reader doubles (the OSLogStore path is a seam; asserting on the real
// unified log from a unit test would be both flaky and vacuous - the brief names
// that trap)

private struct ThrowingOSLogReader: OSLogEntryReading {
    func readInfoPlus(subsystem: String, since: Date, limit: Int) throws -> [OSLogCollectedEntry] {
        throw NSError(domain: "OB4.test", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no unified log in a test"])
    }
}

private struct FixtureOSLogReader: OSLogEntryReading {
    let entries: [OSLogCollectedEntry]
    func readInfoPlus(subsystem: String, since: Date, limit: Int) throws -> [OSLogCollectedEntry] {
        entries
    }
}

// A deliberately DISTINCTIVE station name, note and amount so the sweep has real
// needles (docs/LOGGING.md §7) - values that cannot be spelled by a timestamp or
// a duration, so no clock-field collision (LOGGING.md §1 "do not sweep the clock").
private struct SeededValues {
    let stationName = "Zvezda-Lubricants-77"
    let note = "timing-belt-service-ob4"
    let amount = "64.20"
    let vehicle: Vehicle
    let station: Station
    let fillUp: FillUp

    init() {
        vehicle = Vehicle(
            id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
            name: "OB4 Fixture Car", make: "Volvo", model: "V60", year: 2019,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil
        )
        station = Station(
            id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
            name: stationName, brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil)
        )
        fillUp = FillUp(
            id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
            vehicleId: vehicle.id, date: epoch, odometer: 119_486,
            money: Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur),
            note: note, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.3, unitPrice: Decimal(string: "1.529")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: station.id, crossCheck: .verified, extraction: nil
        )
    }
}

/// The OB.4 suite.
@Suite("OB.4 diagnostics export")
struct OB4DiagnosticsExportTests {

    // MARK: - The bundle carries the sync fields (docs/LOGGING.md §5)

    @Test("the rendered bundle carries last success, the failure's kind+code+traceId and the counts")
    func bundleCarriesTheSyncFields() {
        let sink = InMemorySink()
        let log = makeLog(sink: sink, breadcrumbs: Breadcrumbs())
        let successAt = Date(timeIntervalSinceReferenceDate: 123_456)
        let failure = SyncFailureRecord(at: successAt.addingTimeInterval(3600),
                                        kind: .authExpired, code: "token_invalid",
                                        traceId: "ob4-0001")
        let sync = DiagnosticsSyncSummary(lastSuccessAt: successAt,
                                          dirtyCount: 3, flaggedCount: 1,
                                          lastFailure: failure)

        let bundle = DiagnosticsExport.collect(log: log, context: testContext(),
                                               osLog: nil, sync: sync, rowCounts: [:])
        let text = bundle.rendered()

        // The last successful cycle and the whole failure record: the kind (a
        // code), the raw wire `code`, and the `traceId` that maps the report to
        // the server's own lines (docs/LOGGING.md §2). Dropping any one of these
        // fails this test (mutation 2 drops the traceId).
        #expect(text.contains("lastSuccessAt=\(LogRenderer.timestamp(successAt))"))
        #expect(text.contains("lastFailureAt=\(LogRenderer.timestamp(failure.at))"))
        #expect(text.contains("lastFailureKind=authExpired"))
        #expect(text.contains("lastFailureCode=token_invalid"))
        #expect(text.contains("lastFailureTraceId=ob4-0001"))
        #expect(text.contains("dirtyCount=3"))
        #expect(text.contains("flaggedCount=1"))
    }

    @Test("a nil-code, nil-traceId failure (an offline cycle) renders its kind and omits the absent fields")
    func bundleRendersNilCodeAndTraceAbsent() {
        let sink = InMemorySink()
        let log = makeLog(sink: sink)
        let failure = SyncFailureRecord(at: epoch, kind: .offline, code: nil, traceId: nil)
        let sync = DiagnosticsSyncSummary(lastSuccessAt: nil, dirtyCount: 2, flaggedCount: 0,
                                          lastFailure: failure)

        let bundle = DiagnosticsExport.collect(log: log, context: testContext(),
                                               osLog: nil, sync: sync, rowCounts: [:])
        let text = bundle.rendered()

        #expect(text.contains("lastFailureKind=offline"))
        #expect(!text.contains("lastFailureCode="),
                "an offline cycle has no server code and must not render an empty one")
        #expect(!text.contains("lastFailureTraceId="))
        #expect(!text.contains("lastSuccessAt="),
                "no successful cycle means no lastSuccessAt line")
    }

    // MARK: - DB row counts appear as counts

    @Test("row counts appear as counts over a real repository")
    func rowCountsAppearAsCounts() throws {
        let repo = try makeRepo()
        let seed = SeededValues()
        try repo.upsertVehicle(seed.vehicle)
        try repo.upsertStation(seed.station)
        try repo.upsertFillUp(seed.fillUp)
        var secondFill = seed.fillUp
        secondFill.id = UUID.v7()
        try repo.upsertFillUp(secondFill)
        let vehicle = Vehicle(id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
                              name: "OB4 Second", make: "Audi", model: "A4", year: 2020,
                              plate: nil, powertrain: .ice, fuelKinds: [.petrol98],
                              tankCapacityL: 58, batteryCapacityKWh: nil, homeCurrency: .eur,
                              units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                                    energy: .kWhPer100),
                              photo: nil)
        try repo.upsertVehicle(vehicle)

        let sink = InMemorySink()
        let log = makeLog(sink: sink)
        let counts = ["vehicle": try repo.rowCount(in: TankbookSchema.vehicle),
                      "fillUp": try repo.rowCount(in: TankbookSchema.fillUp),
                      "serviceRecord": try repo.rowCount(in: TankbookSchema.serviceRecord)]
        let bundle = DiagnosticsExport.collect(log: log, context: testContext(),
                                               osLog: nil, sync: nil, rowCounts: counts)
        let text = bundle.rendered()

        #expect(text.contains("rowCount.vehicle=2"))
        #expect(text.contains("rowCount.fillUp=2"))
        #expect(text.contains("rowCount.serviceRecord=0"))
    }

    // MARK: - THE privacy sweep over the whole rendered bundle

    @Test("the whole rendered bundle is free of seeded domain values")
    func wholeRenderedBundleIsFreeOfDomainValues() throws {
        let repo = try makeRepo()
        let seed = SeededValues()
        try repo.upsertVehicle(seed.vehicle)
        try repo.upsertStation(seed.station)
        try repo.upsertFillUp(seed.fillUp)

        // A log whose breadcrumbs were recorded while that repository held the
        // values: an event that (carelessly) carried them classified as Sensitive.
        let sink = InMemorySink()
        let crumbs = Breadcrumbs()
        let log = makeLog(sink: sink, breadcrumbs: crumbs)
        let fixture = OB4PopulatedEntityLog(seed: seed)
        log.emit(fixture)
        #expect(crumbs.snapshot().count == 1)

        // The OSLog window is replayed as a DEBUG-reveal would have persisted it:
        // RAW lines whose values carry the needles. The collector's OSLog redactor
        // is the only thing between these lines and the bundle - removing it
        // (mutation 1) must fail this sweep.
        let leakedLine = "\(LogRenderer.timestamp(epoch)) INFO [sync] event=sync.merge "
            + "stationName=\(seed.stationName) note=\(seed.note) amount=\(seed.amount)"
        let osLog = FixtureOSLogReader(entries: [
            OSLogCollectedEntry(date: epoch, text: leakedLine)
        ])

        let sync = DiagnosticsSyncSummary(
            lastSuccessAt: epoch, dirtyCount: 1, flaggedCount: 1,
            lastFailure: SyncFailureRecord(at: epoch, kind: .serverUnavailable,
                                           code: "unavailable", traceId: "ob4-sweep"))
        let counts = ["vehicle": try repo.rowCount(in: TankbookSchema.vehicle),
                      "fillUp": try repo.rowCount(in: TankbookSchema.fillUp),
                      "station": try repo.rowCount(in: TankbookSchema.station)]
        let bundle = DiagnosticsExport.collect(log: log, context: testContext(),
                                               osLog: osLog, sync: sync, rowCounts: counts)

        // The bundle still renders with the log window present...
        let text = bundle.rendered()
        #expect(text.contains("logStore=ok lines=1"))
        #expect(text.contains("event=sync.merge"))
        // ...and the WHOLE output carries none of the seeded values (a sweep over
        // an empty ring/database would pass against any bug - this one seeded the
        // repository first, per the vacuous-assertion trap list).
        for needle in [seed.stationName, seed.note, seed.amount] {
            #expect(!text.contains(needle), "the bundle leaked: \(needle)")
        }
    }

    // MARK: - OSLogStore unavailable -> a degraded bundle, never an error

    @Test("an unreadable OSLogStore degrades to breadcrumbs with the marker intact")
    func unavailableLogStoreStillRendersBreadcrumbs() {
        let sink = InMemorySink()
        let crumbs = Breadcrumbs()
        let log = makeLog(sink: sink, breadcrumbs: crumbs)
        log.emit(OB4PlainEvent())
        #expect(crumbs.snapshot().count == 1)

        let bundle = DiagnosticsExport.collect(log: log, context: testContext(),
                                               osLog: ThrowingOSLogReader(),
                                               sync: nil, rowCounts: [:])
        let text = bundle.rendered()

        #expect(text.contains("logStore=unavailable"))
        #expect(text.contains("event=ob4.plain"))
        #expect(text.contains("breadcrumbCount=1"))
    }

    @Test("a readable store with no entries reads as ok lines=0, not unavailable")
    func quietStoreIsNotUnavailable() {
        let sink = InMemorySink()
        let log = makeLog(sink: sink)
        let bundle = DiagnosticsExport.collect(log: log, context: testContext(),
                                               osLog: FixtureOSLogReader(entries: []),
                                               sync: nil, rowCounts: [:])
        let text = bundle.rendered()
        #expect(text.contains("logStore=ok lines=0"))
        #expect(!text.contains("logStore=unavailable"),
                "a readable-but-silent store is a quiet device, not a missing capability")
    }

    // MARK: - The OSLog re-redaction itself

    @Test("a debug-reveal OSLog line is re-scrubbed before the bundle holds it")
    func osLogLineRedactorMasksSensitiveFieldValues() {
        let line = "2026-09-05T10:00:00.000Z INFO [capture] event=capture.pipeline "
            + "stationName=Zvezda-Lubricants-77 note=timing-belt-service-ob4 amount=64.20 "
            + "field=total:0.982"
        let redacted = OSLogTextRedactor.redact(line)

        #expect(!redacted.contains("Zvezda-Lubricants-77"))
        #expect(!redacted.contains("timing-belt-service-ob4"))
        #expect(!redacted.contains("64.20"))
        #expect(redacted.contains("stationName=<redacted>"))
        #expect(redacted.contains("note=<redacted>"))
        #expect(redacted.contains("amount=<redacted>"))
        // Safe content survives untouched.
        #expect(redacted.contains("event=capture.pipeline"))
        #expect(redacted.contains("field=total:0.982"))
    }
}

// MARK: - The consent store (docs/LOGGING.md §5: default off, persisted)

@Suite("Diagnostics consent store (OB.4)")
struct OB4DiagnosticsConsentStoreTests {
    @Test("a fresh store defaults to OFF and a written consent persists")
    func defaultsOffAndPersists() {
        let suite = "OB4-consent-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = DiagnosticsConsentStore(defaults: UserDefaults(suiteName: suite)!)

        // Default off - the §5 invariant, and the value a default-on mutation
        // (check 3) breaks before any UI runs.
        #expect(store.hasConsented == false)

        store.setConsented(true)
        // A second instance over the same store sees the persisted value (a
        // persistence bug must be visible, not assumed away).
        #expect(DiagnosticsConsentStore(defaults: UserDefaults(suiteName: suite)!).hasConsented == true)

        store.reset()
        #expect(DiagnosticsConsentStore(defaults: UserDefaults(suiteName: suite)!).hasConsented == false,
                "reset returns the store to its fresh-install default")
    }
}

// MARK: - OB.4 fixtures

/// Simulates a careless call site stuffing a fully populated entry into a log
/// event - the redactor (and only the redactor) keeps the values out.
private struct OB4PopulatedEntityLog: LogEvent {
    let eventName = "test.ob4.redaction.fixture"
    let category = LogCategory.persistence
    let level = LogLevel.info
    let fields: [LogField]

    init(seed: SeededValues) {
        fields = [
            .safe("entityType", "fillUp"),
            .sensitive("stationName", seed.stationName),
            .sensitive("note", seed.note),
            .sensitive("amount", seed.amount)
        ]    }
}

/// A harmless info line for the fallback test.
private struct OB4PlainEvent: LogEvent {
    let eventName = "ob4.plain"
    let category = LogCategory.sync
    let level = LogLevel.info
    let fields: [LogField] = []
}
