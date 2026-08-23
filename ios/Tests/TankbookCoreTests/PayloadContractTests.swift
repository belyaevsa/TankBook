import Foundation
import Testing
@testable import TankbookCore

// Payload-contract tests (docs/SYNC.md -> "Payload contract and versioning",
// docs/TESTING.md -> Cross-cutting foundations, docs/SCHEMA.md -> Payload schemas).
//
// These tests make the forward-compatibility invariant executable:
//   - every synced entity has a registered schema (a new entity without one
//     fails the build, naming the missing entity),
//   - every key the codec emits is declared in that entity's schema,
//   - every fixture validates against its schema,
//   - unknown fields and unknown entityTypes survive decode -> encode
//     byte-identically (never dropped),
//   - money serializes as decimal strings and round-trips exactly,
//   - the {entityType, schemaVersion, payload} envelope round-trips.

// MARK: - Repo layout

/// Repo root, located from this file's path so tests are cwd-independent.
/// <repo>/ios/Tests/TankbookCoreTests/PayloadContractTests.swift -> <repo>
private let repoRoot: URL = {
    URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
}()

private let schemaDirectory: URL = repoRoot.appendingPathComponent("docs/schemas/v1")
private let fixtureDirectory: URL = repoRoot.appendingPathComponent("docs/fixtures/payloads/v1")

private func schemaURL(for entityType: String) -> URL {
    schemaDirectory.appendingPathComponent("\(entityType).schema.json")
}

private func fixtureURL(for entityType: String) -> URL {
    fixtureDirectory.appendingPathComponent("\(entityType).json")
}

private func loadJSON(_ url: URL) throws -> JSONValue {
    try JSONValue.parse(Data(contentsOf: url))
}

private func fixtureEntityTypes() -> [String] {
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)) ?? []
    return entries.filter { $0.hasSuffix(".json") }
        .map { String($0.dropLast(".json".count)) }
        .sorted()
}

private func schemaProperties(_ schema: JSONValue) -> Set<String> {
    Set((schema.objectValue?["properties"]?.objectValue ?? [:]).keys)
}

// MARK: - Shared fixtures

private let testTimestamp = Date(timeIntervalSince1970: 1_752_000_000)
private let posixLocale = Locale(identifier: "en_US_POSIX")

private func dec(_ string: String) -> Decimal {
    Decimal(string: string, locale: posixLocale)!
}

private func parseDecimal(_ string: String) -> Decimal? {
    Decimal(string: string, locale: posixLocale)
}

private func convertedMoney() -> Money {
    Money(amount: dec("289.50"), currency: .pln, homeCurrency: .eur)
        .converted(using: RateSnapshot(rate: dec("4.2706"), rateDate: testTimestamp, source: .ecb))
}

// MARK: - Fully populated instances (every optional field set)

private func fullyPopulatedVehicle() -> Vehicle {
    Vehicle(
        id: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2021, plate: "ABC-123",
        powertrain: .hybrid, fuelKinds: [.petrol95, .electricity],
        tankCapacityL: 71, batteryCapacityKWh: 11.6,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: UUID(uuidString: "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa")!,
        archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 119_486
    )
}

private func fullyPopulatedFillUp() -> FillUp {
    FillUp(
        id: UUID(uuidString: "22222222-2222-7222-8222-222222222222")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        date: testTimestamp, odometer: 119486,
        money: convertedMoney(),
        note: "Shell, A4 exit",
        attachments: [UUID(uuidString: "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa")!],
        provenance: .import(source: "Fuelio"),
        conflict: .flagged(kind: .order, detectedAt: testTimestamp),
        purchaseGroupId: UUID(uuidString: "bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb")!,
        volumeL: 42.3, unitPrice: dec("1.679"), fuelKind: .petrol95, fuelGrade: "V-Power",
        isFull: true, tankLevelAfterPct: 100,
        stationId: UUID(uuidString: "77777777-7777-7777-8777-777777777777")!,
        crossCheck: .mismatch(field: .unitPrice),
        extraction: ExtractionMeta(
            fields: [
                .total: FieldExtraction(cropRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1),
                                        confidence: 0.98, userCorrected: true),
                .lineItem(2): FieldExtraction(cropRect: nil, confidence: 0.77, userCorrected: false),
            ],
            pipeline: "vision+rules v3"
        )
    )
}

