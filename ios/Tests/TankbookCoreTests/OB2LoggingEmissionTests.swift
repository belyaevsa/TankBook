import Testing
import Foundation
@testable import TankbookCore

// OB.2 (was PR.10): the events this row adds are actually EMITTED from real
// write paths and async edges, not merely defined. Tests run entirely in
// process against an injected in-memory sink and assert on the real emitted
// output (docs/TESTING.md: mock the boundary, don't boot the world).

private let epoch = Date(timeIntervalSinceReferenceDate: 0)
private let future = Date(timeIntervalSinceReferenceDate: 86_400 * 40)

private func testContext() -> LogContext {
    LogContext(deviceId: "device-ob2-0001", appVersion: "9.9.9-test", platform: "ios")
}

private func makeLog(sink: InMemorySink) -> TankbookLog {
    TankbookLog(sink: sink, context: { testContext() }, breadcrumbs: nil)
}

private func makeRepo() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

/// A vehicle with a deliberately DISTINCTIVE station name, note and amount so
/// the privacy sweep has real needles to look for (docs/LOGGING.md §7).
private struct SeededValues {
    let stationName = "Zvezda-Lubricants-77"
    let note = "timing-belt-service-ob2"
    let vehicle: Vehicle
    let fillUp: FillUp

    init() {
        vehicle = Vehicle(
            id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
            name: "OB2 Fixture Car", make: "Volvo", model: "V60", year: 2019,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil
        )
        let stationID = UUID.v7()
        fillUp = FillUp(
            id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
            vehicleId: vehicle.id, date: epoch, odometer: 119_486,
            money: Money(amount: Decimal(string: "64.20")!, currency: .eur, homeCurrency: .eur),
            note: note, attachments: [], provenance: .receiptScan, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.3, unitPrice: Decimal(string: "1.529")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: stationID, crossCheck: .verified, extraction: nil
        )
    }
}

// MARK: - A real write on a temp DB emits begin then exactly one ok (OB.2)

@Test func realTempDBWriteEmitsBeginThenExactlyOneOk() throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let repo = try makeRepo()
    let seed = SeededValues()
    // The fill's vehicle must exist first - the schema enforces the FK.
    try repo.upsertVehicle(seed.vehicle)

    try loggedWrite(log, op: .create, entityType: FillUp.entityType,
                    entityId: seed.fillUp.id, source: .capture) {
        try repo.upsertFillUp(seed.fillUp)
    }
    // A double ok() after a throw would be the vacuous trap; here the DB write
    // is real and the handle fires exactly once.
    let events = sink.all().map(\.event)
    #expect(events == ["data.mutate.begin", "data.mutate.ok"])
}

@Test func failingTempDBWriteEmitsFailWithRolledBack() throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let repo = try makeRepo()
    let seed = SeededValues()
    try repo.upsertVehicle(seed.vehicle)

    // Force a genuine database failure: drop the table the write targets, so
    // the real repository write throws and rolls back.
    try repo.database.write { db in
        try db.execute(sql: "DROP TABLE IF EXISTS \(TankbookSchema.fillUp)")
    }

    #expect(throws: Error.self) {
        try loggedWrite(log, op: .create, entityType: FillUp.entityType,
                        entityId: seed.fillUp.id, source: .capture) {
            try repo.upsertFillUp(seed.fillUp)
        }
    }

    let events = sink.all().map(\.event)
    #expect(events == ["data.mutate.begin", "data.mutate.fail"])
    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("rolledBack=true"))
    #expect(text.contains("errorCode=database.write_failed"))
}

// MARK: - A 500-record merge emits ONE sync.merge line, not 500 (OB.2)

@Test func fiveHundredRecordMergeEmitsOneMergeLine() async throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let repo = try makeSyncRepository()
    let transport = SyncTransportDouble()
    let vehicles = (0..<500).map { _ in makeSyncVehicle() }
    transport.enqueuePull(SyncPullResponse(
        records: vehicles.enumerated().map { makePullRecord($0.element, scn: Int64($0.offset + 1)) },
        nextSince: 500, more: false,
        schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))
    let loggedEngine = SyncEngine(repository: repo, transport: transport,
                                  cursorStore: InMemorySyncCursorStore(),
                                  log: log)

    _ = try await loggedEngine.synchronize()

    let mergeLines = sink.all().filter { $0.event == "sync.merge" }
    #expect(mergeLines.count == 1, "500-record merge must be ONE line, got \(mergeLines.count)")
    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("recordsApplied=500"))
    // And the cycle begin/end pair brackets it.
    let cycleEvents = sink.all().map(\.event)
    #expect(cycleEvents.first == "sync.cycle.begin")
    #expect(cycleEvents.last == "sync.cycle.end")
}

