import UIKit
import SwiftUI
import TankbookCore

// MARK: - P2.3 the confirm-prefill seam
//
// The Confirm sheet's new optional input: an extraction plus the evidence that
// backs it. A nil extraction IS the manual form (hard rule 15 - a scan that
// resolved nothing renders as the ordinary empty sheet, never as an error),
// crops are optional per-field proof shown on tap, and the QR anchor outranks
// the OCR total. Nothing here produces an extraction - this consumes one.

/// A crop of the source image that one extracted value came from. `image` is a
/// reference to the scanned photo, `rect` the region in the image's coordinate
/// space. The seam is deliberately dumb - `CGRect` + image - so the capture
/// pipeline can hand crops across without the Confirm sheet doing any Vision.
/// When a field has no crop, tap-to-verify degrades to a no-op.
struct CropEvidence {
    var image: UIImage?
    var rect: CGRect
}

/// The whole optional input of the scanned path into the shared Confirm sheet.
/// `extraction` pre-fills whatever it resolved; `crops` feed tap-to-verify;
/// `qrAnchor` resolves the total authoritatively (docs/SCHEMA.md -> FISCAL QR);
/// `ocrLines` are the recognised lines the mixed-receipt detector (P2.4) reads
/// to offer non-fuel items as separate Expenses.
struct ConfirmPrefill {
    var extraction: FuelExtraction?
    var crops: [ManualFillUpMath.Field: CropEvidence] = [:]
    var qrAnchor: FiscalQRAnchor?
    var ocrLines: [OCRLine] = []
    /// P2.5: the extraction's currency is uncertain - the sheet must ask, never
    /// silently convert (docs/ERRORS.md -> Confirm). False by default; the real
    /// OCR-confidence signal lands with the Foundation-models work (P2.8).
    var currencyLowConfidence: Bool = false
}

// MARK: - Debug seeding (screenshots + UI tests)