private func fullyPopulatedChargeSession() -> ChargeSession {
    ChargeSession(
        id: UUID(uuidString: "33333333-3333-7333-8333-333333333333")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        date: testTimestamp, odometer: 119150,
        money: convertedMoney(),
        note: "Ionity, A6 services",
        attachments: [],
        provenance: .fiscalQR, conflict: .none,
        purchaseGroupId: nil,
        energyKWh: 43.2, unitPrice: dec("0.45"), chargeType: .dcPublic,
        provider: "Ionity",
        tariffId: UUID(uuidString: "88888888-8888-7888-8888-888888888888")!,
        durationMin: 42, socStartPct: 18, socEndPct: 92,
        extraction: ExtractionMeta(
            fields: [.energy: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false)],
            pipeline: "fiscal-qr"
        )
    )
}

private func fullyPopulatedServiceRecord() -> ServiceRecord {
    ServiceRecord(
        id: UUID(uuidString: "44444444-4444-7444-8444-444444444444")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        date: testTimestamp, odometer: 118200,
        money: convertedMoney(),
        note: "Annual service",
        attachments: [],
        provenance: .screenshot, conflict: .none,
        purchaseGroupId: nil,
        vendor: "Bosch Service",
        items: [
            ServiceItem(title: "Oil change", category: .oil,
                        cost: Money(amount: dec("89.00"), currency: .eur, homeCurrency: .eur),
                        partNumber: "MANN W 712/75",
                        lifetime: ServiceItem.Lifetime(km: 15_000, months: 12)),
            ServiceItem(title: "Custom tune", category: .other("tuning"),
                        cost: nil, partNumber: nil, lifetime: nil),
        ],
        usedParts: [UUID(uuidString: "55555555-5555-7555-8555-555555555555")!],
        tireSetId: UUID(uuidString: "99999999-9999-7999-8999-999999999999")!,
        proposedReminderId: UUID(uuidString: "66666666-6666-7666-8666-666666666666")!
    )
}

private func fullyPopulatedExpense() -> Expense {
    Expense(
        id: UUID(uuidString: "55555555-5555-7555-8555-555555555555")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        date: testTimestamp, odometer: 112000,
        money: convertedMoney(),
        note: "Annual comprehensive + theft",
        attachments: [],
        provenance: .manual, conflict: .none,
        purchaseGroupId: nil,
        category: .other("tuning"), title: "Suspension kit",
        recurrence: RecurrenceRule(everyMonths: 12, anchorDate: testTimestamp),
        installedInServiceId: UUID(uuidString: "44444444-4444-7444-8444-444444444444")!
    )
}

private func fullyPopulatedReminder() -> Reminder {
    Reminder(
        id: UUID(uuidString: "66666666-6666-7666-8666-666666666666")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        title: "Oil change", category: .other("valves"),
        dueDate: testTimestamp, dueOdometer: 134486,
        recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12),
        sourceEntryId: UUID(uuidString: "44444444-4444-7444-8444-444444444444")!,
        status: .dismissed(reason: "sold the tires")
    )
}

private func fullyPopulatedStation() -> Station {
    Station(
        id: UUID(uuidString: "77777777-7777-7777-8777-777777777777")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        name: "Shell Tiergarten", brand: "Shell",
        location: GeoCoordinate(latitude: 52.51, longitude: 13.35),
        favorite: true,
        defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: "V-Power"),
        lastUsedAt: testTimestamp
    )
}

private func fullyPopulatedTariff() -> Tariff {
    Tariff(
        id: UUID(uuidString: "88888888-8888-7888-8888-888888888888")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        name: "Home night rate", pricePerKWh: dec("0.24"), currency: .eur,
        validFrom: testTimestamp
    )
}

private func fullyPopulatedTireSet() -> TireSet {
    TireSet(
        id: UUID(uuidString: "99999999-9999-7999-8999-999999999999")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        vehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        name: "Winter Nokian",
        purchaseExpenseId: UUID(uuidString: "55555555-5555-7555-8555-555555555555")!
    )
}

