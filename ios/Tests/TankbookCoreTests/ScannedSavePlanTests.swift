import Testing
import Foundation
@testable import TankbookCore

/// PJ.2 the scanned-save plan: a scanned save keeps the photo, referenced once
/// and shared by the fill-up and every accepted expense; provenance names how
/// the capture arrived; and `userCorrected` feeds the accuracy feed
/// (`docs/EXTRACTION.md` - "pre-fill overwritten by the user"). The typed path
/// stays a peer: no attachment, `.manual`, no extraction record (hard rule 15).
@Suite struct ScannedSavePlanTests {

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    private func extraction(liters: Double? = nil, unitPrice: Decimal? = nil,
                            total: Decimal? = nil, currency: CurrencyCode? = nil,
                            fuelKind: FuelKind? = nil, date: String? = nil) -> FuelExtraction {
        FuelExtraction(liters: liters, unitPrice: unitPrice, total: total,
                       currency: currency, fuelKind: fuelKind, date: date)
    }

    private func plan(_ extraction: FuelExtraction?,
                      cropRects: [FieldRef: CGRect] = [:],
                      qrAnchor: FiscalQRAnchor? = nil,
                      declared: Provenance = .receiptScan,
                      hasPhoto: Bool = true,
                      saved: ScannedSaveValues) -> ScannedSavePlan {
        ScannedSavePlanner.plan(extraction: extraction,
                                cropRects: cropRects,
                                qrAnchor: qrAnchor,
                                declaredProvenance: declared,
                                hasPhoto: hasPhoto,
                                saved: saved)
    }

