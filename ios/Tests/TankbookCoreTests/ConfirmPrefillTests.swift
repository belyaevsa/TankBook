import Testing
import Foundation
@testable import TankbookCore

/// P2.3 confirm-prefill support. The screen's honesty rules in pure form:
/// the dimming gate (resolved-but-unconfirmed = 60%, and dimmed NEVER means
/// disabled), the Decimal boundary (a Double enters the form state only
/// through a formatted string, so 4201.68 stays exact), the QR-anchor total
/// resolution (.disagrees fills the QR total, a mixed receipt keeps the fuel
/// line), the extraction-date parse, and the reduce-motion lock decision.
@Suite struct ConfirmPrefillTests {

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    private func extraction(liters: Double? = nil, unitPrice: Decimal? = nil,
                            total: Decimal? = nil) -> FuelExtraction {
        FuelExtraction(liters: liters, unitPrice: unitPrice, total: total)
    }

    private func crossChecked(volumeL: Double, unitPrice: String, amount: String) -> CrossCheckState {
        TimelineValidator.crossCheck(volumeL: volumeL,
                                     unitPrice: decimal(unitPrice),
                                     amount: decimal(amount))
    }

    // MARK: - The dimming gate

    @Test func resolvedUnconfirmedFieldIsDimmedOnlyWhenCheckIsNotApplicable() {
        // Resolved by the extraction, not yet confirmed, no redundancy to
        // corroborate the triple: dimmed.
        #expect(ConfirmConfidenceGate.confidence(resolved: true,
                                                 crossCheck: .notApplicable,
                                                 userConfirmed: false) == .unconfirmed)
        // The same field once the user has tapped or edited it: confirmed.
        #expect(ConfirmConfidenceGate.confidence(resolved: true,
                                                 crossCheck: .notApplicable,
                                                 userConfirmed: true) == .confirmed)
    }

    @Test func verifiedTripleIsNeverDimmed() {
        #expect(ConfirmConfidenceGate.confidence(resolved: true,
                                                 crossCheck: .verified,
                                                 userConfirmed: false) == .confirmed)
    }

    @Test func mismatchIsNeverDimmedTheAmberUnderlineSpeaksInstead() {
        // A mismatch surfaces the suspect field in amber; dimming it too would
        // double-signal and hide the row that needs the user's eye.
        #expect(ConfirmConfidenceGate.confidence(resolved: true,
                                                 crossCheck: .mismatch(field: .total),
                                                 userConfirmed: false) == .confirmed)
    }

    @Test func unresolvedFieldIsConfirmedNotDimmed() {
        // A nil extraction field is an honest absence: blank, never dimmed,
        // never `0` (hard rule 15 - a partly empty scan is an ordinary form).
        #expect(ConfirmConfidenceGate.confidence(resolved: false,
                                                 crossCheck: .notApplicable,
                                                 userConfirmed: false) == .confirmed)
    }

    // MARK: - The threshold: CHECK 3 tolerance, at and either side

    @Test func crossCheckToleranceIsMaxOfTwoCentFloorAndHalfPercent() {
        // The 0.02 floor dominates a small amount.
        #expect(ConfirmConfidenceGate.crossCheckTolerance(amount: decimal("1.00")) == decimal("0.02"))
        // The 0.5% term dominates a large amount: 200.00 x 0.005 = 1.00 > 0.02.
        #expect(ConfirmConfidenceGate.crossCheckTolerance(amount: decimal("200.00")) == decimal("1.00"))
    }

    @Test func dimmingBoundaryAtToleranceIsConfirmed() {
        // Exactly at the boundary: 0.5 x 2.00 = 1.00, total 1.02, diff 0.02 ==
        // tolerance. Verified -> the fields are confirmed, nothing dimmed.
        let state = crossChecked(volumeL: 0.5, unitPrice: "2.00", amount: "1.02")
        #expect(state == .verified)
        #expect(ConfirmConfidenceGate.confidence(resolved: true, crossCheck: state,
                                                 userConfirmed: false) == .confirmed)
    }

    @Test func dimmingBoundaryJustOutsideToleranceIsSuspect() {
        // One cent outside: total 1.03, diff 0.03 > 0.02. Mismatch on .total,
        // never dimmed (the amber underline carries the signal).
        let state = crossChecked(volumeL: 0.5, unitPrice: "2.00", amount: "1.03")
        #expect(state == .mismatch(field: .total))
        #expect(ConfirmConfidenceGate.confidence(resolved: true, crossCheck: state,
                                                 userConfirmed: false) == .confirmed)
    }

    @Test func dimmingBoundaryAtHalfPercentTermIsConfirmed() {
        // 100 x 2.00 = 200.00, total 201.001: diff 1.001 == tolerance 1.001.
        let state = crossChecked(volumeL: 100, unitPrice: "2.00", amount: "201.001")
        #expect(state == .verified)
        #expect(ConfirmConfidenceGate.confidence(resolved: true, crossCheck: state,
                                                 userConfirmed: false) == .confirmed)
    }

    @Test func dimmedOpacityIsSixtyPercent() {
        #expect(ConfirmConfidenceGate.dimmedOpacity == 0.6)
    }

    // MARK: - The lock never gates saving (the swapped-pair trap)

    @Test func swappedPairStillReportsVerifiedButOnlyConsistencyIsProven() {
        // The corpus has two fixtures where the parser swapped liters and unit
        // price; a x b == b x a, so the cross-check passes. The lock must
        // never be treated as evidence the fields are correctly ASSIGNED, and
        // must never gate saving - the save gate is "two of three typed",
        // independent of the lock (asserted by never touching canSave here;
        // the UI test asserts the lock does not block save).
        let asTyped = crossChecked(volumeL: 42.30, unitPrice: "1.679", amount: "71.02")
        let swapped = crossChecked(volumeL: 1.679, unitPrice: "42.30", amount: "71.02")
        #expect(asTyped == .verified)
        #expect(swapped == .verified)
        #expect(swapped == asTyped)
        // And the lock still leaves both fields as editable default inputs.
        #expect(ConfirmConfidenceGate.confidence(resolved: true, crossCheck: swapped,
                                                 userConfirmed: false) == .confirmed)
    }

    // MARK: - The Decimal boundary (money precision)

    @Test func doubleEntersTheFormAsAnExactDecimal() {
        // The volume boundary: Double -> formatted string -> Decimal(string:).
        // 4201.68 must survive as the exact decimal, never a binary approximation.
        let converted = ConfirmFormat.decimal(fromExtraction: 4201.68, fractionDigits: 2)
        #expect(converted == decimal("4201.68"))
    }

    @Test func nilExtractionFieldStaysBlank() {
        #expect(ConfirmFormat.decimal(fromExtraction: nil, fractionDigits: 2) == nil)
        #expect(ConfirmFormat.string(fromExtraction: Double?.none, fractionDigits: 2) == "")
        #expect(ConfirmFormat.string(fromExtraction: Decimal?.none, fractionDigits: 2) == "")
    }

    @Test func stringBoundaryRoundTripsThroughDecimalString() {
        // The exact path the form uses: pre-fill puts a string in the field,
        // the form parses it back with Decimal(string:). No Decimal(double:)
        // anywhere in the round trip.
        let prefill = ConfirmFormat.string(fromExtraction: 4201.68, fractionDigits: 2)
        #expect(prefill == "4201.68")
        #expect(Decimal(string: prefill, locale: Locale(identifier: "en_US_POSIX")) == decimal("4201.68"))
    }

    @Test func pricePerLitreUsesThreeFractionDigits() {
        #expect(ConfirmFormat.fractionDigits(for: .unitPrice) == 3)
        #expect(ConfirmFormat.string(fromExtraction: 1.679, fractionDigits: 3) == "1.679")
    }

    // MARK: - P2.2b: extraction money is born Decimal, exactly

    @Test func extractionMoneyFormatsDirectlyWithoutADoubleRoundTrip() {
        // The extraction's money fields are Decimal, so formatting them must
        // not route through Double (which would corrupt e.g. 71.02). The
        // Decimal overload formats the exact value.
        #expect(ConfirmFormat.string(fromExtraction: decimal("71.02"), fractionDigits: 2) == "71.02")
        #expect(ConfirmFormat.string(fromExtraction: decimal("1.679"), fractionDigits: 3) == "1.679")
    }

    // MARK: - QR-anchor total resolution

    private func qrAnchor(_ total: String) -> FiscalQRAnchor {
        FiscalQRAnchor(total: decimal(total), date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func qrAgreesKeepsTheOcrTotal() {
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(total: decimal("71.02")),
                                              qrAnchor: qrAnchor("71.02"))
        #expect(resolved == .ocrConfirmed(decimal("71.02")))
    }

    @Test func qrDisagreesFillsTheFieldWithTheQrTotal() {
        // The corpus case: OCR grabbed the VAT line (706.00 on a 4334.83
        // receipt); the QR total is exact and wins.
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(total: decimal("706.00")),
                                              qrAnchor: qrAnchor("4334.83"))
        #expect(resolved == .qrAuthoritative(decimal("4334.83")))
    }

    @Test func qrPresentWithoutOcrTotalFillsTheFieldWithTheQrTotal() {
        // No OCR total at all: the QR anchor is the only evidence and fills the
        // field. There is nothing to disagree with.
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(),
                                              qrAnchor: qrAnchor("4334.83"))
        #expect(resolved == .qrAuthoritative(decimal("4334.83")))
    }

    @Test func mixedReceiptKeepsTheFuelLineNotTheGrandTotal() {
        // The bottled-water fixture shape: grand total 50.00, fuel line
        // 20.00 L x 2.00 = 40.00. Hard rule 4: the fill-up amount is the fuel
        // line, never the grand total, so the fuel line stands in exact
        // Decimal - computed from the formatted operands, never Decimal(double:).
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(liters: 20.0,
                                                                      unitPrice: decimal("2.00"),
                                                                      total: decimal("40.00")),
                                              qrAnchor: qrAnchor("50.00"))
        #expect(resolved == .fuelLineStands(decimal("40.00")))
    }

    @Test func mixedReceiptWithoutOperandsKeepsTheOcrTotal() {
        // No liters/price to compute a fuel line: the only evidence is the OCR
        // total, which stays (the check line then shows honestly whether the
        // triple verifies).
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(total: decimal("40.00")),
                                              qrAnchor: qrAnchor("50.00"))
        #expect(resolved == .fuelLineStands(decimal("40.00")))
    }

    @Test func noAnchorLeavesTheOcrTotalAndBlankMeansBlank() {
        #expect(ConfirmQRTotal.resolve(extraction: extraction(total: decimal("71.02")),
                                       qrAnchor: nil) == .noAnchor(ocrTotal: decimal("71.02")))
        #expect(ConfirmQRTotal.resolve(extraction: extraction(),
                                       qrAnchor: nil) == .noAnchor(ocrTotal: nil))
    }

    // MARK: - Extraction date parsing

    @Test func parsesTheDayFirstRegexShapes() {
        for raw in ["17.08.2026", "17/08/2026", "17-08-26"] {
            let date = ConfirmDate.parse(raw, timeZone: TimeZone(identifier: "Europe/Moscow")!)
            #expect(date != nil)
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date!)
            #expect(components.year == 2026)
            #expect(components.month == 8)
            #expect(components.day == 17)
        }
    }

    @Test func parsesTheIsoShape() {
        let date = ConfirmDate.parse("2026-08-17", timeZone: TimeZone(identifier: "UTC")!)
        #expect(date != nil)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 17)
    }

    @Test func garbageDateParsesNilAndTheFormKeepsItsDefault() {
        #expect(ConfirmDate.parse("") == nil)
        #expect(ConfirmDate.parse("not a date") == nil)
    }

    // MARK: - Reduce-motion lock

    @Test func lockAnimatesUnlessReduceMotionIsOn() {
        #expect(ConfirmLockAnimation.shouldAnimate(reduceMotion: false))
        #expect(!ConfirmLockAnimation.shouldAnimate(reduceMotion: true))
    }

    // MARK: - PJ.17 the empty-but-alive caption decision (F1)

    @Test func emptyScanWithPhotoShowsTheCaption() {
        // F1's verdict: a scan that resolved nothing but kept its photo
        // degrades to the ordinary manual form with the quiet caption.
        #expect(ConfirmEmptyScanCaption.shouldShow(extraction: FuelExtraction(),
                                                   qrAnchor: nil,
                                                   hasPhoto: true))
        #expect(ConfirmEmptyScanCaption.shouldShow(extraction: nil,
                                                   qrAnchor: nil,
                                                   hasPhoto: true))
    }

    @Test func emptyScanWithoutPhotoShowsNoCaption() {
        // No photo, nothing was promised - the plain empty form (hard rule 15).
        #expect(!ConfirmEmptyScanCaption.shouldShow(extraction: FuelExtraction(),
                                                    qrAnchor: nil,
                                                    hasPhoto: false))
    }

    @Test func typedPathShowsNoCaption() {
        // The typed path is a peer door, never a degraded one: no prefill, no
        // photo, no caption - a user who typed by choice sees nothing.
        #expect(!ConfirmEmptyScanCaption.shouldShow(extraction: nil,
                                                    qrAnchor: nil,
                                                    hasPhoto: false))
    }

    @Test func aScanThatResolvedSomethingShowsNoCaption() {
        // "Couldn't read this one" would be a lie once even one field resolved -
        // the dimmed fields already say what the scan read.
        #expect(!ConfirmEmptyScanCaption.shouldShow(
            extraction: FuelExtraction(liters: 42.30, currency: .eur, date: "17.08.2026"),
            qrAnchor: nil, hasPhoto: true))
    }

    @Test func aFiscalQrTotalShowsNoCaption() {
        // The QR grand total is EXACT and fills the field - the scan read
        // something, so the form is not empty and needs no caption.
        let qr = FiscalQRAnchor(total: Decimal(string: "71.02")!,
                                date: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!ConfirmEmptyScanCaption.shouldShow(extraction: FuelExtraction(),
                                                    qrAnchor: qr,
                                                    hasPhoto: true))
    }

    // MARK: - PJ.17 the caption is a hint, never amber (hard rule 5)

    /// The caption's foreground must stay `inkSoft` (a hint) in
    /// `EmptyScanCaption.swift` - never `warn`. XCUITest cannot read a colour,
    /// so this pins the palette choice by scanning the source of the caption's
    /// rendering, the same source-guard shape as `PaletteAccentGuardTests`.
    /// The mutation that breaks it is the obvious one: rendering the caption
    /// in amber to "signal" the failed scan - which is exactly what makes it
    /// an error state, and hard rule 5 reserves amber for attention.
    @Test func emptyScanCaptionIsRenderedInInkSoftNeverWarn() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/ConfirmManual/EmptyScanCaption.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.components(separatedBy: "\n")

        // The accessibility identifier that marks the caption's rendering.
        guard let idIndex = lines.firstIndex(where: {
            $0.contains("manualFillUpEmptyScanCaption")
        }) else {
            Issue.record("empty-scan caption identifier not found in EmptyScanCaption.swift")
            return
        }
        // Find the enclosing property declaration: walk back to the nearest
        // `var` start so the scan covers the whole caption body.
        var start = idIndex
        while start > 0 {
            let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("var ") || trimmed.hasPrefix("private var ") {
                break
            }
            start -= 1
        }
        let body = lines[start...idIndex]
        let usesWarn = body.contains { $0.contains("Theme.Palette.warn") }
        let usesInkSoft = body.contains { $0.contains("Theme.Palette.inkSoft") }
        let rendered = lines[start...idIndex].joined(separator: "\n")
        #expect(usesInkSoft,
                "the empty-scan caption must render in Theme.Palette.inkSoft, got: \(rendered)")
        #expect(!usesWarn,
                "the empty-scan caption must NEVER be amber (hard rule 5) - a hint, not an error state: \(rendered)")
    }
}
