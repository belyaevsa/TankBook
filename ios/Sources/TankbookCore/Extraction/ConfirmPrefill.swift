import Foundation

// MARK: - P2.3 confirm-prefill support
//
// Everything the Confirm sheet needs to land a scan as ordinary input: the
// confidence gate that dims resolved-but-unconfirmed fields, the Decimal
// boundary that converts the extractor's `Double`s without binary noise, the
// QR-anchor total resolution, the date parse, and the reduce-motion decision.
// All thresholds live HERE, in one named place with unit tests - none of them
// is an OCR confidence score, which `pump-004` proved worthless (Vision
// returned a wrong digit at confidence 1.00).

// MARK: - The dimming gate

/// The per-field confidence treatment on the confirm sheet (docs/DESIGN.md:
/// "Low-confidence OCR fields render at 60% opacity until confirmed by tap or
/// edit. Confidence is shown, not hidden.").
public enum ConfirmFieldConfidence: Equatable, Sendable {
    /// Rendered at full opacity. Either the cross-check verified the triple,
    /// the field was never a pre-fill (blank is an honest absence), or the
    /// user has confirmed it by tapping or editing.
    case confirmed
    /// Rendered dimmed: the extraction resolved this field but nothing yet
    /// corroborates it. Dimming is VISUAL ONLY - the field stays fully
    /// editable, focusable and normally announced to VoiceOver (hard rule 13:
    /// a dimmed field is a default input, never read-only).
    case unconfirmed
}

/// The one place the confirm screen's confidence thresholds live (task P2.3
/// check 2). Dimming is driven by whether the extraction RESOLVED a field and
/// whether the cross-check AGREES - never by an OCR score.
public enum ConfirmConfidenceGate {

    /// The DESIGN.md dimming opacity: 60%.
    public static let dimmedOpacity: Double = 0.6

    /// CHECK 3's tolerance, `max(0.02, amount x 0.005)` (docs/SCHEMA.md). The
    /// cross-check "agrees" boundary: a triple whose product is within this of
    /// the total is verified; a hair beyond it is a mismatch. Shared with
    /// `TimelineValidator.crossCheck` so the confirm screen and the validator
    /// can never disagree about where the boundary is.
    public static func crossCheckTolerance(amount: Decimal) -> Decimal {
        max(Decimal(string: "0.02")!,
            amount * Decimal(string: "0.005")!)
    }

    /// The dimming decision for one field.
    ///
    /// - `resolved`: the extraction produced a value for this field.
    /// - `crossCheck`: the three-number cross-check state (the agree signal).
    /// - `userConfirmed`: the user has tapped or edited the field since the
    ///   pre-fill ("until confirmed by tap or edit" - DESIGN.md).
    public static func confidence(resolved: Bool,
                                  crossCheck: CrossCheckState,
                                  userConfirmed: Bool) -> ConfirmFieldConfidence {
        guard resolved, !userConfirmed else { return .confirmed }
        // A blank field is an honest absence, never dimmed; the view only asks
        // for a treatment when the field shows a value.
        if case .notApplicable = crossCheck { return .unconfirmed }
        // .verified confirms the triple; .mismatch surfaces the suspect field
        // in amber instead of dimming it (the existing cross-check line).
        return .confirmed
    }
}

// MARK: - The Decimal boundary

/// The boundary where the extractor's `Double`s become form input (task P2.3
/// check 8). The extraction types money as `Double` (the `Decimal` fix is
/// P2.2b), so a value enters the form state formatted to the field's fraction
/// digits and is re-parsed with `Decimal(string:)` - never `Decimal(double:)`,
/// whose binary rounding under-specifies money. `4201.68` survives this path
/// as the exact `Decimal` `4201.68`.
public enum ConfirmFormat {

    /// The display digits per numeric field, matching the receipt card
    /// (design/screens/ConfirmA.dc.html): money and volume to 2 places, price
    /// per litre to 3.
    public static func fractionDigits(for field: ManualFillUpMath.Field) -> Int {
        switch field {
        case .total, .volume: return 2
        case .unitPrice: return 3
        }
    }

    /// `Double` -> `Decimal` through a formatted string. `nil` passes through
    /// (a nil extraction field stays blank and focusable - never `0`).
    public static func decimal(fromExtraction value: Double?, fractionDigits: Int) -> Decimal? {
        guard let value else { return nil }
        let formatted = String(format: "%.\(fractionDigits)f", value)
        return Decimal(string: formatted, locale: posixLocale)
    }

    /// `Double` -> display string for a form field, with no thousand grouping
    /// (grouping is display-only and belongs to the odometer formatter).
    public static func string(fromExtraction value: Double?, fractionDigits: Int) -> String {
        guard let decimal = decimal(fromExtraction: value, fractionDigits: fractionDigits) else {
            return ""
        }
        return string(decimal: decimal, fractionDigits: fractionDigits)
    }