// MARK: - A clamped push emits sync.clock.skew (OB.2, far-future clientUpdatedAt)

@Test func farFutureClientUpdatedAtEmitsClockSkewOnClampedPush() async throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let repo = try makeRepo()
    let seed = SeededValues()
    try repo.upsertVehicle(seed.vehicle)
    // A fill whose `updatedAt` is ~40 days in the future - the stamp the server
    // clamps (docs/API.md: >24h future is clamped) and reports back, which is
    // the client-visible skew evidence this event narrates.
    var futureFill = seed.fillUp
    futureFill.updatedAt = future
    try repo.upsertFillUp(futureFill)

    let transport = SyncTransportDouble()
    transport.enqueuePush(SyncPushResponse(results: [
        SyncPushResult(id: futureFill.id, status: .accepted(newScn: 1, clamped: true))
    ]))
    let engine = SyncEngine(repository: repo, transport: transport,
                            cursorStore: InMemorySyncCursorStore(),
                            log: log)

    let outcome = try await engine.synchronize()

    #expect(outcome.clampedIds == [futureFill.id])
    let skewLines = sink.all().filter { $0.event == "sync.clock.skew" }
    #expect(skewLines.count == 1)
    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("clampedCount=1"))
    #expect(text.contains("event=sync.clock.skew"))
}

// MARK: - An injected background-task expiry handler emits its event (OB.2)

@Test func backgroundTaskExpiryEmitsItsEvent() {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)

    let task = BackgroundTaskLogging(log: log, kind: "sync")
    task.note(grantedSeconds: 12)
    task.expired()

    let events = sink.all().map(\.event)
    #expect(events == ["background.task.begin", "background.task.expired"])
    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("kind=sync"))
    #expect(text.contains("grantedSeconds=12"))
}

// MARK: - NetRequest/NetResponse carry bytes + endpoint, never a body (OB.2)

/// A transport double that echoes a canned body back.
private struct EchoTransport: TankbookHTTPTransport {
    let status: Int
    let body: Data
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        TankbookHTTPResponse(status: status, body: body)
    }
}

@Test func netEventsCarryEndpointAndByteCountsNeverTheBody() async throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let secret = "Zvezda-Lubricants-77|64.20|timing-belt"
    let requestBody = Data("42.30|71.02".utf8)
    let trace = UUID.v7()
    let request = TankbookHTTPRequest(
        url: URL(string: "https://api.example.com/v1/sync/pull")!,
        method: "POST",
        headers: ["X-Tankbook-Trace": trace.uuidString.lowercased()],
        body: requestBody)
    let transport = LoggingHTTPTransport(inner: EchoTransport(status: 200, body: Data(secret.utf8)),
                                         log: log)

    let response = try await transport.execute(request)

    #expect(response.status == 200)
    let lines = sink.all()
    let requestLine = lines.first { $0.event == "net.request" }
    let responseLine = lines.first { $0.event == "net.response" }
    #expect(requestLine != nil)
    #expect(responseLine != nil)
    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("endpoint=/v1/sync/pull"))
    #expect(text.contains("requestBytes=\(requestBody.count)"))
    #expect(text.contains("responseBytes=\(secret.utf8.count)"))
    #expect(text.contains("status=200"))
    #expect(text.contains("traceId=\(trace.uuidString)"))
    // The bodies - the request values AND the response's own secret - appear
    // nowhere; only their byte counts do (hard rule 12).
    #expect(!text.contains("42.30|71.02"))
    #expect(!text.contains(secret))
    #expect(!text.contains("Zvezda-Lubricants-77"))
    #expect(!text.contains("64.20"))
}

// MARK: - Confirm commit: userCorrected true when edited, false when not (OB.2)

private func makeExtraction() -> FuelExtraction {
    FuelExtraction(liters: 42.30, unitPrice: 1.679, total: 71.02,
                   currency: .eur, fuelKind: .petrol95, date: "17.08.2026")
}

@Test func confirmEmitsUserCorrectedTrueWhenPrefillWasEdited() throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    // The user changed the proposed liters (42.30 -> 40.00) and kept the rest.
    let saved = ScannedSaveValues(total: Decimal(string: "71.02")!,
                                  volumeL: 40.00,
                                  unitPrice: Decimal(string: "1.679")!,
                                  currency: .eur, fuelKind: .petrol95,
                                  date: ConfirmDate.parse("17.08.2026"))
    let plan = ScannedSavePlanner.plan(extraction: makeExtraction(), hasPhoto: true, saved: saved)
    let meta = try #require(plan.extraction)
    let event = CaptureCommitLog.event(meta: meta, crossCheck: .verified, durationMs: 184)
    log.emit(event)

    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("event=capture.pipeline"))
    #expect(text.contains("userCorrected=true"))
    #expect(!text.contains("40.00"))
    #expect(!text.contains("71.02"))
    #expect(!text.contains("42.30"))
}

