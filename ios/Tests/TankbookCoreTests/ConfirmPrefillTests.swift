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

    private func extraction(liters: Double? = nil, unitPrice: Double? = nil,
                            total: Double? = nil) -> FuelExtraction {
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
        // The boundary conversion: Double -> formatted string -> Decimal(string:).
        // 4201.68 must survive as the exact decimal, never a binary approximation.
        let converted = ConfirmFormat.decimal(fromExtraction: 4201.68, fractionDigits: 2)
        #expect(converted == decimal("4201.68"))
    }

    @Test func nilExtractionFieldStaysBlank() {
        #expect(ConfirmFormat.decimal(fromExtraction: nil, fractionDigits: 2) == nil)
        #expect(ConfirmFormat.string(fromExtraction: nil, fractionDigits: 2) == "")
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

    // MARK: - QR-anchor total resolution

    private func qrAnchor(_ total: String) -> FiscalQRAnchor {
        FiscalQRAnchor(total: decimal(total), date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func qrAgreesKeepsTheOcrTotal() {
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(total: 71.02),
                                              qrAnchor: qrAnchor("71.02"))
        #expect(resolved == .ocrConfirmed(decimal("71.02")))
    }

    @Test func qrDisagreesFillsTheFieldWithTheQrTotal() {
        // The corpus case: OCR grabbed the VAT line (706.00 on a 4334.83
        // receipt); the QR total is exact and wins.
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(total: 706.00),
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
                                                                      unitPrice: 2.0,
                                                                      total: 40.00),
                                              qrAnchor: qrAnchor("50.00"))
        #expect(resolved == .fuelLineStands(decimal("40.00")))
    }

    @Test func mixedReceiptWithoutOperandsKeepsTheOcrTotal() {
        // No liters/price to compute a fuel line: the only evidence is the OCR
        // total, which stays (the check line then shows honestly whether the
        // triple verifies).
        let resolved = ConfirmQRTotal.resolve(extraction: extraction(total: 40.00),
                                              qrAnchor: qrAnchor("50.00"))
        #expect(resolved == .fuelLineStands(decimal("40.00")))
    }

    @Test func noAnchorLeavesTheOcrTotalAndBlankMeansBlank() {
        #expect(ConfirmQRTotal.resolve(extraction: extraction(total: 71.02),
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
}
