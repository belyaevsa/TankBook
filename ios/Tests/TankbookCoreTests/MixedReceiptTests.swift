import Foundation
import Testing
@testable import TankbookCore

// P2.4 mixed-receipt detection + grouped-save plan. The detection's two signals
// (fiscal-QR excess and line-item structure), the 129.00 collision, the
// false-positive guard over non-mixed fixtures, and the two hard-rule-4
// invariants (fuel line not grand total; logged group never exceeds the receipt)
// in pure form. No Vision, no images.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func lines(_ texts: [String]) -> [OCRLine] {
    texts.map { OCRLine(text: $0) }
}

private func extraction(liters: Double? = nil, unitPrice: Decimal? = nil,
                        total: Decimal? = nil) -> FuelExtraction {
    FuelExtraction(liters: liters, unitPrice: unitPrice, total: total)
}

private func qrAnchor(_ total: String) -> FiscalQRAnchor {
    FiscalQRAnchor(total: decimal(total), date: Date(timeIntervalSince1970: 1_700_000_000))
}

/// One fuel-only receipt case for the false-positive guard.
private struct MixedReceiptCase {
    let texts: [String]
    let extraction: FuelExtraction
    let qr: FiscalQRAnchor?
}

/// The one mixed corpus fixture (receipt-009): fuel 47.56 л x 129.00 = 6135.24,
/// bottled water 1 x 129.00, grand total 6264.00 (rounded from 6264.24). The
/// water's 129.00 is the exact same number as the fuel's price per litre.
private let receipt009 = [
    "95 V-Power АН-95-K5 (1 ТРК)", "26135.24 НДС 22%", "47.56 л Х 129,00",
    "Округление в пользу клиента", "Вода Святой Источник 0.5л",
    "1 т. X 129.00", "6264.24", "ВСЕГО", "ОКРУГЛЕНИЕ", "6264.00", "ИТОГ",
    "6264.00", "БЕЗНАЛИЧНЫМИ"
]

private func receipt009Extraction() -> FuelExtraction {
    FuelExtraction(liters: 47.56, unitPrice: decimal("129.00"), total: decimal("6135.24"),
                   currency: .rub, fuelKind: .petrol95)
}

// MARK: - Detection

@Suite("Mixed receipt: detection")
struct MixedReceiptDetectorTests {

    @Test("receipt-009 isolates the fuel line, not the grand total")
    func receipt009IsolatesTheFuelLine() {
        let detection = MixedReceiptDetector.detect(lines: lines(receipt009),
                                                    extraction: receipt009Extraction(),
                                                    qrAnchor: qrAnchor("6264.00"))
        guard case .mixed(_, let fuelLine, _) = detection else {
            Issue.record("receipt-009 should be detected as mixed")
            return
        }
        #expect(fuelLine == decimal("6135.24"))
        #expect(fuelLine != decimal("6264.00"))
    }

    @Test("the 129.00 collision: water total is not the fuel unit price")
    func waterTotalIsNotConfusedWithFuelUnitPrice() {
        let detection = MixedReceiptDetector.detect(lines: lines(receipt009),
                                                    extraction: receipt009Extraction(),
                                                    qrAnchor: qrAnchor("6264.00"))
        guard case .mixed(let items, let fuelLine, _) = detection else {
            Issue.record("receipt-009 should be detected as mixed")
            return
        }
        // Exactly one non-fuel item: the water. The fuel line's own unit price
        // (129.00) is NOT offered as a second item, and the water is identified
        // by its product name, not by matching on a number that appears twice.
        #expect(items.count == 1)
        #expect(items[0].amount == decimal("129.00"))
        #expect(items[0].title.contains("Вода"))
        #expect(items[0].title.contains("Вода") && !items[0].title.contains("V-Power"))
        // The fuel line is 47.56 x 129.00, not the water's 129.00 nor the grand total.
        #expect(fuelLine == decimal("6135.24"))
    }

    @Test("no QR: still detected by line-item structure")
    func noQRStillDetectedByStructure() {
        let detection = MixedReceiptDetector.detect(lines: lines(receipt009),
                                                    extraction: receipt009Extraction(),
                                                    qrAnchor: nil)
        guard case .mixed(let items, let fuelLine, let grandTotal) = detection else {
            Issue.record("receipt-009 without a QR should still be detected by structure")
            return
        }
        #expect(fuelLine == decimal("6135.24"))
        #expect(items.count == 1)
        #expect(items[0].amount == decimal("129.00"))
        // The line-extension total (fuel + water) is the group's ceiling.
        #expect(grandTotal == decimal("6264.24"))
    }

