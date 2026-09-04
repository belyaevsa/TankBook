import Foundation
import TankbookCore

// MARK: - RV.45 the per-field comparison's value rendering (docs/DESIGN.md)
//
// The inbox card shows each offered field as "yours vs the receipt". This file
// owns the VALUE strings so the view stays layout-only. Numbers in DIN,
// `tabular-nums` at the call site so a comparison lines up column-wise; money
// amount-then-symbol separated by U+00A0 (never symbol-first); a blank renders
// as an en-dash, never a guessed zero (hard rule 13 - a blank stays blank).

enum InboxValueFormat {
    /// The marker for a field the user left blank. An en-dash, never "0" or "" -
    /// a blank that reads as a value is a lie, and an empty cell reads as broken.
    static let blank = "–"

    /// The row's field label (date, fuel kind, volume, unit price, total,
    /// currency) - the six fields the receipt can read.
    static func label(_ field: FieldRef) -> String {
        switch field {
        case .date: return L10n.localize("Date")
        case .fuelKind: return L10n.localize("Fuel")
        case .volume: return L10n.localize("Litres")
        case .unitPrice: return L10n.localize("Price/L")
        case .total: return L10n.localize("Total")
        case .currency: return L10n.localize("Currency")
        default: return ""
        }
    }

    /// The user's saved value for a field, or the blank marker.
    static func yours(_ field: FieldRef, entry: FillUp) -> String {
        switch field {
        case .date:
            return entry.date.formatted(.dateTime.month(.abbreviated).day().year())
        case .fuelKind:
            return entry.fuelKind.inboxLabel
        case .volume:
            return "\(ManualFillUpFormat.decimal(entry.volumeL, fractionDigits: 2)) \(L10n.volumeUnit(.l))"
        case .unitPrice:
            return entry.unitPrice.map { money($0, fractionDigits: 3, symbol: symbol(for: entry)) } ?? blank
        case .total:
            return entry.money.map { money($0.amount, fractionDigits: 2, symbol: symbol(for: entry)) } ?? blank
        case .currency:
            return entry.money.map { $0.currency.rawValue } ?? blank
        default:
            return blank
        }
    }

    /// The receipt's reading for a field, or the blank marker (a field the
    /// receipt did not read is not offered, so this should not be reached).
    static func receipt(_ field: FieldRef, entry: FillUp, extraction: GatewayExtraction) -> String {
        switch field {
        case .date:
            if let raw = extraction.date?.value, let parsed = ConfirmDate.parse(raw) {
                return parsed.formatted(.dateTime.month(.abbreviated).day().year())
            }
            return blank
        case .fuelKind:
            return extraction.fuelKind.map { $0.value.inboxLabel } ?? blank
        case .volume:
            return extraction.volume.map {
                "\(ManualFillUpFormat.decimal($0.value, fractionDigits: 2)) \(L10n.volumeUnit(.l))"
            } ?? blank
        case .unitPrice:
            return extraction.unitPrice.map {
                money($0.value, fractionDigits: 3, symbol: receiptSymbol(entry: entry, extraction: extraction))
            } ?? blank
        case .total:
            return extraction.total.map {
                money($0.value, fractionDigits: 2, symbol: receiptSymbol(entry: entry, extraction: extraction))
            } ?? blank
        case .currency:
            return extraction.currency.map { $0.value.rawValue } ?? blank
        default:
            return blank
        }
    }

    /// "68.46 €" - amount then a no-break-space then symbol, never symbol-first
    /// (docs/DESIGN.md). No symbol when the currency has none distinct from its
    /// code (so a CHF figure does not print "CHF CHF").
    private static func money(_ amount: Decimal, fractionDigits: Int, symbol: String) -> String {
        let figure = ManualFillUpFormat.decimal(amount, fractionDigits: fractionDigits)
        return symbol.isEmpty ? figure : "\(figure)\u{00A0}\(symbol)"
    }

    private static func symbol(for entry: FillUp) -> String {
        entry.money.map { AddVehicleSupport.currencySymbol(for: $0.currency) } ?? ""
    }

    /// The receipt's money symbol: the currency the receipt read, falling back to
    /// the entry's when the receipt read no currency. The symbol is always the
    /// figure's own currency (hard rule 3).
    private static func receiptSymbol(entry: FillUp, extraction: GatewayExtraction) -> String {
        if let currency = extraction.currency?.value {
            return AddVehicleSupport.currencySymbol(for: currency)
        }
        return symbol(for: entry)
    }
}

extension FuelKind {
    /// The fuel kind's localized display label as a `String` (the `labelKey`
    /// `LocalizedStringKey` cannot be read back for a comparison cell).
    var inboxLabel: String {
        switch self {
        case .diesel: return L10n.localize("Diesel")
        case .petrol92: return L10n.localize("92")
        case .petrol95: return L10n.localize("95")
        case .petrol98: return L10n.localize("98")
        case .petrol100: return L10n.localize("100")
        case .lpg: return L10n.localize("LPG")
        case .cng: return L10n.localize("CNG")
        case .e85: return L10n.localize("E85")
        case .electricity: return L10n.localize("Electricity")
        }
    }
}
