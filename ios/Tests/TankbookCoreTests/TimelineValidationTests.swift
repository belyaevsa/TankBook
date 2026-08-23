import Testing
import Foundation
@testable import TankbookCore

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func vehicle(paceLimit: Double = 1500) -> Vehicle {
    Vehicle(
        id: UUID.v7(),
        createdAt: epoch,
        updatedAt: epoch,
        deletedAt: nil,
        name: "Test car",
        make: nil,
        model: nil,
        year: nil,
        plate: nil,
        powertrain: .ice,
        fuelKinds: [.petrol95],
        tankCapacityL: nil,
        batteryCapacityKWh: nil,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil,
        paceLimitKmPerDay: paceLimit
    )
}

private func fill(date: Date, odometer: Int, volumeL: Double = 40,
                  id: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: id,
        createdAt: date,
        updatedAt: date,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: date,
        odometer: odometer,
        money: nil,
        note: nil,
        attachments: [],
        provenance: .manual,
        conflict: .none,
        purchaseGroupId: nil,
        volumeL: volumeL,
        unitPrice: nil,
        fuelKind: .petrol95,
        fuelGrade: nil,
        isFull: true,
        tankLevelAfterPct: nil,
        stationId: nil,
        crossCheck: .notApplicable,
        extraction: nil
    )
}

// MARK: - INVARIANT

@Test func invariantHoldsForInOrderOdometers() {
    let entries: [any Entry] = [
        fill(date: epoch, odometer: 10_000),
        fill(date: epoch + 5 * day, odometer: 10_200),
        fill(date: epoch + 10 * day, odometer: 10_500),
    ]
    #expect(TimelineValidator.invariantHolds(entries: entries))
}

@Test func invariantBreaksForOutOfOrderOdometer() {
    let entries: [any Entry] = [
        fill(date: epoch, odometer: 10_000),
        fill(date: epoch + 5 * day, odometer: 9_990),
    ]
    #expect(!TimelineValidator.invariantHolds(entries: entries))
}

@Test func invariantBreaksForEqualOdometers() {
    let entries: [any Entry] = [
        fill(date: epoch, odometer: 10_000),
        fill(date: epoch + 5 * day, odometer: 10_000),
    ]
    #expect(!TimelineValidator.invariantHolds(entries: entries))
}

@Test func invariantSkipsEntriesWithoutOdometer() {
    var noOdo = fill(date: epoch, odometer: 10_000)
    noOdo.odometer = nil
    let entries: [any Entry] = [
        noOdo,
        fill(date: epoch + 5 * day, odometer: 9_990),
    ]
    // Only one entry carries an odometer: nothing to compare, invariant holds.
    #expect(TimelineValidator.invariantHolds(entries: entries))
}

// MARK: - CHECK 1: order

@Test func outOfOrderEntryIsFlaggedOrderAndStillSaveable() {
    let first = fill(date: epoch, odometer: 10_000)
    let middle = fill(date: epoch + 5 * day, odometer: 10_050)
    let bad = fill(date: epoch + 10 * day, odometer: 10_020)

    let results = TimelineValidator.validate(entries: [first, middle, bad], vehicle: vehicle())
    let validation = results.first { $0.entryID == bad.id }
    #expect(validation?.flags.contains { $0.kind == .order } == true)
    #expect(validation?.conflict == .flagged(kind: .order, detectedAt: bad.createdAt))
    #expect(validation?.isSaveable == true)
}

@Test func equalOdometerEntryIsFlaggedOrder() {
    let first = fill(date: epoch, odometer: 10_000)
    let equal = fill(date: epoch + 5 * day, odometer: 10_000)

    let validation = TimelineValidator.validate(entries: [first, equal], vehicle: vehicle())
        .first { $0.entryID == equal.id }
    #expect(validation?.flags.contains { $0.kind == .order } == true)
}

@Test func inOrderEntriesCarryNoFlags() {
    let first = fill(date: epoch, odometer: 10_000)
    let second = fill(date: epoch + 5 * day, odometer: 10_200)

    let validations = TimelineValidator.validate(entries: [first, second], vehicle: vehicle())
    #expect(validations.allSatisfy { $0.flags.isEmpty })
    #expect(validations.allSatisfy { $0.conflict == .none })
}

// MARK: - CHECK 2: pace