private func fullyPopulatedPreferences() -> Preferences {
    Preferences(
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        notifications: Preferences.Notifications(reminders: true, anomalies: true, monthlySummary: true),
        eagerMediaOnWiFi: true,
        defaultVehicleId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        proFeedbackDiagnostics: true
    )
}

private func payload<T: SyncedEntity>(_ entity: T) throws -> JSONValue {
    try PayloadCodec.encode(entity).payload
}

/// Every synced entity encoded with every field populated. The domain
/// `Attachment` type name clashes with `Testing.Attachment` in type position,
/// so it is constructed in expression context only, never spelled as a bare
/// return type.
private func fullyPopulatedPayloads() throws -> [(entityType: String, payload: JSONValue)] {
    let attachment = Attachment(
        id: UUID(uuidString: "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa")!,
        createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: testTimestamp,
        kind: .pdf,
        file: LocalFileRef(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                           relativePath: "docs/2026/08/service.pdf"),
        extractedTimestamp: testTimestamp,
        ocrText: "BOSCH SERVICE 89.00"
    )
    return [
        (Vehicle.entityType, try payload(fullyPopulatedVehicle())),
        (FillUp.entityType, try payload(fullyPopulatedFillUp())),
        (ChargeSession.entityType, try payload(fullyPopulatedChargeSession())),
        (ServiceRecord.entityType, try payload(fullyPopulatedServiceRecord())),
        (Expense.entityType, try payload(fullyPopulatedExpense())),
        (Reminder.entityType, try payload(fullyPopulatedReminder())),
        (Station.entityType, try payload(fullyPopulatedStation())),
        (Tariff.entityType, try payload(fullyPopulatedTariff())),
        (TireSet.entityType, try payload(fullyPopulatedTireSet())),
        (type(of: attachment).entityType, try payload(attachment)),
        (Preferences.entityType, try payload(fullyPopulatedPreferences())),
    ]
}

// MARK: - Round-trip plumbing

private func roundTrip<T: SyncedEntity>(_ envelope: PayloadEnvelope, as type: T.Type) throws -> PayloadEnvelope {
    let decoded = try PayloadCodec.decode(envelope, as: T.self)
    return try PayloadCodec.encode(decoded.entity, preserving: decoded)
}

/// One constructed instance per synced entity; used only to obtain concrete
/// metatypes without spelling a type name (the domain `Attachment` type name
/// clashes with `Testing.Attachment` in type position).
private var sampleEntities: [any SyncedEntity] {
    [
        fullyPopulatedVehicle(),
        fullyPopulatedFillUp(),
        fullyPopulatedChargeSession(),
        fullyPopulatedServiceRecord(),
        fullyPopulatedExpense(),
        fullyPopulatedReminder(),
        fullyPopulatedStation(),
        fullyPopulatedTariff(),
        fullyPopulatedTireSet(),
        Attachment(
            id: UUID(uuidString: "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa")!,
            createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
            kind: .pdf,
            file: LocalFileRef(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                               relativePath: "docs/2026/08/service.pdf"),
            extractedTimestamp: nil,
            ocrText: nil
        ),
        fullyPopulatedPreferences(),
    ]
}

private func roundTripPreserving(_ envelope: PayloadEnvelope, entityType: String) throws -> PayloadEnvelope {
    guard let sample = sampleEntities.first(where: { type(of: $0).entityType == entityType }) else {
        throw PayloadCodec.Error.malformedEnvelope("no concrete SyncedEntity type for entityType '\(entityType)'")
    }
    return try openRoundTrip(envelope, via: sample)
}

/// Opens the existential value so `PayloadCodec.decode`/`encode` get a
/// concrete generic `Entity`.
private func openRoundTrip<T: SyncedEntity>(_ envelope: PayloadEnvelope, via sample: T) throws -> PayloadEnvelope {
    let decoded = try PayloadCodec.decode(envelope, as: T.self)
    return try PayloadCodec.encode(decoded.entity, preserving: decoded)
}

// MARK: - Schema coverage guard