    private func qr(_ total: String) -> FiscalQRAnchor {
        FiscalQRAnchor(total: decimal(total), date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - The shared id

    @Test("the plan mints ONE attachment id, shared by the fill and every expense")
    func oneIdSharedByEveryRow() {
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679"), total: decimal("71.02"),
                                      currency: .eur, fuelKind: .petrol95, date: "17.08.2026"),
                           cropRects: [.total: CGRect(x: 1, y: 2, width: 3, height: 4),
                                       .volume: CGRect(x: 5, y: 6, width: 7, height: 8)],
                           saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                                    unitPrice: decimal("1.679"), currency: .eur,
                                                    fuelKind: .petrol95, date: Date()))
        #expect(scanned.attachmentID != nil)
        // The id is read for the fill-up AND for each accepted expense - every
        // read returns the SAME id. A per-row mint would break the shared-photo
        // promise (J3 mixed variant: one receipt photo for the group).
        let fill = scanned.sharedAttachmentIDs
        let expenseA = scanned.sharedAttachmentIDs
        let expenseB = scanned.sharedAttachmentIDs
        #expect(fill.count == 1)
        #expect(fill == expenseA && fill == expenseB)
        #expect(scanned.sharedAttachmentIDs == [scanned.attachmentID!])
    }

    @Test("the typed path shares nothing, even with a photo in hand")
    func typedPathSharesNothing() {
        // No prefill means no scan: nothing to attach, `.manual`, no extraction
        // record - even when a photo exists. The app never hits this (a photo
        // only arrives inside a prefill), but the planner's contract must hold
        // unconditionally, not merely in the one shape the app produces.
        let typed = plan(nil, hasPhoto: true, saved: ScannedSaveValues())
        #expect(typed.attachmentID == nil)
        #expect(typed.sharedAttachmentIDs.isEmpty)
        #expect(typed.provenance == .manual)
        #expect(typed.extraction == nil)
    }

    @Test("PJ.17 an all-nil scan with a photo still attaches it")
    func emptyScanWithPhotoStillAttachesIt() {
        // The PJ.17 empty-but-alive promise: the caption says "the photo stays
        // attached" for a scan that resolved NOTHING - an all-nil extraction
        // is a prefill (never the typed path), so its photo MUST be written,
        // and the save records scan provenance, never `.manual`. A promise in
        // copy the code does not keep is worse than no copy.
        let scanned = plan(extraction(), hasPhoto: true,
                           saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                                    unitPrice: decimal("1.679")))
        #expect(scanned.attachmentID != nil,
                "a scan that resolved nothing still keeps its photo on save (PJ.17)")
        #expect(scanned.sharedAttachmentIDs == [scanned.attachmentID!])
        #expect(scanned.provenance != .manual)
        #expect(scanned.extraction != nil)
    }

    // MARK: - Provenance

    @Test("a scanned save is never .manual")
    func scannedSaveIsNeverManual() {
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679")),
                           saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                                    unitPrice: decimal("1.679")))
        #expect(scanned.provenance != .manual)
        #expect(scanned.provenance == .receiptScan)
    }

    @Test("a fiscal QR outranks the declared provenance")
    func qrBecomesFiscalProvenance() {
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679"), total: decimal("71.02")),
                           qrAnchor: qr("71.02"),
                           saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                                    unitPrice: decimal("1.679")))
        #expect(scanned.provenance == .fiscalQR)
    }

    @Test("a pump capture keeps pump provenance")
    func pumpProvenanceSurvives() {
        let scanned = plan(extraction(liters: 60.25, unitPrice: decimal("76.24"), total: decimal("4593.46")),
                           declared: .pumpPhoto,
                           saved: ScannedSaveValues(total: decimal("4593.46"), volumeL: 60.25,
                                                    unitPrice: decimal("76.24")))
        #expect(scanned.provenance == .pumpPhoto)
    }

    // MARK: - The extraction record

    @Test("a scanned save carries the extraction record with crop rects")
    func scannedSaveCarriesExtraction() {
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679"), total: decimal("71.02"),
                                      currency: .eur, fuelKind: .petrol95, date: "17.08.2026"),
                           cropRects: [.total: CGRect(x: 1, y: 2, width: 3, height: 4),
                                       .volume: CGRect(x: 5, y: 6, width: 7, height: 8),
                                       .unitPrice: CGRect(x: 9, y: 10, width: 11, height: 12)],
                           saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                                    unitPrice: decimal("1.679"), currency: .eur,
                                                    fuelKind: .petrol95, date: Date()))
        let meta = scanned.extraction
        #expect(meta != nil)
        guard let meta else { return }
        #expect(meta.fields.count == 6, "every resolved field must be recorded")
        #expect(meta.fields[.total]?.cropRect == CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(meta.fields[.volume]?.cropRect == CGRect(x: 5, y: 6, width: 7, height: 8))
        #expect(meta.fields[.unitPrice]?.cropRect == CGRect(x: 9, y: 10, width: 11, height: 12))
        // date/currency/fuelKind have no crop today - absent, never fabricated.
        #expect(meta.fields[.date]?.cropRect == nil)
        #expect(meta.fields[.currency]?.cropRect == nil)
        #expect(meta.fields[.fuelKind]?.cropRect == nil)
        #expect(meta.pipeline == ScannedSavePlanner.onDevicePipeline)
    }

    // MARK: - userCorrected, the accuracy feed

    @Test("userCorrected is true for a field the user edited, false for one left as proposed")
    func userCorrectedTracksTheUsersEdits() {
        // The scan proposed 42.30 L x 1.679 = 71.02. The user changed the litres
        // to 42.00 (the total was re-typed to keep the check from blocking) and
        // left the unit price untouched.
        let edited = ScannedSaveValues(total: decimal("70.52"), volumeL: 42.00,
                                       unitPrice: decimal("1.679"))
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679"), total: decimal("71.02")),
                           saved: edited)
        #expect(scanned.extraction?.fields[.volume]?.userCorrected == true)
        #expect(scanned.extraction?.fields[.total]?.userCorrected == true)
        #expect(scanned.extraction?.fields[.unitPrice]?.userCorrected == false,
                "a field left exactly as the scan proposed is never flagged corrected")
    }

    @Test("an untouched scan flags nothing as corrected")
    func untouchedScanFlagsNothing() {
        let proposedDate = ConfirmDate.parse("17.08.2026")!
        let untouched = ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                          unitPrice: decimal("1.679"), currency: .eur,
                                          fuelKind: .petrol95, date: proposedDate)
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679"), total: decimal("71.02"),
                                      currency: .eur, fuelKind: .petrol95, date: "17.08.2026"),
                           saved: untouched)
        guard let meta = scanned.extraction else {
            Issue.record("expected an extraction record")
            return
        }
        for (ref, field) in meta.fields {
            #expect(field.userCorrected == false,
                    "\(ref) must not be flagged corrected on an untouched scan")
        }
    }

    @Test("a derived price that does not divide evenly is not flagged when displayed rounded")
    func derivedPriceAtDisplayPrecisionIsNotFlagged() {
        // The scan proposed liters 42.30 + price 1.679, the total derives. The
        // stored price is the full-precision quotient (71.0217 / 42.30), which
        // rounds to the printed 1.679 - the user never touched it, so it must
        // not read as corrected.
        let saved = ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                      unitPrice: decimal("1.6789598"))
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679")),
                           saved: saved)
        #expect(scanned.extraction?.fields[.unitPrice]?.userCorrected == false)
        #expect(scanned.extraction?.fields[.volume]?.userCorrected == false)
        #expect(scanned.extraction?.fields[.total] == nil,
                "a total that derives (never proposed) is not an extraction field")
    }

    @Test("a QR-corrected total left untouched is not flagged corrected")
    func qrCorrectedTotalLeftUntouchedIsNotFlagged() {
        // OCR grabbed the VAT line (706.00); the QR total 4334.83 is exact and
        // fills the field. The user saves it unchanged - the comparison must be
        // against what the user SAW (the QR total), never the raw OCR total.
        let scanned = plan(extraction(total: decimal("706.00")),
                           qrAnchor: qr("4334.83"),
                           saved: ScannedSaveValues(total: decimal("4334.83")))
        #expect(scanned.extraction?.fields[.total]?.userCorrected == false)
        // And a user who DOES overtype the QR total is flagged.
        let corrected = plan(extraction(total: decimal("706.00")),
                             qrAnchor: qr("4334.83"),
                             saved: ScannedSaveValues(total: decimal("4334.00")))
        #expect(corrected.extraction?.fields[.total]?.userCorrected == true)
    }

    // MARK: - Attachment presence

    @Test("a prefill with no photo attaches nothing but keeps scan provenance")
    func prefillWithoutPhotoAttachesNothing() {
        // The `-seedConfirmPrefill*` states: a prefill applied, no photo. The
        // scan provenance and extraction record still stand - only the bytes
        // are absent.
        let scanned = plan(extraction(liters: 42.30, unitPrice: decimal("1.679")),
                           hasPhoto: false,
                           saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                                    unitPrice: decimal("1.679")))
        #expect(scanned.attachmentID == nil)
        #expect(scanned.sharedAttachmentIDs.isEmpty)
        #expect(scanned.provenance == .receiptScan)
        #expect(scanned.extraction != nil)
    }
}

