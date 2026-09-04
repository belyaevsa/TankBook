import CoreGraphics
import Foundation

// MARK: - PJ.2 the scanned-save plan
//
// What a scanned save writes, as a pure value: whether the receipt photo is
// attached (and to which id), the provenance that names how it arrived, and the
// extraction record - per resolved field, its crop rect, confidence and whether
// the user changed the proposed value. Lives in core because the "a scanned
// save keeps the photo" guarantee must be L1-testable from values with no UIKit
// (there is no app unit-test target, and a guarantee pinned only at L4 is
// "verified by looking at one device" - the P3.7 lesson). The file bytes stay
// app-side (`VehiclePhotoStore`/`InvoiceAttachmentFiles`); this decides the
// shape and the shared id.

/// The values a save will actually record, compared against the extraction's
/// proposal to decide `userCorrected` per field. All in the units the entry is
/// stored in: volume always litres, money in the entry's original currency.
public struct ScannedSaveValues: Sendable, Equatable {
    public var total: Decimal?
    public var volumeL: Double?
    public var unitPrice: Decimal?
    public var currency: CurrencyCode?
    public var fuelKind: FuelKind?
    public var date: Date?

    public init(total: Decimal? = nil, volumeL: Double? = nil,
                unitPrice: Decimal? = nil, currency: CurrencyCode? = nil,
                fuelKind: FuelKind? = nil, date: Date? = nil) {
        self.total = total
        self.volumeL = volumeL
        self.unitPrice = unitPrice
        self.currency = currency
        self.fuelKind = fuelKind
        self.date = date
    }
}

/// The shape of one save (PJ.2). A scanned save writes the receipt photo ONCE
/// and references the SAME id from the `FillUp` and from every accepted
/// mixed-receipt `Expense` - one photograph of one receipt, never a copy per
/// row. The typed path (no prefill) writes nothing and stays `.manual`
/// (hard rule 15: typing is a peer path, not a lesser one).
public struct ScannedSavePlan: Sendable, Equatable {
    /// The attachment id the whole save shares, or nil when the save attaches
    /// no photo (the typed path, or a prefill that carried no photo).
    public let attachmentID: AttachmentID?
    /// How the entry arrived: `.receiptScan` / `.pumpPhoto` / `.fiscalQR` /
    /// `.screenshot` - never `.manual` when a prefill was applied.
    public let provenance: Provenance
    /// The per-field extraction record, when a prefill was applied.
    public let extraction: ExtractionMeta?

    public init(attachmentID: AttachmentID?, provenance: Provenance,
                extraction: ExtractionMeta?) {
        self.attachmentID = attachmentID
        self.provenance = provenance
        self.extraction = extraction
    }

    /// One receipt written once: the same reference for the fill-up and every
    /// accepted expense of the grouped save. Never minted per row - a separate
    /// id per expense would break the shared-photo promise (J3 mixed variant:
    /// the fuel row and its accepted expenses share ONE receipt image). Empty
    /// on the typed path.
    public var sharedAttachmentIDs: [AttachmentID] {
        attachmentID.map { [$0] } ?? []
    }
}

/// The pure decision for a save that may have arrived through the scan door.
public enum ScannedSavePlanner {
    /// The pipeline id recorded in `ExtractionMeta` for the on-device
    /// vision+rules pipeline (the canonical label, docs/LOGGING.md).
    public static let onDevicePipeline = "vision+rules v3"
    /// The schema-required per-field confidence slot. The on-device pipeline
    /// does not propagate Vision's per-line confidence to the assembler today,
    /// so this documented default fills the slot; a caller that has a real
    /// score passes it via the `confidence` parameter. Never a claim of
    /// certainty - the UI dims on `ConfirmConfidenceGate`, not on this number.
    public static let onDeviceConfidenceDefault: Double = 0.9

