import Foundation
import TankbookCore

// MARK: - RV.45 the per-field comparison's value rendering (docs/DESIGN.md);
// RV.201 generalised over entry kind.
//
// The inbox card shows each offered field as "yours vs the receipt". This file
// owns the VALUE strings so the view stays layout-only. Numbers in DIN,
// `tabular-nums` at the call site so a comparison lines up column-wise; money
// amount-then-symbol separated by U+00A0 (never symbol-first); a blank renders
// as an en-dash, never a guessed zero (hard rule 13 - a blank stays blank).
//
// The field LABEL is not here: it lives in the one `FieldLabel` table the attach
// path's recognised page also calls (RV.201), so the two surfaces cannot render
// the same field two ways.

enum InboxValueFormat {
    /// The marker for a field the user left blank. An en-dash, never "0" or "" -
    /// a blank that reads as a value is a lie, and an empty cell reads as broken.
    static let blank = "–"

    /// The row's field label, from the one shared table (RV.201). The vehicle's
    /// volume unit is threaded so a gallons car reads "Gallons"/"Price/gal"
    /// (RV.234).
    static func label(_ field: FieldRef, volumeUnit: VolumeUnit = .l) -> String {
        FieldLabel.text(field, volumeUnit: volumeUnit)
    }

    /// One stable, DISTINCT accessibility id per field ref (RV.201). The old
    /// `default: "inboxTick_other"` gave two different non-fuel fields the same
    /// id, so a UI test asserting one could not tell it from the other - a test
    /// that cannot fail. The switch is exhaustive on purpose: a new field ref
    /// must be given its own id, not fall into a shared bucket.
    static func tickID(_ field: FieldRef) -> String {
        switch field {
        case .date: return "inboxTick_date"
        case .fuelKind: return "inboxTick_fuelKind"
        case .volume: return "inboxTick_volume"
        case .unitPrice: return "inboxTick_unitPrice"
        case .total: return "inboxTick_total"
        case .currency: return "inboxTick_currency"
        case .station: return "inboxTick_station"
        case .vendor: return "inboxTick_vendor"
        case .energy: return "inboxTick_energy"
        case .category: return "inboxTick_category"
        case .lineItem(let n): return "inboxTick_lineItem_\(n)"
        }
    }

    /// The user's saved value for a field, or the blank marker. The volume
    /// value renders in the owning car's unit, not the stored litre figure
    /// (RV.271).
    static func yours(_ field: FieldRef, entry: InboxEntry, volumeUnit: VolumeUnit) -> String {
        switch field {
        case .date:
            return entry.date.formatted(.dateTime.month(.abbreviated).day().year())
        case .fuelKind:
            guard case .fillUp(let fillUp) = entry else { return blank }
            return fillUp.fuelKind.inboxLabel
        case .volume:
            guard case .fillUp(let fillUp) = entry else { return blank }
            return volume(fillUp.volumeL, unit: volumeUnit)
        case .unitPrice:
            guard case .fillUp(let fillUp) = entry else { return blank }
            // The stored price is per litre; the row's label is the car's own
            // unit, so the figure converts here and nowhere else.
            return fillUp.unitPrice.map {
                money(ManualFillUpMath.displayUnitPrice(fromPerLitre: $0, unit: volumeUnit),
                      fractionDigits: 3, symbol: symbol(for: entry))
            } ?? blank
        case .total:
            return entry.money.map { money($0.amount, fractionDigits: 2, symbol: symbol(for: entry)) } ?? blank
        case .currency:
            return entry.money.map { $0.currency.rawValue } ?? blank
        case .vendor:
            guard case .service(let service) = entry else { return blank }
            return service.vendor ?? blank
        case .lineItem(let index):
            return lineItemYours(entry: entry, index: index)
        case .category:
            guard case .expense(let expense) = entry else { return blank }
            return L10n.expenseCategoryLabel(expense.category)
        case .station, .energy:
            return blank
        }
    }

    /// The recognition's reading for a field, or the blank marker (a field the
    /// recognition did not read is not offered, so this should not be reached).
    static func receipt(_ field: FieldRef, entry: InboxEntry, recognition: InboxRecognition,
                        volumeUnit: VolumeUnit) -> String {
        switch recognition {
        case .fuel(let extraction):
            return fuelReceipt(field, entry: entry, extraction: extraction, volumeUnit: volumeUnit)
        case .service(let service):
            return serviceReceipt(field, entry: entry, recognition: service)
        case .expense(let expense):
            return expenseReceipt(field, entry: entry, recognition: expense)
        }
    }

    // MARK: - Fuel