// MARK: - Persistence: the save writes one row shared by the fill and expenses

@Suite("Scanned save: one Attachment referenced by the FillUp and every accepted Expense")
struct ScannedSavePersistenceTests {

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    @Test("the fill-up and each accepted expense reference the SAME attachment id, and only one row exists")
    func sharedIdAcrossFillAndExpenses() throws {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Volvo V60", make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
        try repository.upsertVehicle(vehicle)

        // The scanned save's plan: one attachment id for the whole group.
        let scanned = ScannedSavePlanner.plan(
            extraction: FuelExtraction(liters: 42.30, unitPrice: decimal("1.679"),
                                       total: decimal("71.02"), currency: .eur,
                                        fuelKind: .petrol95, date: "17.08.2026"),
            cropRects: [:],
            hasPhoto: true,
            saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                     unitPrice: decimal("1.679"), currency: .eur,
                                     fuelKind: .petrol95, date: Date()))
        guard let attachmentID = scanned.attachmentID else {
            Issue.record("a scanned save must plan an attachment")
            return
        }

        // The app's save writes the receipt ONCE and references the same id
        // from the fill-up and from each accepted expense.
        let now = Date()
        let attachment = Attachment(
            id: attachmentID, createdAt: now, updatedAt: now, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: "abc", relativePath: "\(attachmentID.uuidString).jpg"),
            extractedTimestamp: now, ocrText: "SHELL 71.02 42.30 1.679")
        try repository.upsertAttachment(attachment)

        let fill = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: scanned.sharedAttachmentIDs, provenance: scanned.provenance,
            conflict: .none, purchaseGroupId: UUID.v7(),
            volumeL: 42.30, unitPrice: decimal("1.679"), fuelKind: .petrol95,
            fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: scanned.extraction)
        try repository.upsertFillUp(fill)

        for (index, category) in [ExpenseCategory.parking, ExpenseCategory.other("wash")].enumerated() {
            let expense = Expense(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                vehicleId: vehicle.id, date: now, odometer: nil,
                money: Money(amount: decimal("8.00"), currency: .eur, homeCurrency: .eur),
                note: nil, attachments: scanned.sharedAttachmentIDs, provenance: scanned.provenance,
                conflict: .none, purchaseGroupId: fill.purchaseGroupId,
                category: category, title: "Car wash \(index)")
            try repository.upsertExpense(expense)
        }

        // Exactly ONE attachment row exists - a copy per row would be two.
        let savedAttachments = try repository.liveAttachments()
        #expect(savedAttachments.count == 1)
        #expect(savedAttachments.first?.id == attachmentID)

        // The fill and BOTH expenses reference the SAME id, not merely "each has one".
        let savedFill = try #require(try repository.liveFillUps(forVehicle: vehicle.id).first)
        let savedExpenses = try repository.liveExpenses(forVehicle: vehicle.id)
        #expect(savedExpenses.count == 2)
        #expect(savedFill.attachments == [attachmentID])
        #expect(savedExpenses.allSatisfy { $0.attachments == [attachmentID] })
        #expect(savedFill.provenance == .receiptScan)
        #expect(savedFill.provenance != .manual)
        #expect(savedExpenses.allSatisfy { $0.provenance == .receiptScan })
        #expect(savedFill.extraction?.fields[.volume] != nil)
    }

    @Test("the typed path writes no attachment row and stays manual")
    func typedPathWritesNoAttachment() throws {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Volvo V60", make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
        try repository.upsertVehicle(vehicle)

        let typed = ScannedSavePlanner.plan(extraction: nil, hasPhoto: true,
                                            saved: ScannedSaveValues())
        let now = Date()
        let fill = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil,
            money: Money(amount: decimal("70.15"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: typed.sharedAttachmentIDs, provenance: typed.provenance,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 42.1, unitPrice: decimal("1.666"), fuelKind: .petrol95,
            fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: typed.extraction)
        try repository.upsertFillUp(fill)

        #expect(try repository.liveAttachments().isEmpty,
                "the typed path must not leave an orphan attachment")
        let saved = try #require(try repository.liveFillUps(forVehicle: vehicle.id).first)
        #expect(saved.attachments.isEmpty)
        #expect(saved.provenance == .manual)
        #expect(saved.extraction == nil)
    }
}