    /// Plans a save.
    ///
    /// - Parameters:
    ///   - extraction: the prefill's extraction. `nil` IS the typed path:
    ///     no attachment, `.manual`, no extraction record.
    ///   - cropRects: the per-field source-image crop rects the prefill carried
    ///     (image pixel space), keyed by `FieldRef`.
    ///   - qrAnchor: a decoded fiscal QR, when present. Outranks the declared
    ///     provenance (`.fiscalQR`) and supplies the total proposal.
    ///   - declaredProvenance: how the prefill declares the capture arrived
    ///     (`.receiptScan` unless the pump seed says otherwise).
    ///   - hasPhoto: whether the prefill carried a photo to attach.
    ///   - confidence: per-field confidence overrides; falls back to
    ///     `onDeviceConfidenceDefault`.
    ///   - saved: the values the save will record, for the `userCorrected`
    ///     comparison.
    ///   - pipeline: the `ExtractionMeta.pipeline` label.
    ///   - attachmentID: the id to mint for the shared attachment.
    public static func plan(
        extraction: FuelExtraction?,
        cropRects: [FieldRef: CGRect] = [:],
        qrAnchor: FiscalQRAnchor? = nil,
        declaredProvenance: Provenance = .receiptScan,
        hasPhoto: Bool,
        confidence: [FieldRef: Double] = [:],
        saved: ScannedSaveValues,
        pipeline: String = onDevicePipeline,
        attachmentID: AttachmentID = UUID.v7()
    ) -> ScannedSavePlan {
        guard let extraction else {
            // The typed path: no prefill, so nothing to attach, nothing the scan
            // proposed, and manual provenance (hard rule 15).
            return ScannedSavePlan(attachmentID: nil, provenance: .manual, extraction: nil)
        }
        let provenance = Self.provenance(qrAnchor: qrAnchor, declared: declaredProvenance)
        let meta = extractionMeta(extraction: extraction, cropRects: cropRects,
                                  qrAnchor: qrAnchor, confidence: confidence,
                                  saved: saved, pipeline: pipeline)
        return ScannedSavePlan(attachmentID: hasPhoto ? attachmentID : nil,
                               provenance: provenance, extraction: meta)
    }

    /// The provenance the save records: a decoded fiscal QR outranks everything
    /// (the receipt arrived as a QR), otherwise the capture declares it
    /// `.receiptScan` / `.pumpPhoto` / `.screenshot`.
    static func provenance(qrAnchor: FiscalQRAnchor?,
                           declared: Provenance) -> Provenance {
        if qrAnchor != nil { return .fiscalQR }
        return declared
    }

    /// The value-only assignment for an `Attachment` written OUTSIDE a save
    /// (PJ.48 attach, RV.37 replace): the fields the parse read with their
    /// values and confidence, but no `userCorrected` - that comparison needs the
    /// saved values and lives on the save path. nil when the parse assigned
    /// nothing, so the attachment stores no empty container (RV.48).
    public static func assignment(from extraction: FuelExtraction,
                                  pipeline: String = onDevicePipeline,
                                  confidence: Double = onDeviceConfidenceDefault) -> ExtractionMeta? {
        var fields: [FieldRef: FieldExtraction] = [:]
        if let total = extraction.total {
            fields[.total] = FieldExtraction(cropRect: nil, confidence: confidence,
                                             userCorrected: false, value: .money(total))
        }
        if let liters = extraction.liters {
            fields[.volume] = FieldExtraction(cropRect: nil, confidence: confidence,
                                              userCorrected: false, value: .number(liters))
        }
        if let price = extraction.unitPrice {
            fields[.unitPrice] = FieldExtraction(cropRect: nil, confidence: confidence,
                                                 userCorrected: false, value: .money(price))
        }
        if let date = extraction.date {
            fields[.date] = FieldExtraction(cropRect: nil, confidence: confidence,
                                            userCorrected: false, value: .text(date))
        }
        if let currency = extraction.currency {
            fields[.currency] = FieldExtraction(cropRect: nil, confidence: confidence,
                                                userCorrected: false, value: .currency(currency))
        }
        if let kind = extraction.fuelKind {
            fields[.fuelKind] = FieldExtraction(cropRect: nil, confidence: confidence,
                                                userCorrected: false, value: .fuelKind(kind))
        }
        guard !fields.isEmpty else { return nil }
        return ExtractionMeta(fields: fields, pipeline: pipeline)
    }

    // MARK: - The extraction record

    private static func extractionMeta(extraction: FuelExtraction,
                                       cropRects: [FieldRef: CGRect],
                                       qrAnchor: FiscalQRAnchor?,
                                       confidence: [FieldRef: Double],
                                       saved: ScannedSaveValues,
                                       pipeline: String) -> ExtractionMeta {
        var fields: [FieldRef: FieldExtraction] = [:]

        let proposalTotal = resolvedTotal(extraction: extraction, qrAnchor: qrAnchor)
        if let proposalTotal {
            fields[.total] = FieldExtraction(
                cropRect: cropRects[.total],
                confidence: confidence[.total] ?? onDeviceConfidenceDefault,
                userCorrected: saved.total.map { !sameMoney($0, proposalTotal) } ?? true,
                value: .money(proposalTotal))
        }
        if let liters = extraction.liters {
            fields[.volume] = FieldExtraction(
                cropRect: cropRects[.volume],
                confidence: confidence[.volume] ?? onDeviceConfidenceDefault,
                userCorrected: saved.volumeL.map { !sameVolume($0, liters) } ?? true,
                value: .number(liters))
        }
        if let price = extraction.unitPrice {
            fields[.unitPrice] = FieldExtraction(
                cropRect: cropRects[.unitPrice],
                confidence: confidence[.unitPrice] ?? onDeviceConfidenceDefault,
                userCorrected: saved.unitPrice.map { !sameMoney($0, price) } ?? true,
                value: .money(price))
        }
        if let raw = extraction.date, let date = ConfirmDate.parse(raw) {
            fields[.date] = FieldExtraction(
                cropRect: nil,
                confidence: confidence[.date] ?? onDeviceConfidenceDefault,
                userCorrected: saved.date != date,
                value: .text(raw))
        }
        if let currency = extraction.currency {
            fields[.currency] = FieldExtraction(
                cropRect: nil,
                confidence: confidence[.currency] ?? onDeviceConfidenceDefault,
                userCorrected: saved.currency != currency,
                value: .currency(currency))
        }
        if let kind = extraction.fuelKind {
            fields[.fuelKind] = FieldExtraction(
                cropRect: nil,
                confidence: confidence[.fuelKind] ?? onDeviceConfidenceDefault,
                userCorrected: saved.fuelKind != kind,
                value: .fuelKind(kind))
        }
        return ExtractionMeta(fields: fields, pipeline: pipeline)
    }