    @Test("a QR that agrees with the fuel line is not mixed")
    func qrAgreeingWithFuelLineIsNotMixed() {
        // A plain fill: QR total equals the fuel line, no non-fuel items.
        let plainLines = ["ДТ-Л-К5 ДИЗЕЛЬ", "42.30 л X 1.679", "ИТОГ", "71.02"]
        let detection = MixedReceiptDetector.detect(lines: lines(plainLines),
                                                    extraction: extraction(liters: 42.30,
                                                                           unitPrice: decimal("1.679"),
                                                                           total: decimal("71.02")),
                                                    qrAnchor: qrAnchor("71.02"))
        #expect(detection == .notMixed)
    }

    @Test("non-mixed corpus receipts are never flagged mixed")
    func fuelOnlyReceiptsAreNotMixed() {
        // receipt-007 (ЛУКОЙЛ, rounded total, a discount line): one operand pair.
        let receipt007 = ["43.61 Х 99.40", "=4334.83_НДС 22%", "В ТОМ ЧИСЛЕ ВАША СКИДКА = 0.83",
                          "ИТОГ", "4334.00", "ОКРУГЛЕНИЕ", "0.83", "СУММА НДС 22%", "=781.69"]
        // receipt-011 (Самара, VAT-line trap): one operand pair.
        let receipt011 = ["1 ДТ-Л-К5 N 1:09005", "=4201.68", "62.89*66.810л", "НДС 20%",
                          "ДТ-Л-К5", "=4201.68", "ИТОГ", "=700.28", "СУММА НДС 20%", "=4201.68",
                          "БЕЗНАЛИЧНЫМИ"]
        // receipt-002 (Крым Оил, unmarked operand): one operand pair.
        let receipt002 = ["1 АН-100-K5 АИ-100-K5 (3 ТРК)", "n=19719.00", "450.00*43.820",
                          "НДС 22%", "ПОДАКЦИЗНЫЙ ТОВАР", "=19719.00", "ИТОГ", "=3555.89",
                          "СУММА НДС 22%", "=19719.00", "НАЛИЧНЫМИ", "=19719.00"]

        let cases = [
            MixedReceiptCase(texts: receipt007,
                             extraction: extraction(liters: 43.61, unitPrice: decimal("99.40"),
                                                    total: decimal("4334.00")),
                             qr: qrAnchor("4334.00")),
            MixedReceiptCase(texts: receipt011,
                             extraction: extraction(liters: 66.810, unitPrice: decimal("62.89"),
                                                    total: decimal("4201.68")),
                             qr: qrAnchor("4201.68")),
            MixedReceiptCase(texts: receipt002,
                             extraction: extraction(liters: 43.820, unitPrice: decimal("450.00"),
                                                    total: decimal("19719.00")),
                             qr: qrAnchor("19719.00"))
        ]
        for candidate in cases {
            let detection = MixedReceiptDetector.detect(lines: lines(candidate.texts),
                                                        extraction: candidate.extraction,
                                                        qrAnchor: candidate.qr)
            #expect(detection == .notMixed,
                    "a fuel-only receipt was flagged mixed: \(candidate.texts.first ?? "")")
        }
    }

    @Test("a second operand pair that does not explain the total is not mixed")
    func unexplainedOperandPairIsNotMixed() {
        // A stray non-fuel operand pair whose amount does NOT bridge the fuel
        // line to the receipt total must not be trusted (conservative, hard
        // rule 13): fuel 71.02 + a phantom 500.00 line cannot equal ИТОГ 71.02.
        let texts = ["ДТ ДИЗЕЛЬ", "42.30 л X 1.679", "Стеклоомыватель", "2 X 500.00",
                     "ИТОГ", "71.02"]
        let detection = MixedReceiptDetector.detect(lines: lines(texts),
                                                    extraction: extraction(liters: 42.30,
                                                                           unitPrice: decimal("1.679"),
                                                                           total: decimal("71.02")),
                                                    qrAnchor: nil)
        #expect(detection == .notMixed)
    }

    @Test("the artboard shape: car wash accepted, coffee dismissed by category")
    func artboardShapeDetectsTwoItemsWithCategories() {
        let texts = ["ДТ-Л-К5 ДИЗЕЛЬ", "42.30 л X 1.679", "Мойка кузова", "1 X 8.00",
                     "Кофе американо", "1 X 4.80", "83.82", "ИТОГ", "БЕЗНАЛИЧНЫМИ", "83.82"]
        let detection = MixedReceiptDetector.detect(lines: lines(texts),
                                                    extraction: extraction(liters: 42.30,
                                                                           unitPrice: decimal("1.679"),
                                                                           total: decimal("71.02")),
                                                    qrAnchor: nil)
        guard case .mixed(let items, let fuelLine, let grandTotal) = detection else {
            Issue.record("the two-item receipt should be detected as mixed")
            return
        }
        #expect(fuelLine == decimal("71.02"))
        #expect(items.count == 2)
        #expect(grandTotal == decimal("83.82"))
        let wash = items.first { $0.title.contains("Мойка") }
        let coffee = items.first { $0.title.contains("Кофе") }
        #expect(wash?.amount == decimal("8.00"))
        #expect(wash?.isCarRelated == true)
        #expect(coffee?.amount == decimal("4.80"))
        #expect(coffee?.isCarRelated == false)
    }
}

