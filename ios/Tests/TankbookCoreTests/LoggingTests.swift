import Testing
import Foundation
@testable import TankbookCore

// Tests for ios/Sources/TankbookCore/Logging - the P0.11 logging foundation.
// They run entirely in-process against an injected in-memory sink and assert on
// the real emitted output (docs/TESTING.md: mock the boundary, don't boot the
// world).

private let epoch = Date(timeIntervalSince1970: 1_752_000_000)
private let day: TimeInterval = 86_400

private func testContext() -> LogContext {
    LogContext(deviceId: "device-test-0001", appVersion: "9.9.9-test", platform: "ios")
}

private func makeLog(sink: InMemorySink, breadcrumbs: Breadcrumbs? = nil) -> TankbookLog {
    TankbookLog(sink: sink, context: { testContext() }, breadcrumbs: breadcrumbs)
}

private func makeLine(_ event: String) -> LogLine {
    LogLine(timestamp: Date(), level: .info, category: .sync, event: event,
            traceId: nil, deviceId: nil, appVersion: "9.9.9-test", platform: "ios",
            fields: [])
}

// MARK: - Redaction fixture (a fully populated entity, docs/LOGGING.md §7)

/// Simulates a careless call site stuffing a fully populated entity into a log
/// event. Every value is classified through the public factories; the redactor
/// is what keeps the Sensitive/Never ones out of the emitted output.
private struct PopulatedEntityLog: LogEvent {
    let eventName = "test.redaction.fixture"
    let category = LogCategory.persistence
    let level = LogLevel.info
    let fields: [LogField]

    init(vehicle: Vehicle, fillUp: FillUp, station: Station,
         email: String, token: String, payload: String, ocrText: String) {
        fields = [
            .safe("vehicleId", vehicle.id.uuidString),
            .safe("fillUpId", fillUp.id.uuidString),
            .safe("stationId", station.id.uuidString),
            .safe("entityType", "fillUp"),
            .safe("schemaVersion", 1),
            .safe("count", 5),
            .safe("errorCode", "sqlite_busy"),
            .safe("fieldName", "odometer"),
            .sensitive("stationName", station.name),
            .sensitive("brand", station.brand ?? ""),
            .sensitive("note", fillUp.note ?? ""),
            .sensitive("plate", vehicle.plate ?? ""),
            .sensitive("amount", "\(fillUp.money?.amount ?? 0)"),
            .sensitive("volumeL", "\(fillUp.volumeL)"),
            .sensitive("odometer", "\(fillUp.odometer ?? 0)"),
            .sensitive("latitude", "\(station.location?.latitude ?? 0)"),
            .sensitive("longitude", "\(station.location?.longitude ?? 0)"),
            .sensitive("email", email),
            .never("token", token),
            .never("payload", payload),
            .never("ocrText", ocrText),
        ]
    }
}

private func redactionFixture() -> (event: PopulatedEntityLog, forbidden: [String]) {
    let vehicle = Vehicle(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        name: "Marina's Commuter", make: "Volkswagen", model: "Golf", year: 2019,
        plate: "AB-123-CD", powertrain: .ice, fuelKinds: [.petrol95],
        tankCapacityL: 50, batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil
    )
    let station = Station(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        name: "Shell Lubricants Rhein-Main", brand: "Shell",
        location: GeoCoordinate(latitude: 50.1109, longitude: 8.6821),
        favorite: true,
        defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: "V-Power")
    )
    let fillUp = FillUp(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        vehicleId: vehicle.id, date: epoch, odometer: 119_486,
        money: Money(amount: Decimal(string: "64.20")!, currency: .eur, homeCurrency: .eur),
        note: "Timing belt service", attachments: [],
        provenance: .receiptScan, conflict: .none, purchaseGroupId: nil,
        volumeL: 42.3, unitPrice: Decimal(string: "1.529")!, fuelKind: .petrol95,
        fuelGrade: "V-Power", isFull: true, tankLevelAfterPct: 100,
        stationId: station.id, crossCheck: .verified, extraction: nil
    )
    let email = "owner@example.com"
    let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.fake-signature"
    let payload = "{\"records\":[{\"id\":\"00000000-0000-0000-0000-000000000000\",\"payload\":{\"volumeL\":42.3}}]}"
    let ocrText = "SHELL 42.30L EUR 64.20 50.1109N 8.6821E"
    let event = PopulatedEntityLog(vehicle: vehicle, fillUp: fillUp, station: station,
                                   email: email, token: token, payload: payload, ocrText: ocrText)
    let forbidden = [
        "Marina's Commuter", "Volkswagen", "Golf", "AB-123-CD",
        "Shell Lubricants Rhein-Main", "Shell",
        "Timing belt service", "V-Power",
        "64.2", "42.3", "119486", "50.1109", "8.6821",
        "owner@example.com", token, payload, ocrText,
    ]
    return (event, forbidden)
}