    /// The total the form actually proposed: the OCR total as the QR resolves
    /// it (`.noAnchor` keeps the OCR total, a QR that disagrees wins, a mixed
    /// receipt keeps the fuel line - `ConfirmQRTotal` owns the rule). The
    /// comparison is against what the user SAW, never the raw OCR total: a
    /// user leaving a QR-corrected total alone has not corrected anything.
    static func resolvedTotal(extraction: FuelExtraction,
                              qrAnchor: FiscalQRAnchor?) -> Decimal? {
        switch ConfirmQRTotal.resolve(extraction: extraction, qrAnchor: qrAnchor) {
        case .noAnchor(let ocrTotal): return ocrTotal
        case .ocrConfirmed(let total), .qrAuthoritative(let total), .fuelLineStands(let total):
            return total
        }
    }

    /// Two money values are the same when they agree at the receipt's own
    /// display precision (2 decimals). The form derives and stores at full
    /// precision (a derived price divides unevenly), so an untouched pre-filled
    /// price must not read as user-corrected just because 71.02 / 42.30 has
    /// more digits than the receipt printed.
    private static func sameMoney(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        var left = lhs, right = rhs
        var result = Decimal()
        var operation = Decimal()
        NSDecimalRound(&result, &left, 2, .plain)
        operation = result
        NSDecimalRound(&result, &right, 2, .plain)
        return operation == result
    }

    /// Volume agrees at the form's display precision (2 decimals). Mirrors
    /// `sameMoney` for the `Double` volume, whose formatted-string round trip
    /// through the form is the boundary the proposal was actually shown at.
    private static func sameVolume(_ lhs: Double, _ rhs: Double) -> Bool {
        let left = (lhs * 100).rounded() / 100
        let right = (rhs * 100).rounded() / 100
        return left == right
    }
}

// MARK: - The Expense rows the grouped save writes (PJ.2b)

extension ScannedSavePlan {
    /// Builds the `Expense` rows a grouped save writes, one per accepted
    /// mixed-receipt line, each referencing THIS plan's single shared attachment
    /// id and provenance. This is the construction that used to live in the
    /// Confirm sheet's save loop (`ios/App`), where no unit-test target could
    /// reach it - so the PJ.2 guarantee ("one photograph of one receipt, never a
    /// copy per row") was asserted nowhere and a per-row id mutation passed both
    /// L1 and L4. Moved into core (the P3.7 lesson): the app writes what the
    /// plan decided, it does not decide the shared id itself.
    ///
    /// The fill-up's own attachment list is `sharedAttachmentIDs`; every expense
    /// produced here carries that SAME list, so the receipt photo is written
    /// once and referenced by the fill-up and by every accepted expense alike.
    ///
    /// - Parameters:
    ///   - group: the grouped-save plan (`ReceiptGroupPlanner.plan`); its
    ///     `purchaseGroupId` and accepted `expenses` are what the rows inherit.
    ///   - vehicleId: the selected car, shared by the whole group.
    ///   - date: the entry date, shared by the whole group.
    ///   - createdAt: the write timestamp (both `createdAt` and `updatedAt`).
    ///   - money: turns a line's receipt amount into the `Money` pair the row
    ///     stores. The app supplies this because conversion is a form concern
    ///     (manual rate, feed snapshot, low-confidence), never a plan concern.
    public func expenses(from group: ReceiptGroupPlan,
                         vehicleId: UUID,
                         date: Date,
                         createdAt: Date,
                         money: (Decimal) -> Money) -> [Expense] {
        let attachments = sharedAttachmentIDs
        return group.expenses.map { receipt in
            Expense(
                id: receipt.id, createdAt: createdAt, updatedAt: createdAt, deletedAt: nil,
                vehicleId: vehicleId, date: date, odometer: nil,
                money: money(receipt.amount),
                note: nil, attachments: attachments, provenance: provenance,
                conflict: .none, purchaseGroupId: group.purchaseGroupId,
                category: receipt.category, title: receipt.title)
        }
    }
}