@Test func paceJustUnderLimitIsNotFlagged() {
    let first = fill(date: epoch, odometer: 10_000)
    let candidate = fill(date: epoch + 10 * day, odometer: 10_099) // 9.9 km/day

    let validation = TimelineValidator.validate(entries: [first, candidate], vehicle: vehicle(paceLimit: 10))
        .first { $0.entryID == candidate.id }
    #expect(validation?.flags.isEmpty == true)
}

@Test func paceJustOverLimitIsFlagged() {
    let first = fill(date: epoch, odometer: 10_000)
    let candidate = fill(date: epoch + 10 * day, odometer: 10_101) // 10.1 km/day

    let validation = TimelineValidator.validate(entries: [first, candidate], vehicle: vehicle(paceLimit: 10))
        .first { $0.entryID == candidate.id }
    #expect(validation?.flags.contains { $0.kind == .pace } == true)
    #expect(validation?.conflict == .flagged(kind: .pace, detectedAt: candidate.createdAt))
}

@Test func customPaceLimitChangesOutcome() {
    let first = fill(date: epoch, odometer: 10_000)
    let candidate = fill(date: epoch + 10 * day, odometer: 10_100) // 10 km/day

    let strict = TimelineValidator.validate(entries: [first, candidate], vehicle: vehicle(paceLimit: 5))
        .first { $0.entryID == candidate.id }
    let relaxed = TimelineValidator.validate(entries: [first, candidate], vehicle: vehicle(paceLimit: 20))
        .first { $0.entryID == candidate.id }

    #expect(strict?.flags.contains { $0.kind == .pace } == true)
    #expect(relaxed?.flags.contains { $0.kind == .pace } == false)
}

@Test func defaultPaceLimitIs1500() {
    let first = fill(date: epoch, odometer: 10_000)
    let candidate = fill(date: epoch + 1 * day, odometer: 11_500) // 1500 km/day

    let atLimit = TimelineValidator.validate(entries: [first, candidate], vehicle: vehicle())
        .first { $0.entryID == candidate.id }
    #expect(atLimit?.flags.contains { $0.kind == .pace } == false)

    let over = fill(date: epoch + 1 * day, odometer: 11_501) // 1501 km/day
    let overLimit = TimelineValidator.validate(entries: [first, over], vehicle: vehicle())
        .first { $0.entryID == over.id }
    #expect(overLimit?.flags.contains { $0.kind == .pace } == true)
}

// MARK: - CHECK 3: cross-check

@Test func crossCheckVerifiesInsideToleranceAtBoundary() {
    // computed = 10 x 2.00 = 20.00; tolerance = max(0.02, amount x 0.005),
    // which depends on the actual amount: 20.10 -> 0.1005, 19.90 -> 0.0995.
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: decimal("2.00"), amount: decimal("20.00")) == .verified)
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: decimal("2.00"), amount: decimal("20.10")) == .verified)
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: decimal("2.00"), amount: decimal("20.11")) == .mismatch(field: .total))
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: decimal("2.00"), amount: decimal("19.90")) == .mismatch(field: .total))
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: decimal("2.00"), amount: decimal("19.89")) == .mismatch(field: .total))
}

@Test func crossCheckToleranceHasSmallAmountFloor() {
    // computed = 0.5 x 2.00 = 1.00; tolerance = max(0.02, 0.005) = 0.02
    #expect(TimelineValidator.crossCheck(volumeL: 0.5, unitPrice: decimal("2.00"), amount: decimal("1.02")) == .verified)
    #expect(TimelineValidator.crossCheck(volumeL: 0.5, unitPrice: decimal("2.00"), amount: decimal("1.03")) == .mismatch(field: .total))
}

@Test func crossCheckNotApplicableWhenFieldsMissing() {
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: nil, amount: decimal("20.00")) == .notApplicable)
    #expect(TimelineValidator.crossCheck(volumeL: 10, unitPrice: decimal("2.00"), amount: nil) == .notApplicable)
}

@Test func validateEmbedsFillUpCrossCheck() {
    var fillUp = fill(date: epoch, odometer: 10_000)
    fillUp.volumeL = 10
    fillUp.unitPrice = decimal("2.00")
    fillUp.money = Money(amount: decimal("20.05"), currency: .eur, homeCurrency: .eur)

    let validation = TimelineValidator.validate(entries: [fillUp], vehicle: vehicle()).first
    #expect(validation?.crossCheck == .verified)
}

