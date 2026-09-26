#if DEBUG
import Foundation
import TankbookCore

// MARK: - RV.57 the canned local parse for the fill-up capture path

/// The real fill-up capture path runs `CapturePipeline` (Vision OCR); these
/// arguments substitute a fixed `FuelExtraction` so a UI test can assert what
/// the user SEES without depending on OCR over a corpus image - the same seam
/// `ExpenseScanTestSeed` gives the Expense path and `ConfirmPrefillSeed` gives
/// the `-presentScreen confirmManual` path. The seam substitutes ONLY the
/// pipeline's output; the session hand-off and the form's apply path are the
/// exact shipped ones.
///
/// - `-seedFillUpScan` - the resolved state (42.30 L x 1.679 = 71.02 EUR,
///   17.08.2026), so the L4 test asserts the pre-filled field values.
/// - `-seedFillUpScanSparse` - only liters resolved: the late-answer test's
///   boundary, where the OLD behaviour filled the blank total/price and the
///   new behaviour (RV.57) leaves them untouched.
/// - `-seedFillUpScanPumpNothingRead` - a pump display none of whose numbers
///   was read: the verify screen's admission.
/// - `-seedFillUpScanPumpCaution` - a pump pair whose shown price differs from
///   the one it implies, read in alpha: both notices on the verify screen.
enum FillUpScanTestSeed {
    static func extraction(from arguments: [String]) -> FuelExtraction? {
        if arguments.contains("-seedFillUpScan") {
            return FuelExtraction(liters: 42.30, unitPrice: 1.679, total: 71.02,
                                  currency: .eur, fuelKind: .petrol95,
                                  date: "17.08.2026")
        }
        if arguments.contains("-seedFillUpScanSparse") {
            return FuelExtraction(liters: 42.30, currency: .eur)
        }
        if arguments.contains("-seedFillUpScanPumpNothingRead") {
            return FuelExtraction(currency: .eur)
        }
        if arguments.contains("-seedFillUpScanPumpCaution") {
            return FuelExtraction(liters: 11.88, total: Decimal(string: "20.02"), currency: .eur)
        }
        return nil
    }

    /// The pump seeds' provenance and notices, as the pipeline sets them.
    static func decorate(_ prefill: inout ConfirmPrefill, arguments: [String]) {
        if arguments.contains("-seedFillUpScanPumpNothingRead") {
            prefill.provenance = .pumpPhoto
            prefill.pumpAlpha = true
        }
        if arguments.contains("-seedFillUpScanPumpCaution") {
            prefill.provenance = .pumpPhoto
            prefill.pumpAlpha = true
            prefill.pumpCaution = .shownPriceDiffers(shown: Decimal(string: "1.759")!,
                                                     implied: Decimal(string: "1.685")!)
        }
    }
}
#endif