// MARK: - Redaction

@Test func redactorStripsEverySensitiveAndNeverValueFromEmittedOutput() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let (fixture, forbidden) = redactionFixture()

    log.emit(fixture)

    let output = sink.rendered().joined(separator: "\n")

    // Safe values survive.
    #expect(output.contains("event=test.redaction.fixture"))
    #expect(output.contains("errorCode=sqlite_busy"))
    #expect(output.contains("fieldName=odometer"))
    #expect(output.contains("count=5"))
    #expect(output.contains("schemaVersion=1"))
    #expect(output.contains("entityType=fillUp"))

    // Sensitive and Never values appear nowhere.
    for value in forbidden {
        #expect(!output.contains(value), "leaked value: \(value)")
    }
}

@Test func neverValuesAreDroppedStructurallyAndSensitiveStayNonPublic() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let (fixture, _) = redactionFixture()

    log.emit(fixture)

    let line = sink.all().first { $0.event == "test.redaction.fixture" }
    #expect(line != nil)
    guard let line else { return }

    let names = line.fields.map(\.name)
    // Never-class fields do not survive redaction at all.
    #expect(!names.contains("token"))
    #expect(!names.contains("payload"))
    #expect(!names.contains("ocrText"))
    // Sensitive-class fields survive in debug builds but only as non-public.
    #expect(names.contains("stationName"))
    switch line.fields.first(where: { $0.name == "stationName" })?.kind {
    case .privateValue: break
    default: Issue.record("sensitive value must never be public")
    }
}

// MARK: - App error path (docs/LOGGING.md §4 Errors, hard rule 12)

/// An error whose rendered description embeds a domain value - the exact shape
/// a GRDB error takes when it carries its statement's arguments.
private struct StationNameError: LocalizedError {
    let stationName: String
    var errorDescription: String? { "failed to write station \(stationName)" }
}

@Test func appErrorNeverRendersTheErrorMessage() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let stationName = "Shell Lubricants Rhein-Main"
    let error = StationNameError(stationName: stationName)

    log.emit(AppError(operation: "home.load", category: .ui, error: error))

    let output = sink.rendered().joined(separator: "\n")

    // What stays loggable (hard rule 12): the stable operation code and the
    // error's type - never the rendered message.
    #expect(output.contains("event=app.error"))
    #expect(output.contains("operation=home.load"))
    #expect(output.contains("errorType=StationNameError"))
    // The description is Sensitive, so it is masked, not emitted.
    #expect(output.contains("errorDescription=<redacted>"))
    #expect(!output.contains("Shell Lubricants Rhein-Main"))
    #expect(!output.contains("Rhein-Main"))
}

// MARK: - Common fields (docs/LOGGING.md §2)

@Test func everyLineCarriesTheCommonFields() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let traceId = UUID.v7()

    log.emit(DataRecompute(vehicleId: UUID.v7(), segmentsBefore: 3, segmentsAfter: 4, durationMs: 12),
             traceId: traceId)

    let line = sink.all().last
    #expect(line != nil)
    guard let line else { return }
    #expect(line.event == "data.recompute")
    #expect(line.traceId == traceId)
    #expect(line.deviceId == "device-test-0001")
    #expect(line.appVersion == "9.9.9-test")
    #expect(line.platform == "ios")

    let text = sink.rendered().last!
    #expect(text.contains("event=data.recompute"))
    #expect(text.contains("traceId=\(traceId.uuidString)"))
    #expect(text.contains("deviceId=device-test-0001"))
    #expect(text.contains("appVersion=9.9.9-test"))
    #expect(text.contains("platform=ios"))
}