@Test func confirmEmitsUserCorrectedFalseWhenPrefillWasAccepted() throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    // The user accepted every proposed value.
    let saved = ScannedSaveValues(total: Decimal(string: "71.02")!,
                                  volumeL: 42.30,
                                  unitPrice: Decimal(string: "1.679")!,
                                  currency: .eur, fuelKind: .petrol95,
                                  date: ConfirmDate.parse("17.08.2026"))
    let plan = ScannedSavePlanner.plan(extraction: makeExtraction(), hasPhoto: true, saved: saved)
    let meta = try #require(plan.extraction)
    let event = CaptureCommitLog.event(meta: meta, crossCheck: .verified, durationMs: 184)
    log.emit(event)

    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("event=capture.pipeline"))
    #expect(text.contains("userCorrected=false"))
}

// MARK: - THE privacy sweep over every event this row adds (docs/LOGGING.md §7)

@Test func everyEventThisRowAddsIsFreeOfDomainValues() async throws {
    let sink = InMemorySink()
    let log = makeLog(sink: sink)
    let repo = try makeRepo()
    let seed = SeededValues()
    let stationName = seed.stationName
    let note = seed.note
    let amount = "64.20"
    try repo.upsertVehicle(seed.vehicle)

    // 1. A real repository write carrying the distinctive values.
    try loggedWrite(log, op: .create, entityType: FillUp.entityType,
                    entityId: seed.fillUp.id, source: .capture) {
        try repo.upsertFillUp(seed.fillUp)
    }

    // 2. A full sync cycle over records that hold the same values.
    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(seed.vehicle, scn: 1), makePullRecord(seed.fillUp, scn: 2)],
        nextSince: 2, more: false,
        schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))
    let engine = SyncEngine(repository: repo, transport: transport,
                            cursorStore: InMemorySyncCursorStore(), log: log)
    _ = try? await engine.synchronize()

    // 3. A failing write path (its underlyingError could carry the values).
    try repo.database.write { db in
        try db.execute(sql: "DROP TABLE IF EXISTS \(TankbookSchema.fillUp)")
    }
    try? loggedWrite(log, op: .create, entityType: FillUp.entityType,
                     entityId: seed.fillUp.id, source: .capture,
                     errorCode: "database.write_failed") {
        try repo.upsertFillUp(seed.fillUp)
    }

    // 4. The capture.pipeline event over an extraction that carries the amount.
    let saved = ScannedSaveValues(total: Decimal(string: amount)!,
                                  volumeL: 42.30,
                                  unitPrice: Decimal(string: "1.529")!,
                                  currency: .eur, fuelKind: .petrol95,
                                  date: ConfirmDate.parse("17.08.2026"))
    if let plan = ScannedSavePlanner.plan(extraction: makeExtraction(),
                                          hasPhoto: true, saved: saved).extraction {
        log.emit(CaptureCommitLog.event(meta: plan, crossCheck: .verified, durationMs: 184))
    }

    // 4. The HTTP edges.
    let http = LoggingHTTPTransport(
        inner: EchoTransport(status: 200, body: Data("\(stationName) \(amount) \(note)".utf8)),
        log: log)
    let trace = UUID.v7()
    let request = TankbookHTTPRequest(
        url: URL(string: "https://api.example.com/v1/sync/push")!,
        method: "POST",
        headers: ["X-Tankbook-Trace": trace.uuidString.lowercased()],
        body: Data("\(stationName) \(amount) \(note)".utf8))
    _ = try? await http.execute(request)

    // 5. The lifecycle / background-task / path edges.
    log.emit(AppLifecycle(phase: .active))
    let task = BackgroundTaskLogging(log: log, kind: "sync")
    task.note(grantedSeconds: 20)
    task.expired()
    log.emit(NetworkPathChange(from: "satisfied", to: "unsatisfied"))
    log.emit(SyncQueue(dirtyCount: 2, oldestDirtyAgeSeconds: 60))

    // Sweep the WHOLE captured output, over every event above, not per-event:
    // a future event that starts carrying a domain value fails here even if no
    // per-event test mentions it (the OB.2 privacy contract).
    let output = sink.rendered().joined(separator: "\n")
    for needle in [stationName, note, amount] {
        #expect(!output.contains(needle), "privacy sweep leaked: \(needle)")
    }
}