// MARK: - Grouped-save plan (the two invariants)

@Suite("Mixed receipt: grouped-save plan")
struct MixedReceiptGroupPlanTests {

    private func detection(_ acceptedLines: [String]) -> MixedReceiptDetection {
        // A three-item receipt: fuel + car wash + coffee + toll, exact numbers.
        let texts = ["ДТ ДИЗЕЛЬ", "42.30 л X 1.679", "Мойка кузова", "1 X 8.00",
                     "Кофе американо", "1 X 4.80", "Платный участок", "1 X 12.00",
                     "95.82", "ИТОГ", "БЕЗНАЛИЧНЫМИ", "95.82"]
        return MixedReceiptDetector.detect(lines: lines(texts),
                                           extraction: extraction(liters: 42.30,
                                                                  unitPrice: decimal("1.679"),
                                                                  total: decimal("71.02")),
                                           qrAnchor: nil)
    }

    private func ids(_ detection: MixedReceiptDetection, matching name: String) -> Set<UUID> {
        Set(detection.lines.filter { $0.title.contains(name) }.map(\.id))
    }

    @Test("accepted lines share one purchaseGroupId with the fill-up")
    func acceptedLinesShareOneGroupId() {
        let det = detection([])
        guard case .mixed(let lines, let fuelLine, _) = det else {
            Issue.record("expected a mixed detection")
            return
        }
        let plan = ReceiptGroupPlanner.plan(detection: det,
                                            fillUpAmount: fuelLine,
                                            acceptedLineIDs: Set(lines.map(\.id)))
        #expect(plan != nil)
        guard let plan else { return }
        // The plan carries ONE id and the expenses inherit it at save time, so
        // there is nothing to compare inside a single plan - which is why the
        // original `plan.purchaseGroupId == plan.purchaseGroupId` here proved
        // nothing. What IS assertable at this level: every accepted line makes
        // it into the plan, and two plans do not share an id (a constant or
        // default UUID would silently merge unrelated purchases into one group).
        #expect(plan.expenses.count == lines.count,
                "every accepted line must appear in the plan")
        let other = ReceiptGroupPlanner.plan(detection: det,
                                             fillUpAmount: fuelLine,
                                             acceptedLineIDs: Set(lines.map(\.id)))
        #expect(other?.purchaseGroupId != plan.purchaseGroupId,
                "each grouped save must mint its own id, never a shared constant")

        // That the FillUp and the Expenses actually receive this id is asserted
        // in the persistence suite, where the rows exist to be read back.
    }

    @Test("the fill-up amount is the fuel line, never the grand total")
    func fillUpAmountIsTheFuelLine() {
        let det = detection([])
        guard case .mixed(let lines, let fuelLine, let grandTotal) = det else {
            Issue.record("expected a mixed detection")
            return
        }
        let plan = ReceiptGroupPlanner.plan(detection: det, fillUpAmount: fuelLine,
                                            acceptedLineIDs: Set(lines.map(\.id)))
        #expect(plan?.fillUpAmount == fuelLine)
        #expect(plan?.fillUpAmount != grandTotal)
        #expect(fuelLine == decimal("71.02"))
        #expect(grandTotal == decimal("95.82"))
    }

    @Test("the logged group never exceeds the receipt, across compositions")
    func loggedGroupNeverExceedsReceipt() {
        let det = detection([])
        guard case .mixed(let lines, let fuelLine, let grandTotal) = det else {
            Issue.record("expected a mixed detection")
            return
        }
        let allIDs = Set(lines.map(\.id))
        let washIDs = ids(det, matching: "Мойка")
        let coffeeIDs = ids(det, matching: "Кофе")
        let tollIDs = ids(det, matching: "Платный")

        // Every subset of accepted lines: the sum is always <= the receipt
        // total, and equals it only when every line is accepted.
        let compositions: [(Set<UUID>, Decimal)] = [
            (allIDs, decimal("95.82")),              // everything
            (washIDs, decimal("79.02")),             // fuel + wash
            (coffeeIDs, decimal("75.82")),           // fuel + coffee
            (tollIDs, decimal("83.02")),             // fuel + toll
            (washIDs.union(coffeeIDs), decimal("83.82")),
            (washIDs.union(tollIDs), decimal("91.02")),
            ([], fuelLine)                             // nothing accepted
        ]
        for (accepted, expectedLogged) in compositions {
            let plan = ReceiptGroupPlanner.plan(detection: det, fillUpAmount: fuelLine,
                                                acceptedLineIDs: accepted)
            guard let plan else {
                Issue.record("plan should build for every composition")
                continue
            }
            #expect(plan.respectsReceiptTotal, "logged \(plan.loggedTotal) exceeded \(plan.receiptTotal)")
            #expect(plan.loggedTotal == expectedLogged)
            #expect(plan.loggedTotal <= grandTotal)
        }
    }

    @Test("a dismissed line produces no expense")
    func dismissedLineProducesNoExpense() {
        let det = detection([])
        guard case .mixed(_, let fuelLine, _) = det else {
            Issue.record("expected a mixed detection")
            return
        }
        // Accept only the wash; dismiss coffee and toll.
        let accepted = ids(det, matching: "Мойка")
        let plan = ReceiptGroupPlanner.plan(detection: det, fillUpAmount: fuelLine,
                                            acceptedLineIDs: accepted)
        guard let plan else {
            Issue.record("plan should build")
            return
        }
        #expect(plan.expenses.count == 1)
        #expect(plan.expenses.first?.title.contains("Мойка") == true)
        // The dismissed lines are absent from the plan, so no Expense is ever
        // built for them.
        #expect(!plan.expenses.contains { $0.title.contains("Кофе") })
        #expect(!plan.expenses.contains { $0.title.contains("Платный") })
    }
}