/// Every synced entity known to the domain has a schema file. This is the
/// guard that stops a future entity shipping without its payload contract
/// (docs/SYNC.md -> "How this is assured"). The failure names the entity.
@Test func everySyncedEntityHasARegisteredSchema() {
    let missing = SyncedEntityCatalog.all
        .map { $0.entityType }
        .filter { !FileManager.default.fileExists(atPath: schemaURL(for: $0).path) }
        .sorted()
    let message = "Synced entities without a registered schema in \(schemaDirectory.path): \(missing). "
        + "A new entity ships with docs/schemas/v1/<entityType>.schema.json or the build fails."
    #expect(missing.isEmpty, Comment(stringLiteral: message))
}

// MARK: - Field coverage

/// Encoding a fully populated instance must only emit keys that the entity's
/// schema declares. A Swift field added without a schema entry fails here,
/// with the missing key and the entity named.
@Test func everyEncodedKeyIsDeclaredInItsSchema() throws {
    for (entityType, emittedPayload) in try fullyPopulatedPayloads() {
        let schema = try loadJSON(schemaURL(for: entityType))
        let declared = schemaProperties(schema)
        let emitted = Set((emittedPayload.objectValue ?? [:]).keys)
        let missing = emitted.subtracting(declared).sorted()
        let message = "\(entityType): encoded keys missing from schema properties: \(missing). "
            + "Declare them in scripts/generate-payload-schemas.swift and regenerate."
        #expect(missing.isEmpty, Comment(stringLiteral: message))
    }
}

// MARK: - Fixture validity

/// Every canonical fixture validates against its entity's schema.
@Test(arguments: fixtureEntityTypes())
func fixtureValidatesAgainstItsSchema(_ entityType: String) throws {
    let fixture = try loadJSON(fixtureURL(for: entityType))
    let schema = try loadJSON(schemaURL(for: entityType))
    let errors = JSONSchemaValidator.validate(instance: fixture, schema: schema)
    let message = "\(entityType) fixture violates its schema: "
        + errors.map { "\($0.pointer): \($0.message)" }.joined(separator: "; ")
    #expect(errors.isEmpty, Comment(stringLiteral: message))
}

@Test func fixtureCorpusExists() {
    #expect(FileManager.default.fileExists(atPath: fixtureDirectory.path),
            "fixture directory missing: \(fixtureDirectory.path)")
    #expect(!fixtureEntityTypes().isEmpty, "no fixtures found under \(fixtureDirectory.path)")
}

// MARK: - Round-trip preservation (the forward-compatibility invariant)

/// A record with an unknown top-level field survives decode -> encode
/// byte-identically, for every fixture (docs/SYNC.md, forward compatibility).
@Test(arguments: fixtureEntityTypes())
func unknownTopLevelFieldSurvivesDecodeEncode(_ entityType: String) throws {
    let fixture = try loadJSON(fixtureURL(for: entityType))
    var payload = fixture.objectValue ?? [:]
    payload["futureField"] = .object([
        "nested": .string("future-value"),
        "list": .array([.number("1"), .number("2")]),
        "enabled": .bool(true),
    ])

    let envelope = PayloadEnvelope(entityType: entityType,
                                   schemaVersion: PayloadCodec.currentSchemaVersion,
                                   payload: .object(payload))
    let originalBytes = try envelope.jsonData()
    let reencoded = try roundTripPreserving(envelope, entityType: entityType)
    let reencodedBytes = try reencoded.jsonData()

    let originalFuture = try JSONValue.parse(originalBytes).objectValue?["payload"]?.objectValue?["futureField"]
    let reencodedFuture = try JSONValue.parse(reencodedBytes).objectValue?["payload"]?.objectValue?["futureField"]
    #expect(originalFuture != nil, "\(entityType): futureField missing from the original envelope")
    #expect(reencodedFuture != nil, "\(entityType): futureField was dropped by decode -> encode")
    #expect(reencodedFuture == originalFuture, "\(entityType): futureField value changed")
    if let originalFuture, let reencodedFuture {
        #expect(try reencodedFuture.jsonData() == originalFuture.jsonData(),
                "\(entityType): futureField bytes changed")
    }

    let originalKeys = Set(payload.keys)
    let reencodedKeys = Set((reencoded.payload.objectValue ?? [:]).keys)
    let message = "\(entityType): top-level key set changed "
        + "(added \(reencodedKeys.subtracting(originalKeys).sorted()), "
        + "dropped \(originalKeys.subtracting(reencodedKeys).sorted()))"
    #expect(reencodedKeys == originalKeys, Comment(stringLiteral: message))
}

