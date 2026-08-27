import Foundation
import TankbookCore

// Display formatting for the import wizard's figures (P5.5b). Every number a
// user checks from memory - consumption, odometer span, total spend - is
// formatted here so the preview and the review render identically and the
// digits stay readable (no-break-space grouping, like OdometerFormat).

enum ImportFormatting {

    /// "14 208.40 €" - grouped thousands (U+00A0, matching OdometerFormat) and
    /// the currency's symbol. POSIX numerals so a comma-decimal device does not
    /// change the separator.
    static func amount(_ value: Decimal, currency: CurrencyCode) -> String {
        let symbol = AddVehicleSupport.currencySymbol(for: currency)
        let number = grouped(value, fractionDigits: 2)
        if symbol.isEmpty { return "\(number) \(currency.rawValue)" }
        return "\(number) \(symbol)"
    }

    /// "14 208.40" - a plain grouped decimal with a fixed number of digits.
    static func grouped(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "\u{00A0}"
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// "42.31" - a field value (litres, price per litre), no grouping.
    static func decimal(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// "8.2" - the headline consumption figure, one decimal place.
    static func consumption(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// "119 486" - a grouped odometer, the same formatter the rest of the app
    /// uses so the preview cannot disagree with the garage.
    static func odometer(_ value: Int) -> String {
        OdometerFormat.grouped(value)
    }

    /// "Mar 2023" - locale-aware month year for the date-range figure.
    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM yyyy",
                                                        options: 0, locale: Locale.current)
        return formatter.string(from: date)
    }

    /// "Mar 2023 – Aug 2026" - the preview's date-range figure.
    static func dateRange(_ from: Date?, _ to: Date?) -> String {
        guard let from, let to else { return "–" }
        return "\(monthYear(from)) – \(monthYear(to))"
    }

    /// "3 Nov 2024" - a review row's date (the file's date, never today).
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "d MMM yyyy",
                                                        options: 0, locale: Locale.current)
        return formatter.string(from: date)
    }

    /// The preview's "Units & currency" figure: "L/100km · EUR".
    static func unitsCurrency(units: Vehicle.Units, currency: CurrencyCode?) -> String {
        let unitsLabel = L10n.consumptionUnit(units.consumption)
        guard let currency else { return unitsLabel }
        return "\(unitsLabel) · \(currency.rawValue)"
    }
}