// MARK: - Mutation pair (docs/LOGGING.md §4, §7)

@Test func successfulMutationEmitsBeginThenExactlyOneOk() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let entityId = UUID.v7()

    let mutation = DataMutationLogger(log: log, op: .create, entityType: "fillUp",
                                      entityId: entityId, source: .manual)
    mutation.ok(fieldsChanged: ["odometer", "volumeL"])
    mutation.ok(fieldsChanged: ["note"]) // ignored: a terminal already fired

    let events = sink.all().map(\.event)
    #expect(events == ["data.mutate.begin", "data.mutate.ok"])
}

@Test func failingWriteEmitsFailWithErrorCodeAndRollbackFlag() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let entityId = UUID.v7()

    let mutation = DataMutationLogger(log: log, op: .update, entityType: "fillUp",
                                      entityId: entityId, source: .capture)
    mutation.fail(errorCode: "sqlite_busy", errorDomain: "TankbookDatabaseError",
                  underlyingError: "UNIQUE constraint failed", rolledBack: true)
    mutation.fail(errorCode: "second", rolledBack: false) // ignored

    let events = sink.all().map(\.event)
    #expect(events == ["data.mutate.begin", "data.mutate.fail"])

    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("errorCode=sqlite_busy"))
    #expect(text.contains("errorDomain=TankbookDatabaseError"))
    #expect(text.contains("rolledBack=true"))
}

@Test func okAfterFailDoesNotEmitASecondTerminal() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)

    let mutation = DataMutationLogger(log: log, op: .delete, entityType: "station",
                                      entityId: UUID.v7(), source: .manual)
    mutation.ok(fieldsChanged: [])
    mutation.fail(errorCode: "boom", rolledBack: false)

    let events = sink.all().map(\.event)
    #expect(events == ["data.mutate.begin", "data.mutate.ok"])
}

// MARK: - fieldsChanged carries names, never values (docs/LOGGING.md §4)

@Test func fieldsChangedLogsTheFieldNameAndNeitherValue() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)

    // Editing odometer 119486 -> 119500. The call site only ever hands the
    // logger the *names* of the changed fields; the values have no API to
    // reach a log line.
    let changedFieldNames = ["odometer"]
    let mutation = DataMutationLogger(log: log, op: .update, entityType: "fillUp",
                                      entityId: UUID.v7(), source: .manual)
    mutation.ok(fieldsChanged: changedFieldNames)

    let output = sink.rendered().joined(separator: "\n")
    #expect(output.contains("fieldsChanged=odometer"))
    #expect(!output.contains("119486"))
    #expect(!output.contains("119500"))
}

// MARK: - Volume discipline: O(1) lines per merge, not O(n) (docs/LOGGING.md §7)

@Test func mergingFiveHundredRecordsEmitsOneLine() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let session = UUID.v7()

    log.emit(SyncCycleBegin(syncSessionId: session, trigger: .foreground))
    log.emit(SyncMerge(recordsApplied: 1, conflicts: []))
    log.emit(SyncMerge(recordsApplied: 500, conflicts: [SyncConflict(scenario: .s3, count: 2)]))
    log.emit(SyncCycleEnd(syncSessionId: session, durationMs: 42, recordsPulled: 501, recordsPushed: 1))

    // 4 lines total - the merge of 500 records contributed exactly 1 line.
    #expect(sink.all().count == 4)

    let bigMerge = sink.rendered().first { $0.contains("recordsApplied=500") }
    #expect(bigMerge != nil)
    guard let bigMerge else { return }
    #expect(bigMerge.contains("event=sync.merge"))
    #expect(bigMerge.contains("recordsApplied=500"))
    #expect(bigMerge.contains("conflict=S3:2"))
}

// MARK: - Conflict tagging (docs/SYNC.md S1-S8)

@Test func mergeConflictTalliesCarryScenarioTags() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)

    let conflicts = SyncScenario.allCases.map { SyncConflict(scenario: $0, count: 1) }
    log.emit(SyncMerge(recordsApplied: 8, conflicts: conflicts))

    let mergeLines = sink.rendered().filter { $0.contains("event=sync.merge") }
    #expect(mergeLines.count == 1)

    let text = mergeLines.first!
    for scenario in SyncScenario.allCases {
        #expect(text.contains("\(scenario.rawValue):1"), "missing tag \(scenario.rawValue)")
    }
}