/// Unknown nested keys and unknown tagged-enum cases also survive unchanged
/// (the codec keeps them in a side dictionary / tag splice, re-emitted on encode).
@Test func unknownNestedFieldAndUnknownEnumTagSurviveDecodeEncode() throws {
    let fixture = try loadJSON(fixtureURL(for: "fillUp"))
    var payload = fixture.objectValue ?? [:]
    var money = payload["money"]?.objectValue ?? [:]
    money["futureMoneyField"] = .number("99")
    payload["money"] = .object(money)
    payload["provenance"] = .object(["tag": .string("telepathy"), "futuristic": .bool(true)])
    payload["futureField"] = .string("preserve-me")

    let envelope = PayloadEnvelope(entityType: "fillUp",
                                   schemaVersion: PayloadCodec.currentSchemaVersion,
                                   payload: .object(payload))
    let originalBytes = try envelope.jsonData()
    let reencoded = try roundTripPreserving(envelope, entityType: "fillUp")

    let reencodedPayload = reencoded.payload.objectValue ?? [:]
    #expect(reencodedPayload["futureField"] == .string("preserve-me"))
    #expect(reencodedPayload["money"]?.objectValue?["futureMoneyField"] == .number("99"))
    #expect(reencodedPayload["provenance"]?.objectValue?["tag"] == .string("telepathy"))
    #expect(reencodedPayload["provenance"]?.objectValue?["futuristic"] == .bool(true))

    let originalProvenanceBytes = try JSONValue.parse(originalBytes)
        .objectValue?["payload"]?.objectValue?["provenance"]?.jsonData()
    let reencodedProvenanceBytes = try reencodedPayload["provenance"]?.jsonData()
    #expect(reencodedProvenanceBytes == originalProvenanceBytes,
            "unknown provenance tag must round-trip byte-identically")
}