    /// A `Decimal` (e.g. a QR total, already exact) -> display string.
    public static func string(decimal value: Decimal, fractionDigits: Int) -> String {
        formatter(fractionDigits: fractionDigits).string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static func formatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        // Pinned to the input fields' separator, exactly like the existing pump
        // card formatter: the value the user sees in the field is the value the
        // form parses, whatever the device region.
        formatter.locale = posixLocale
        return formatter
    }
}

// MARK: - The QR-anchor total resolution

/// What the form's total field should show once the QR anchor has had its say.
/// The QR's total is EXACT and outranks the OCR total (docs/SCHEMA.md ->
/// FISCAL QR); on a mixed receipt the fuel line stands (hard rule 4).
public enum ConfirmQRTotalResolution: Equatable, Sendable {
    /// No QR anchor: the OCR total stands (nil when OCR had no total either).
    case noAnchor(ocrTotal: Decimal?)
    /// The QR grand total agrees with the OCR candidate: the OCR total is
    /// confirmed and stands.
    case ocrConfirmed(Decimal)
    /// The QR grand total disagrees (or OCR produced no total): the QR total
    /// is authoritative and fills the field.
    case qrAuthoritative(Decimal)
    /// The OCR value is the fuel line of a mixed receipt, less than the grand
    /// total but still most of it: the fill-up amount is the fuel line, never
    /// the grand total. The fuel line = liters x unitPrice in exact Decimal.
    case fuelLineStands(Decimal)
}

/// The pure resolution rule, L1-testable without a view. On `.disagrees` the
/// QR total fills the field; on `.suggestsMixedReceipt` the fuel line stands
/// and the grand-total difference is left for P2.4.
public enum ConfirmQRTotal {

    public static func resolve(extraction: FuelExtraction,
                               qrAnchor: FiscalQRAnchor?) -> ConfirmQRTotalResolution {
        let ocrTotal = ConfirmFormat.decimal(fromExtraction: extraction.total,
                                             fractionDigits: 2)
        guard let qrAnchor else { return .noAnchor(ocrTotal: ocrTotal) }
        guard let ocrTotal else { return .qrAuthoritative(qrAnchor.total) }

        switch FiscalQRCrossCheck.classify(qrTotal: qrAnchor.total, candidateTotal: ocrTotal) {
        case .agrees:
            return .ocrConfirmed(ocrTotal)
        case .disagrees:
            return .qrAuthoritative(qrAnchor.total)
        case .suggestsMixedReceipt:
            // The fuel line, computed in exact Decimal from the formatted
            // operands so a Double multiply never introduces noise. Falls back
            // to the OCR total only when the operands are missing.
            if let liters = ConfirmFormat.decimal(fromExtraction: extraction.liters,
                                                  fractionDigits: 2),
               let price = ConfirmFormat.decimal(fromExtraction: extraction.unitPrice,
                                                 fractionDigits: 3) {
                return .fuelLineStands(liters * price)
            }
            return .fuelLineStands(ocrTotal)
        }
    }
}

// MARK: - Extraction date parsing

/// Parses `FuelExtraction.date` - the `String` the extractor's regex produced,
/// so `17.08.2026`, `17/08/26` and `2026-08-17` are all valid - into a `Date`
/// for the form's date row. Returns nil on anything the extractor would not
/// have emitted (the form then keeps its default date).
public enum ConfirmDate {
    public static func parse(_ raw: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(whereSeparator: { $0 == "." || $0 == "/" || $0 == "-" })
        guard parts.count == 3 else { return nil }
        let calendar = Calendar(identifier: .gregorian)

        // ISO `yyyy-mm-dd` (the detectDate regex's second alternative).
        if parts[0].count == 4,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            return calendar.date(from: DateComponents(timeZone: timeZone,
                                                      year: year, month: month, day: day))
        }

        // Day-first `dd.mm.yy` / `dd.mm.yyyy`. A two-digit year below 50 maps
        // to the 2000s (a 2026 receipt), otherwise to the 1900s.
        guard let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]) else {
            return nil
        }
        let fullYear = year < 100 ? (year < 50 ? 2000 + year : 1900 + year) : year
        return calendar.date(from: DateComponents(timeZone: timeZone,
                                                  year: fullYear, month: month, day: day))
    }
}

// MARK: - The lock's reduce-motion decision

/// The cross-check lock's motion (docs/DESIGN.md -> Motion: the rule draws in
/// from both ends toward the tick, paired with a `.success` haptic; all motion
/// degrades under Reduce Motion). The decision is named here so the view gates
/// its animation on one tested function and the reduced-motion variant still
/// communicates the state change - the tick appears, just without the spring.
public enum ConfirmLockAnimation {
    public static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