// MARK: - Persistence: dismissed lines create no rows

@Suite("Mixed receipt: grouped save persists only accepted lines")
struct MixedReceiptPersistenceTests {

    @Test("accepted expenses share the fill-up's purchaseGroupId; dismissed lines have no row")
    func groupedSavePersistsOnlyAcceptedLines() throws {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Volvo V60", make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
            batteryCapacityKWh: nil, homeCurrency: .rub,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
        try repository.upsertVehicle(vehicle)

        let texts = ["ДТ ДИЗЕЛЬ", "47.56 л X 129.00", "Мойка кузова", "1 X 8.00",
                     "Кофе американо", "1 X 4.80", "6148.04", "ИТОГ", "БЕЗНАЛИЧНЫМИ", "6148.04"]
        let detection = MixedReceiptDetector.detect(
            lines: lines(texts),
            extraction: FuelExtraction(liters: 47.56, unitPrice: decimal("129.00"), total: decimal("6135.24"),
                                       currency: .rub, fuelKind: .petrol95),
            qrAnchor: nil)
        guard case .mixed(let items, let fuelLine, _) = detection else {
            Issue.record("expected a mixed detection")
            return
        }
        let accepted = Set(items.filter { $0.title.contains("Мойка") }.map(\.id))
        let plan = ReceiptGroupPlanner.plan(detection: detection, fillUpAmount: fuelLine,
                                            acceptedLineIDs: accepted)
        guard let plan else {
            Issue.record("plan should build")
            return
        }

        let now = Date()
        let fillUp = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: plan.fillUpAmount, currency: .rub, homeCurrency: .rub),
            note: nil, attachments: [], provenance: .receiptScan, conflict: .none,
            purchaseGroupId: plan.purchaseGroupId,
            volumeL: 47.56, unitPrice: decimal("129.00"), fuelKind: .petrol95,
            fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
        try repository.upsertFillUp(fillUp)

        for expense in plan.expenses {
            let row = Expense(
                id: expense.id, createdAt: now, updatedAt: now, deletedAt: nil,
                vehicleId: vehicle.id, date: now, odometer: nil,
                money: Money(amount: expense.amount, currency: .rub, homeCurrency: .rub),
                note: nil, attachments: [], provenance: .receiptScan, conflict: .none,
                purchaseGroupId: plan.purchaseGroupId, category: expense.category,
                title: expense.title)
            try repository.upsertExpense(row)
        }

        let savedExpenses = try repository.liveExpenses(forVehicle: vehicle.id)
        #expect(savedExpenses.count == 1)
        #expect(savedExpenses.first?.title.contains("Мойка") == true)
        #expect(savedExpenses.allSatisfy { $0.purchaseGroupId == plan.purchaseGroupId })
        // The dismissed coffee line has no row at all.
        #expect(!savedExpenses.contains { $0.title.contains("Кофе") })
        // The fill-up shares the same group id.
        let savedFillUp = try #require(try repository.liveFillUps(forVehicle: vehicle.id).first)
        #expect(savedFillUp.purchaseGroupId == plan.purchaseGroupId)
        #expect(savedFillUp.money?.amount == decimal("6135.24"))
    }
}