/// An envelope with an unknown entityType is stored opaquely and re-emitted
/// unchanged, never dropped (docs/SYNC.md, forward compatibility of types).
@Test func envelopeWithUnknownEntityTypeRoundTripsUnchanged() throws {
    let unknownPayload: JSONValue = .object([
        "someFutureField": .string("keep"),
        "nested": .object(["a": .number("1")]),
        "list": .array([.object(["b": .bool(true)]), .number("2.5")]),
    ])
    let envelope = PayloadEnvelope(entityType: "tireset",
                                   schemaVersion: PayloadCodec.currentSchemaVersion,
                                   payload: unknownPayload)
    let bytes = try envelope.jsonData()
    let reparsed = try PayloadEnvelope.parse(bytes)
    let rebytes = try reparsed.jsonData()
    #expect(reparsed.entityType == "tireset")
    #expect(reparsed.schemaVersion == PayloadCodec.currentSchemaVersion)
    #expect(reparsed.payload == unknownPayload)
    #expect(rebytes == bytes, "unknown entityType envelope must round-trip byte-identically, not be dropped")

    do {
        _ = try PayloadCodec.decode(envelope, as: Vehicle.self)
        Issue.record("decode must not force an unknown entityType into a known type")
    } catch let error as PayloadCodec.Error {
        #expect(error == .mismatchedEntityType(expected: "vehicle", actual: "tireset"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

// MARK: - Decimal-as-string

/// Money serializes as JSON strings, never numbers, and round-trips exactly.
@Test func moneySerializesAsDecimalStringAndRoundTripsExactly() throws {
    let amounts = ["1.679", "289.50", "67.79", "0.1"]
    for raw in amounts {
        let money = Money(amount: dec(raw), currency: .pln, homeCurrency: .eur)
        let tree = try payload(FillUp(
            id: UUID.v7(), createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
            vehicleId: UUID.v7(), date: testTimestamp, odometer: 119486,
            money: money, note: nil,
            attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil,
            volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95,
            fuelGrade: nil, isFull: true, tankLevelAfterPct: nil,
            stationId: nil, crossCheck: .notApplicable, extraction: nil
        ))
        let amountValue = tree.objectValue?["money"]?.objectValue?["amount"]
        guard case .string(let token)? = amountValue else {
            Issue.record("\(raw): money.amount serialized as a non-string: \(String(describing: amountValue))")
            continue
        }
        #expect(amountValue?.numericValue == nil, "\(raw): money.amount must never be a JSON number")
        #expect(token == PayloadFormat.decimalString(dec(raw)),
                "\(raw): serialized as '\(token)' instead of the canonical decimal string")
        #expect(parseDecimal(token) == dec(raw), "\(raw): did not round-trip exactly through '\(token)'")
    }

    // Snapshot fields are decimal strings too and round-trip exactly.
    let tree = try payload(FillUp(
        id: UUID.v7(), createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
        vehicleId: UUID.v7(), date: testTimestamp, odometer: 119486,
        money: convertedMoney(), note: nil,
        attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil,
        volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95,
        fuelGrade: nil, isFull: true, tankLevelAfterPct: nil,
        stationId: nil, crossCheck: .notApplicable, extraction: nil
    ))
    let moneyTree = tree.objectValue?["money"]?.objectValue ?? [:]
    #expect(moneyTree["homeAmount"]?.stringValue != nil, "homeAmount must serialize as a string")
    #expect(moneyTree["rate"]?.stringValue != nil, "rate must serialize as a string")
    #expect(moneyTree["homeAmount"]?.numericValue == nil, "homeAmount must never be a JSON number")
    #expect(moneyTree["rate"]?.numericValue == nil, "rate must never be a JSON number")
    if case .string(let homeAmount)? = moneyTree["homeAmount"] {
        #expect(parseDecimal(homeAmount) == dec("67.79"), "homeAmount did not round-trip exactly")
    }
    if case .string(let rate)? = moneyTree["rate"] {
        #expect(parseDecimal(rate) == dec("4.2706"), "rate did not round-trip exactly")
    }
}

// MARK: - Envelope

@Test func envelopeEncodesAndDecodesWithCurrentVersion() throws {
    #expect(PayloadCodec.currentSchemaVersion == 1)

    let payload: JSONValue = .object(["name": .string("Volvo V60"), "archived": .bool(false)])
    let envelope = PayloadEnvelope(entityType: "vehicle",
                                   schemaVersion: PayloadCodec.currentSchemaVersion,
                                   payload: payload)
    let data = try envelope.jsonData()
    let parsed = try PayloadEnvelope.parse(data)
    #expect(parsed.entityType == "vehicle")
    #expect(parsed.schemaVersion == PayloadCodec.currentSchemaVersion)
    #expect(parsed.payload == payload)

    let encoded = try PayloadCodec.encode(fullyPopulatedVehicle())
    #expect(encoded.entityType == "vehicle")
    #expect(encoded.schemaVersion == PayloadCodec.currentSchemaVersion)
    #expect(encoded.payload.isObject)
}

@Test func malformedEnvelopesAreRejected() throws {
    do {
        _ = try PayloadEnvelope.parse(Data("42".utf8))
        Issue.record("parse must reject a non-object document")
    } catch let error as PayloadCodec.Error {
        #expect(error == .malformedEnvelope("envelope must be a JSON object"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }

    do {
        _ = try PayloadEnvelope.parse(Data(#"{"entityType":"vehicle"}"#.utf8))
        Issue.record("parse must reject an envelope missing schemaVersion/payload")
    } catch let error as PayloadCodec.Error {
        #expect(error == .malformedEnvelope(
            "envelope must be { entityType: string, schemaVersion: int, payload: object }"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test func unsupportedSchemaVersionIsRejected() throws {
    let envelope = PayloadEnvelope(entityType: "vehicle", schemaVersion: 2, payload: .object([:]))
    do {
        _ = try PayloadCodec.decode(envelope, as: Vehicle.self)
        Issue.record("decode must reject a future schema version")
    } catch let error as PayloadCodec.Error {
        #expect(error == .unsupportedSchemaVersion(2))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