    private static func fuelReceipt(_ field: FieldRef,
                                    entry: InboxEntry,
                                    extraction: GatewayExtraction,
                                    volumeUnit: VolumeUnit) -> String {
        switch field {
        case .date:
            if let raw = extraction.date?.value, let parsed = ConfirmDate.parse(raw) {
                return parsed.formatted(.dateTime.month(.abbreviated).day().year())
            }
            return blank
        case .fuelKind:
            return extraction.fuelKind.map { $0.value.inboxLabel } ?? blank
        case .volume:
            // The extraction normalizes every reading to litres and carries no
            // read-unit (FuelExtraction.liters, GatewayWire), so the receipt
            // column renders the car's unit too: that is what keeps the two
            // columns comparable, and on the common imperial case (a US pump
            // printed in gallons) it reproduces the receipt's own number.
            return extraction.volume.map { volume($0.value, unit: volumeUnit) } ?? blank
        case .unitPrice:
            // The extraction normalizes the reading to a per-litre price; the
            // row renders the car's own unit (RV.234), so it converts (RV.274).
            return extraction.unitPrice.map {
                money(ManualFillUpMath.displayUnitPrice(fromPerLitre: $0.value, unit: volumeUnit),
                      fractionDigits: 3,
                      symbol: receiptSymbol(entry: entry, read: extraction.currency?.value))
            } ?? blank
        case .total:
            return extraction.total.map {
                money($0.value, fractionDigits: 2, symbol: receiptSymbol(entry: entry, read: extraction.currency?.value))
            } ?? blank
        case .currency:
            return extraction.currency.map { $0.value.rawValue } ?? blank
        default:
            return blank
        }
    }

    // MARK: - Service

    private static func serviceReceipt(_ field: FieldRef,
                                       entry: InboxEntry,
                                       recognition: ServiceRecognition) -> String {
        switch field {
        case .date:
            return recognition.date.map {
                $0.value.formatted(.dateTime.month(.abbreviated).day().year())
            } ?? blank
        case .vendor:
            return recognition.vendor?.value ?? blank
        case .lineItem(let index):
            guard index < recognition.lineItems.count else { return blank }
            let line = recognition.lineItems[index]
            guard let cost = line.cost else { return line.title }
            return "\(line.title) · \(money(cost.amount, fractionDigits: 2, symbol: AddVehicleSupport.moneySymbol(for: cost.currency)))"
        case .total:
            return recognition.total.map {
                money($0.value, fractionDigits: 2, symbol: receiptSymbol(entry: entry, read: recognition.currency?.value))
            } ?? blank
        case .currency:
            return recognition.currency.map { $0.value.rawValue } ?? blank
        default:
            return blank
        }
    }

    // MARK: - Expense

    private static func expenseReceipt(_ field: FieldRef,
                                       entry: InboxEntry,
                                       recognition: ExpenseRecognition) -> String {
        switch field {
        case .date:
            return recognition.date.map {
                $0.value.formatted(.dateTime.month(.abbreviated).day().year())
            } ?? blank
        case .total:
            return recognition.total.map {
                money($0.value, fractionDigits: 2,
                      symbol: receiptSymbol(entry: entry, read: recognition.currency?.value))
            } ?? blank
        case .currency:
            return recognition.currency.map { $0.value.rawValue } ?? blank
        case .category:
            return recognition.category.map { L10n.expenseCategoryLabel($0.value) } ?? blank
        default:
            return blank
        }
    }

    // MARK: - Shared rendering

    /// The user's saved line item at `index`, title and cost together.
    private static func lineItemYours(entry: InboxEntry, index: Int) -> String {
        guard case .service(let service) = entry, index < service.items.count else { return blank }
        let item = service.items[index]
        guard let cost = item.cost else { return item.title }
        return "\(item.title) · \(money(cost.amount, fractionDigits: 2, symbol: AddVehicleSupport.moneySymbol(for: cost.currency)))"
    }

    /// A stored litre figure in the car's display unit. The one litre<->display
    /// converter (`ManualFillUpMath`) - the same one the fill forms use - never
    /// a second factor (RV.271).
    private static func volume(_ litres: Double, unit: VolumeUnit) -> String {
        let display = ManualFillUpMath.displayVolume(from: litres, unit: unit)
        return "\(ManualFillUpFormat.decimal(display, fractionDigits: 2)) \(L10n.volumeUnit(unit))"
    }

    /// "68.46 €" - amount then a no-break-space then symbol, never symbol-first
    /// (docs/DESIGN.md). No symbol when the currency has none distinct from its
    /// code (so a CHF figure does not print "CHF CHF").
    private static func money(_ amount: Decimal, fractionDigits: Int, symbol: String) -> String {
        let figure = ManualFillUpFormat.decimal(amount, fractionDigits: fractionDigits)
        return symbol.isEmpty ? figure : "\(figure)\u{00A0}\(symbol)"
    }

    private static func symbol(for entry: InboxEntry) -> String {
        entry.money.map { AddVehicleSupport.moneySymbol(for: $0.currency) } ?? ""
    }

    /// The recognition's money symbol: the currency it read, falling back to the
    /// entry's when it read no currency. The symbol is always the figure's own
    /// currency (hard rule 3).
    private static func receiptSymbol(entry: InboxEntry, read: CurrencyCode?) -> String {
        if let read { return AddVehicleSupport.moneySymbol(for: read) }
        return symbol(for: entry)
    }
}

extension FuelKind {
    /// The fuel kind's localized display label as a `String` (the `labelKey`
    /// `LocalizedStringKey` cannot be read back for a comparison cell). The
    /// one label source lives in `L10n.fuelKindLabel`; this is its Inbox
    /// spelling so a comparison cell reads the same words as the chips.
    var inboxLabel: String {
        L10n.fuelKindLabel(self)
    }
}