// MARK: - Capture pipeline: field names + confidence only (docs/LOGGING.md §4)

@Test func capturePipelineLogsFieldNamesAndConfidenceNeverValues() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)

    log.emit(CapturePipeline(
        pipelineId: "vision+rules v3", durationMs: 184,
        fields: [
            CapturedField(name: .total, confidence: 0.982),
            CapturedField(name: .volume, confidence: 0.914),
            CapturedField(name: .station, confidence: 0.881),
        ],
        crossCheck: .verified,
        userCorrected: false
    ))

    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("pipelineId=vision+rules v3"))
    #expect(text.contains("field=total:0.982"))
    #expect(text.contains("field=volume:0.914"))
    #expect(text.contains("field=station:0.881"))
    #expect(text.contains("crossCheck=verified"))
    // No extracted value could be attached even by mistake: the event takes no
    // value-carrying parameter.
    #expect(!text.contains("42.3"))
}

// MARK: - Level discipline (docs/LOGGING.md §3)

@Test func netResponseLevelsFollowDegradation() {
    #expect(NetResponse(endpoint: "/v1/sync/pull", status: 200, durationMs: 12).level == .info)
    #expect(NetResponse(endpoint: "/v1/sync/push", status: 429, durationMs: 12, retryAfter: 5, errorCode: "rate_limited", willRetry: true).level == .warn)
    #expect(NetResponse(endpoint: "/v1/sync/push", status: 503, durationMs: 12, errorCode: "unavailable", willRetry: true).level == .warn)
}

// MARK: - Breadcrumb ring (docs/LOGGING.md §4-§5)

@Test func breadcrumbRingEvictsOldestAndKeepsNewest() {
    let crumbs = Breadcrumbs(capacity: 5)
    for index in 0..<10 {
        crumbs.record(makeLine("event.\(index)"))
    }

    let snapshot = crumbs.snapshot()
    #expect(snapshot.count == 5)
    #expect(snapshot.first?.event == "event.5")
    #expect(snapshot.last?.event == "event.9")
}

@Test func breadcrumbRingIsSafeUnderConcurrentAppends() {
    let crumbs = Breadcrumbs(capacity: 50)
    DispatchQueue.concurrentPerform(iterations: 2_000) { index in
        crumbs.record(makeLine("event.\(index)"))
    }

    let snapshot = crumbs.snapshot()
    #expect(snapshot.count == 50)
    #expect(Set(snapshot.map(\.event)).count == 50)
}

// MARK: - Diagnostics export (docs/LOGGING.md §5)

@Test func diagnosticsBundleContainsNoSensitiveOrNeverValue() {
    let sink = InMemorySink()
    let crumbs = Breadcrumbs()
    let log = makeLog(sink: sink, breadcrumbs: crumbs)

    // The breadcrumb ring now holds a line whose source event carried a fully
    // populated entity.
    let (fixture, forbidden) = redactionFixture()
    log.emit(fixture)
    #expect(crumbs.snapshot().count == 1)

    let bundle = DiagnosticsExport.make(log: log, context: testContext())
    let text = bundle.rendered()

    #expect(text.contains("Tankbook diagnostics"))
    #expect(text.contains("generatedAt="))
    #expect(text.contains("appVersion=9.9.9-test"))
    #expect(text.contains("platform=ios"))
    #expect(text.contains("deviceId=device-test-0001"))
    #expect(text.contains("breadcrumbCount=1"))
    #expect(text.contains("event=test.redaction.fixture"))

    for value in forbidden {
        #expect(!text.contains(value), "diagnostics leaked value: \(value)")
    }
    // The bundle is available as UTF-8 data for the About screen flow.
    #expect(String(data: bundle.data, encoding: .utf8) == text)
}

@Test func diagnosticsExportAssemblesFromExplicitLines() {
    let bundle = DiagnosticsExport.make(lines: ["timestamp INFO [sync] event=sync.merge recordsApplied=500"],
                                        context: testContext())
    let text = bundle.rendered()
    #expect(text.contains("breadcrumbCount=1"))
    #expect(text.contains("event=sync.merge"))
    #expect(text.contains("recordsApplied=500"))
}
