import Testing
import Foundation
@testable import TankbookCore

private let timestamp = Date(timeIntervalSince1970: 1_752_000_000)

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func roundTrips<T: Codable & Equatable>(_ value: T) -> Bool {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    guard let data = try? encoder.encode(value),
          let decoded = try? decoder.decode(T.self, from: data) else {
        return false
    }
    return decoded == value
}

@Test func vehicleRoundTrips() {
    let vehicle = Vehicle(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        name: "Volvo V60",
        make: "Volvo",
        model: "V60",
        year: 2021,
        plate: "ABC-123",
        powertrain: .hybrid,
        fuelKinds: [.petrol95, .electricity],
        tankCapacityL: 71,
        batteryCapacityKWh: nil,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: UUID.v7(),
        archived: false,
        paceLimitKmPerDay: 1500
    )
    #expect(roundTrips(vehicle))
}

@Test func fillUpRoundTrips() {
    let fillUp = FillUp(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: timestamp,
        odometer: 82_400,
        money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
        note: "Shell, A4 exit",
        attachments: [UUID.v7(), UUID.v7()],
        provenance: .receiptScan,
        conflict: .flagged(kind: .pace, detectedAt: timestamp),
        purchaseGroupId: UUID.v7(),
        volumeL: 42.3,
        unitPrice: decimal("1.679"),
        fuelKind: .petrol95,
        fuelGrade: "V-Power",
        isFull: true,
        tankLevelAfterPct: 100,
        stationId: UUID.v7(),
        crossCheck: .verified,
        extraction: ExtractionMeta(
            fields: [
                .total: FieldExtraction(cropRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1), confidence: 0.98, userCorrected: true),
                .lineItem(2): FieldExtraction(cropRect: nil, confidence: 0.77, userCorrected: false),
            ],
            pipeline: "vision+rules v3"
        )
    )
    #expect(roundTrips(fillUp))
}

@Test func chargeSessionRoundTrips() {
    let charge = ChargeSession(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: timestamp,
        odometer: 18_000,
        money: nil,
        note: "Free destination charging",
        attachments: [],
        provenance: .fiscalQR,
        conflict: .none,
        purchaseGroupId: nil,
        energyKWh: 43.2,
        unitPrice: nil,
        chargeType: .dcPublic,
        provider: "Ionity",
        tariffId: nil,
        durationMin: 42,
        socStartPct: 18,
        socEndPct: 92,
        extraction: ExtractionMeta(fields: [:], pipeline: "fiscal-qr")
    )
    #expect(roundTrips(charge))
}

@Test func serviceRecordRoundTrips() {
    let service = ServiceRecord(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: timestamp,
        odometer: 90_000,
        money: nil,
        note: nil,
        attachments: [],
        provenance: .screenshot,
        conflict: .none,
        purchaseGroupId: nil,
        vendor: "Bosch Service",
        items: [
            ServiceItem(
                title: "Oil change",
                category: .oil,
                cost: Money(amount: decimal("89.00"), currency: .eur, homeCurrency: .eur),
                partNumber: "MANN W 712/75",
                lifetime: ServiceItem.Lifetime(km: 15_000, months: 12)
            ),
            ServiceItem(
                title: "Cabin filter",
                category: .filters,
                cost: nil,
                partNumber: nil,
                lifetime: nil
            ),
        ],
        usedParts: [UUID.v7()],
        tireSetId: nil,
        proposedReminderId: UUID.v7()
    )
    #expect(roundTrips(service))
}

@Test func expenseRoundTrips() {
    let expense = Expense(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: timestamp,
        odometer: nil,
        money: Money(amount: decimal("540.00"), currency: .eur, homeCurrency: .eur),
        note: nil,
        attachments: [],
        provenance: .manual,
        conflict: .none,
        purchaseGroupId: nil,
        category: .insurance,
        title: "Annual insurance",
        recurrence: RecurrenceRule(everyMonths: 12, anchorDate: timestamp),
        installedInServiceId: nil
    )
    #expect(roundTrips(expense))

    let part = Expense(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: timestamp,
        odometer: nil,
        money: nil,
        note: nil,
        attachments: [],
        provenance: .import(source: "Fuelio"),
        conflict: .none,
        purchaseGroupId: nil,
        category: .other("coffee"),
        title: "Brake pads",
        recurrence: nil,
        installedInServiceId: UUID.v7()
    )
    #expect(roundTrips(part))
}

@Test func reminderRoundTrips() {
    let reminder = Reminder(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        title: "Oil change",
        category: .oil,
        dueDate: timestamp.addingTimeInterval(3_600),
        dueOdometer: 105_000,
        recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12),
        sourceEntryId: UUID.v7(),
        status: .done(entryId: UUID.v7())
    )
    #expect(roundTrips(reminder))

    let dismissed = Reminder(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        title: "Winter tires",
        category: .tires,
        dueDate: nil,
        dueOdometer: nil,
        recurrence: nil,
        sourceEntryId: nil,
        status: .dismissed(reason: "sold the tires")
    )
    #expect(roundTrips(dismissed))
}

@Test func stationRoundTrips() {
    let station = Station(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        name: "Shell Tiergarten",
        brand: "Shell",
        location: GeoCoordinate(latitude: 52.51, longitude: 13.35),
        favorite: true,
        defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: "V-Power"),
        lastUsedAt: timestamp
    )
    #expect(roundTrips(station))
}

@Test func tariffRoundTrips() {
    let tariff = Tariff(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: nil,
        name: "Home night rate",
        pricePerKWh: decimal("0.24"),
        currency: .eur,
        validFrom: timestamp
    )
    #expect(roundTrips(tariff))
}

@Test func tireSetRoundTrips() {
    let tireSet = TireSet(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        name: "Winter Nokian",
        purchaseExpenseId: UUID.v7()
    )
    #expect(roundTrips(tireSet))
}

@Test func attachmentRoundTrips() {
    let attachment = Attachment(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: timestamp,
        kind: .photo,
        file: LocalFileRef(
            sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
            relativePath: "photos/2026/07/9f86d081.jpg"
        ),
        extractedTimestamp: timestamp,
        ocrText: "SHELL 71.02 42.30 1.679"
    )
    #expect(roundTrips(attachment))
}

@Test func preferencesRoundTrips() {
    let preferences = Preferences(
        createdAt: timestamp,
        updatedAt: timestamp,
        notifications: Preferences.Notifications(reminders: true, anomalies: false, monthlySummary: true),
        eagerMediaOnWiFi: true,
        defaultVehicleId: UUID.v7(),
        proFeedbackDiagnostics: true
    )
    #expect(roundTrips(preferences))

    #expect(preferences.id == Preferences.fixedID)
}

@Test func exchangeRateRoundTrips() {
    let rate = ExchangeRate(
        base: .eur,
        quote: .pln,
        date: timestamp,
        rate: decimal("4.2706"),
        source: .ecb
    )
    #expect(roundTrips(rate))
}

@Test func extractionDictionaryWithLineItemKeyRoundTrips() {
    let meta = ExtractionMeta(
        fields: [
            .total: FieldExtraction(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1), confidence: 0.99, userCorrected: false),
            .currency: FieldExtraction(cropRect: nil, confidence: 0.60, userCorrected: true),
            .lineItem(3): FieldExtraction(cropRect: nil, confidence: 0.71, userCorrected: false),
        ],
        pipeline: "vision+rules v3"
    )
    #expect(roundTrips(meta))
}

@Test func moneyWithSnapshotRoundTrips() {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
        .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: timestamp, source: .ecb))
    #expect(money.hasSnapshot)
    #expect(roundTrips(money))
}