// MARK: - PRIORITY: receipt date is ground truth

@Test func receiptTimestampRanksFixOdometerFirstAndConfirmsDateChange() {
    let first = fill(date: epoch, odometer: 10_000)
    let middle = fill(date: epoch + 5 * day, odometer: 10_050)
    var bad = fill(date: epoch + 10 * day, odometer: 10_020) // out of order
    let receiptID = UUID.v7()
    bad.attachments = [receiptID]
    let receipt = Attachment(
        id: receiptID,
        createdAt: epoch,
        updatedAt: epoch,
        deletedAt: nil,
        kind: .photo,
        file: LocalFileRef(sha256: "sha", relativePath: "receipt.jpg"),
        extractedTimestamp: epoch + 2 * day,
        ocrText: nil
    )

    let validation = TimelineValidator.validate(
        entries: [first, middle, bad],
        vehicle: vehicle(),
        attachments: [receipt]
    ).first { $0.entryID == bad.id }

    #expect(validation?.suggestions == [
        .fixOdometer(from: nil, to: nil),
        .fixDate(from: nil, to: nil, requiresExplicitConfirmation: true),
    ])
}

@Test func manualEntryWithoutReceiptRanksDateChangeFirstWithoutConfirmation() {
    let first = fill(date: epoch, odometer: 10_000)
    let middle = fill(date: epoch + 5 * day, odometer: 10_050)
    let bad = fill(date: epoch + 10 * day, odometer: 10_020) // out of order

    let validation = TimelineValidator.validate(entries: [first, middle, bad], vehicle: vehicle())
        .first { $0.entryID == bad.id }

    #expect(validation?.suggestions == [
        .fixDate(from: nil, to: nil, requiresExplicitConfirmation: false),
        .fixOdometer(from: nil, to: nil),
    ])
}

@Test func attachmentWithoutTimestampIsNotGroundTruth() {
    let first = fill(date: epoch, odometer: 10_000)
    let middle = fill(date: epoch + 5 * day, odometer: 10_050)
    var bad = fill(date: epoch + 10 * day, odometer: 10_020)
    let photoID = UUID.v7()
    bad.attachments = [photoID]
    let photo = Attachment(
        id: photoID,
        createdAt: epoch,
        updatedAt: epoch,
        deletedAt: nil,
        kind: .photo,
        file: LocalFileRef(sha256: "sha", relativePath: "dashcam.jpg"),
        extractedTimestamp: nil,
        ocrText: nil
    )

    let validation = TimelineValidator.validate(
        entries: [first, middle, bad],
        vehicle: vehicle(),
        attachments: [photo]
    ).first { $0.entryID == bad.id }

    #expect(validation?.suggestions == [
        .fixDate(from: nil, to: nil, requiresExplicitConfirmation: false),
        .fixOdometer(from: nil, to: nil),
    ])
}

// MARK: - Multi-type timeline

@Test func validateHandlesMixedEntryTypes() {
    let fuel = fill(date: epoch, odometer: 10_000)
    let service = ServiceRecord(
        id: UUID.v7(), createdAt: epoch + 3 * day, updatedAt: epoch + 3 * day,
        deletedAt: nil, vehicleId: UUID.v7(), date: epoch + 3 * day,
        odometer: 10_300, money: nil, note: nil, attachments: [],
        provenance: .manual, conflict: .none, purchaseGroupId: nil,
        vendor: "Garage", items: [], usedParts: [], tireSetId: nil,
        proposedReminderId: nil
    )
    let expense = Expense(
        id: UUID.v7(), createdAt: epoch + 6 * day, updatedAt: epoch + 6 * day,
        deletedAt: nil, vehicleId: UUID.v7(), date: epoch + 6 * day,
        odometer: 10_700, money: nil, note: nil, attachments: [],
        provenance: .manual, conflict: .none, purchaseGroupId: nil,
        category: .toll, title: "Toll", recurrence: nil, installedInServiceId: nil
    )

    let validations = TimelineValidator.validate(entries: [fuel, service, expense], vehicle: vehicle())
    #expect(validations.count == 3)
    #expect(validations.allSatisfy { $0.flags.isEmpty })
    // Cross-check applies only to FillUp entries.
    #expect(validations.first { $0.entryID == fuel.id }?.crossCheck == .notApplicable)
    #expect(validations.first { $0.entryID == service.id }?.crossCheck == nil)
}