// MARK: - PJ.2b the Expense rows the plan emits (one shared id, L1-reachable)

@Suite("Scanned save: the plan emits Expense rows sharing the ONE attachment id")
struct ScannedSaveExpenseRowsTests {

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    /// A mixed-receipt group plan through the production path: the detector and
    /// the group planner, never a hand-built `ReceiptGroupPlan`.
    private func groupPlan() -> ReceiptGroupPlan? {
        let detection = MixedReceiptDetection.mixed(
            lines: [
                ReceiptLineItem(title: "Мойка кузова", amount: decimal("8.00"),
                                category: .parking, isCarRelated: true),
                ReceiptLineItem(title: "Кофе американо", amount: decimal("4.80"),
                                category: .other("coffee"), isCarRelated: false)
            ],
            fuelLine: decimal("71.02"), grandTotal: decimal("83.82"))
        return ReceiptGroupPlanner.plan(detection: detection,
                                        fillUpAmount: decimal("71.02"),
                                        acceptedLineIDs: Set(detection.lines.map(\.id)))
    }

    @Test("the fill-up and every expense reference the SAME attachment id, not merely one each")
    func everyExpenseSharesTheFillUpsId() {
        let scanned = ScannedSavePlanner.plan(
            extraction: FuelExtraction(liters: 42.30, unitPrice: decimal("1.679"),
                                       total: decimal("71.02"), currency: .eur, fuelKind: .petrol95),
            hasPhoto: true,
            saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                     unitPrice: decimal("1.679"), currency: .eur,
                                     fuelKind: .petrol95))
        guard let attachmentID = scanned.attachmentID else {
            Issue.record("a scanned save must plan an attachment")
            return
        }
        guard let group = groupPlan() else {
            Issue.record("a mixed-receipt group plan must build")
            return
        }

        // The production path: the plan builds the rows, the test does not
        // arrange them itself (that would assert its own setup, not the code).
        let rows = scanned.expenses(from: group, vehicleId: UUID.v7(),
                                    date: Date(), createdAt: Date()) { amount in
            Money(amount: amount, currency: .eur, homeCurrency: .eur)
        }

        #expect(rows.count == 2, "every accepted line becomes an expense")
        // THE assertion that matters: each row references the SAME id the fill
        // references. A per-row mint (each expense its own fresh id) makes every
        // `attachments` list differ from `sharedAttachmentIDs` and fails here.
        #expect(rows.allSatisfy { $0.attachments == scanned.sharedAttachmentIDs },
                "every expense must reference the plan's ONE shared id")
        #expect(scanned.sharedAttachmentIDs == [attachmentID])
        #expect(rows.allSatisfy { $0.attachments == [attachmentID] })
        // The rest of the shared shape: provenance and group id come from the plan too.
        #expect(rows.allSatisfy { $0.provenance == scanned.provenance })
        #expect(rows.allSatisfy { $0.purchaseGroupId == group.purchaseGroupId })
    }
}