/// Builds a `ConfirmPrefill` from launch arguments, the same test-hook pattern
/// as `-seedCaptureDetection`:
/// - `-seedConfirmPrefillEmpty` - the all-nil extraction that must render as
///   the ordinary empty form (hard rule 15).
/// - `-seedConfirmPrefillSparse` - one field resolved (a pump's liters), the
///   rest blank and focusable, the resolved field dimmed.
/// - `-seedConfirmPrefill` - the common partly-empty reality (liters + price,
///   the total derives); the resolved fields are dimmed until confirmed.
/// - `-seedConfirmPrefillLocked` - all three consistent: the lock verifies.
/// - `-seedConfirmPrefillSwapped` - liters and price SWAPPED but consistent
///   (a x b == b x a): the lock still reports verified and must not gate save.
/// - `-seedConfirmPrefillQR` - the QR grand total disagrees with the OCR
///   total (a VAT/rounding line was grabbed): the QR total fills the field.
/// - `-seedConfirmPrefillMixed` - a mixed receipt: the fuel line stands
///   (hard rule 4), never the grand total.
/// - `-seedConfirmForeign` / `-seedConfirmForeignPending` /
///   `-seedConfirmForeignLowConfidence` - the P2.5 foreign-currency states:
///   converted (rate in the seed pack), rate-pending (date outside it), and
///   low-confidence (asks, never converts).
enum ConfirmPrefillSeed {
    static func from(arguments: [String]) -> ConfirmPrefill? {
        if let foreign = foreignPrefill(from: arguments) { return foreign }
        if let pump = pumpPrefill(from: arguments) { return pump }
        if arguments.contains("-seedConfirmPrefillEmpty") {
            return ConfirmPrefill(extraction: FuelExtraction())
        }
        if arguments.contains("-seedConfirmPrefillSparse") {
            return ConfirmPrefill(extraction: FuelExtraction(liters: 42.30,
                                                             currency: .eur,
                                                             date: "17.08.2026"))
        }
        if arguments.contains("-seedConfirmPrefillLocked") {
            return ConfirmPrefill(extraction: FuelExtraction(liters: 42.30, unitPrice: 1.679,
                                                             total: 71.02,
                                                             currency: .eur, fuelKind: .petrol95,
                                                             date: "17.08.2026"))
        }
        if arguments.contains("-seedConfirmPrefillSwapped") {
            // The corpus trap, in seed form: the parser swapped liters and
            // unit price, and a x b == b x a means the cross-check still
            // passes. The lock must never be trusted for assignment, and must
            // never gate saving.
            return ConfirmPrefill(extraction: FuelExtraction(liters: 1.679, unitPrice: 42.30,
                                                             total: 71.02,
                                                             currency: .eur, fuelKind: .petrol95,
                                                             date: "17.08.2026"))
        }
        if arguments.contains("-seedConfirmPrefillQR") {
            // The QR disagrees with the OCR total (a VAT/rounding line was
            // grabbed): the QR total fills the field and outranks the OCR one.
            // Exact, so it is never dimmed; nothing else is resolved yet.
            return ConfirmPrefill(extraction: FuelExtraction(total: 867.00,
                                                             currency: .eur,
                                                             date: "17.08.2026"),
                                  crops: [:],
                                  qrAnchor: FiscalQRAnchor(total: 4334.83,
                                                            date: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        if arguments.contains("-seedConfirmPrefillMixed") {
            return ConfirmPrefill(extraction: FuelExtraction(liters: 20.0, unitPrice: 2.0,
                                                               total: 40.00,
                                                               currency: .eur, fuelKind: .petrol95,
                                                               date: "17.08.2026"),
                                  crops: crops(for: [.total, .volume, .unitPrice]),
                                  qrAnchor: FiscalQRAnchor(total: 50.00,
                                                            date: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        if arguments.contains("-seedConfirmPrefillMixedReceipt") {
            // P2.4: a mixed receipt with TWO non-fuel items, matching the
            // ConfirmMixed artboard (diesel 71.02 + car wash 8.00 + coffee 4.80
            // = receipt total 83.82). The car wash is car-related (defaults to
            // accepted), the coffee is not (defaults to skipped). No QR - the
            // section is driven by line-item structure, so the no-QR path is
            // exercised by the screenshot and the UI test.
            let lines = ["DIESEL 42.30 л X 1.679", "CAR WASH BASIC", "1 X 8.00",
                         "COFFEE L", "1 X 4.80", "83.82", "TOTAL", "83.82"]
            return ConfirmPrefill(
                extraction: FuelExtraction(liters: 42.30, unitPrice: 1.679, total: 71.02,
                                           currency: .eur, fuelKind: .diesel,
                                           date: "17.08.2026"),
                crops: crops(for: [.total, .volume, .unitPrice]),
                qrAnchor: nil,
                ocrLines: lines.map { OCRLine(text: $0) })
        }
        if arguments.contains("-seedConfirmPrefill") {
            return ConfirmPrefill(extraction: FuelExtraction(liters: 42.30, unitPrice: 1.679,
                                                             currency: .eur, fuelKind: .petrol95,
                                                             date: "17.08.2026"),
                                  crops: crops(for: [.volume, .unitPrice]))
        }
        return nil
    }

    /// P2.7: a pump detection, routed through the accuracy gate. Off (the
    /// shipped state) yields nil - the ordinary empty manual form, never an
    /// error (hard rule 15). On (once the gate clears) the extraction pre-fills
    /// as default input the user edits. The simulated reading is pump-007's
    /// labelled triple (Spike/ReceiptSpike/fixtures/pump).
    private static func pumpPrefill(from arguments: [String]) -> ConfirmPrefill? {
        guard arguments.contains("-seedPumpCapture") else { return nil }
        let extraction = FuelExtraction(liters: 60.25, unitPrice: 76.24, total: 4593.46,
                                        currency: .rub, date: "17.08.2026")
        return ConfirmPrefill(
            extraction: PumpPhotoCapture.prefill(
                pumpPhotoEnabled: PumpPhotoGate.allowsPumpPhoto,
                extraction: extraction))
    }

    /// P2.5: the three foreign-currency seeds (converted / rate-pending /
    /// low-confidence). Split out so the main switch stays under the lint
    /// complexity budget.
    private static func foreignPrefill(from arguments: [String]) -> ConfirmPrefill? {
        if arguments.contains("-seedConfirmForeign") {
            // The artboard's foreign fill (ORLEN, 47.30 L x 6.12/L = 289.50 PLN),
            // dated 2026-08-21 - inside the bundled seed pack - so the conversion
            // card shows the worked number: 289.50 / 4.2706 = 67.79 EUR.
            return ConfirmPrefill(extraction: FuelExtraction(liters: 47.30, unitPrice: 6.12,
                                                             total: 289.50, currency: .pln,
                                                             fuelKind: .diesel,
                                                             date: "21.08.2026"),
                                  crops: crops(for: [.total, .volume, .unitPrice]))
        }
        if arguments.contains("-seedConfirmForeignPending") {
            // The same foreign fill dated far outside the seed pack (2020-01-01):
            // no rate, so the sheet is rate-pending (F9) - the original amount
            // is exact, the home amount is absent.
            return ConfirmPrefill(extraction: FuelExtraction(liters: 47.30, unitPrice: 6.12,
                                                             total: 289.50, currency: .pln,
                                                             fuelKind: .diesel,
                                                             date: "01.01.2020"))
        }
        if arguments.contains("-seedConfirmForeignLowConfidence") {
            // Foreign currency flagged low-confidence: the sheet asks ("Which
            // currency is this?") and never converts, even though the seed pack
            // HAS a rate for the pair on that date.
            return ConfirmPrefill(extraction: FuelExtraction(liters: 47.30, unitPrice: 6.12,
                                                             total: 289.50, currency: .pln,
                                                             fuelKind: .diesel,
                                                             date: "21.08.2026"),
                                  currencyLowConfidence: true)
        }
        return nil
    }

    /// A tiny deterministic stand-in for a scanned photo so tap-to-verify can
    /// be exercised without real imagery: a solid taillight square at a
    /// 100x40 crop in its lower-right quadrant.
    private static func crops(for fields: [ManualFillUpMath.Field]) -> [ManualFillUpMath.Field: CropEvidence] {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        let image = renderer.image { context in
            Theme.Palette.taillight.uiColor().setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        return Dictionary(uniqueKeysWithValues: fields.map {
            ($0, CropEvidence(image: image, rect: CGRect(x: 250, y: 280, width: 100, height: 40)))
        })
    }
}

extension Color {
    /// The concrete UIColor of a palette token, for seed imagery only.
    fileprivate func uiColor() -> UIColor {
        UIColor(self)
    }
}
