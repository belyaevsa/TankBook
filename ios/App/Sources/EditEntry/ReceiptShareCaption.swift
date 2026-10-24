import Foundation
import TankbookCore

/// The text that travels with a shared receipt photo: what the entries made
/// from that receipt say, one labelled line per value, so the person on the
/// other end reads the fill without opening the photo.
///
/// The values are the STORED entries - what the user confirmed or edited -
/// never the raw recognition (hard rule 13: the entry is the user's answer).
/// Every figure is in the currency the receipt was paid in, `Money.amount`,
/// because that is what the photo beside it prints. Sums are per currency and
/// a mixed group lists each currency's sum separately (hard rule 3).
///
/// Shape for a fuel receipt with two shop lines:
///
///     Date: 18 October 2026
///     Station: Shell
///     Fuel: 95
///     Volume: 42.3 L
///     Price / L: 58.900 ₽
///     Amount: 2491.47 ₽
///     Coffee: 240.00 ₽
///     Wipers: 400.00 ₽
///     Expenses: 640.00 ₽
///     Total: 3131.47 ₽
///     Odometer: 123 456 km
enum ReceiptShareCaption {
    /// The caption over `entry`'s purchase group as stored - the receipt's
    /// fill-up and the expenses bought beside it - or the entry alone. A store
    /// read that fails degrades to the entry as passed in.
    @MainActor
    static func stored(for entry: any Entry, volumeUnit: VolumeUnit) -> String {
        let repository = try? AppStore.repository()
        let live = (try? repository?.liveEntries(forVehicle: entry.vehicleId)) ?? []
        let stored = live.first { $0.id == entry.id } ?? entry
        let group = stored.purchaseGroupId.map { id in live.filter { $0.purchaseGroupId == id } } ?? []
        let vehicle = (try? repository?.vehicle(id: entry.vehicleId)) ?? nil
        return text(entries: group.isEmpty ? [stored] : group,
                    stations: (try? repository?.liveStations()) ?? [],
                    units: vehicle?.units ?? Vehicle.Units(distance: .km, volume: volumeUnit,
                                                           consumption: .lPer100, energy: .kWhPer100))
    }

    /// The caption for `entries` - the receipt's purchase group, or the one
    /// entry when it has none. Empty input gives an empty string, which the
    /// share leaves out.
    static func text(entries: [any Entry], stations: [Station], units: Vehicle.Units) -> String {
        let ordered = entries.sorted { rank($0) != rank($1) ? rank($0) < rank($1)
                                                            : $0.createdAt < $1.createdAt }
        guard let first = ordered.first else { return "" }
        var lines = [line(L10n.localize("Date"), first.date.formatted(.dateTime.day().month(.wide).year()))]
        if let stationID = (ordered.first { $0 is FillUp } as? FillUp)?.stationId,
           let station = stations.first(where: { $0.id == stationID })?.displayTitle {
            lines.append(line(L10n.localize("Station"), station))
        }
        let others = ordered.filter { !($0 is FillUp) && !($0 is ChargeSession) }
        for entry in ordered {
            lines += entryLines(entry, stations: stations, units: units, alone: ordered.count == 1)
        }
        if others.count > 1, let sum = sumText(others) {
            lines.append(line(L10n.localize("Expenses"), sum))
        }
        if ordered.count > 1, let sum = sumText(ordered) {
            lines.append(line(L10n.localize("Total"), sum))
        }
        if let odometer = ordered.lazy.compactMap(\.odometer).first {
            lines.append(line(L10n.localize("Odometer"),
                              "\(OdometerFormat.grouped(odometer)) \(L10n.distanceUnit(units.distance))"))
        }
        return lines.joined(separator: "\n")
    }

    /// Fuel first, then charging, then everything bought beside it.
    private static func rank(_ entry: any Entry) -> Int {
        switch entry {
        case is FillUp: return 0
        case is ChargeSession: return 1
        default: return 2
        }
    }

    private static func entryLines(_ entry: any Entry, stations: [Station], units: Vehicle.Units,
                                   alone: Bool) -> [String] {
        switch entry {
        case let fill as FillUp:
            var lines = [line(L10n.localize("Fuel"), L10n.fuelKindLabel(fill.fuelKind)),
                         line(L10n.localize("Volume"),
                              VolumeDisplay.text(fill.volumeL, unit: units.volume))]
            // `unitPrice` is per litre in the receipt's currency; without money
            // there is no currency to name it in.
            if let price = fill.unitPrice, let money = fill.money {
                let label = units.volume == .l ? L10n.localize("Price / L")
                                               : L10n.localize("Price / gal")
                lines.append(line(label, HomeFormat.unitPrice(
                    price, symbol: AddVehicleSupport.moneySymbol(for: money.currency),
                    volumeUnit: units.volume)))
            }
            if let amount = amountText(fill.money) { lines.append(line(L10n.localize("Amount"), amount)) }
            return lines
        case let charge as ChargeSession:
            let energy = "\(ManualFillUpFormat.decimal(charge.energyKWh, fractionDigits: 1)) "
                + L10n.localize("kWh")
            var lines = [line(L10n.localize("Energy"), energy)]
            if let amount = amountText(charge.money) { lines.append(line(L10n.localize("Amount"), amount)) }
            return lines
        default:
            guard let amount = amountText(entry.money) else {
                return alone ? [] : [EntryTitle.text(entry, stations: stations)]
            }
            return [line(alone ? L10n.localize("Amount") : EntryTitle.text(entry, stations: stations),
                         amount)]
        }
    }

    /// "Label: value" for an already-localised label; the pair itself is a
    /// catalog phrase so a language can re-punctuate it.
    private static func line(_ label: String, _ value: String) -> String {
        String(format: L10n.localize("%1$@: %2$@"), label, value)
    }

    private static func amountText(_ money: Money?) -> String? {
        guard let money else { return nil }
        return HomeFormat.entryAmount(money.amount,
                                      symbol: AddVehicleSupport.moneySymbol(for: money.currency))
    }

    /// The entries' amounts summed per currency, in first-seen order and joined
    /// with " · " when there is more than one; nil when none carries money.
    private static func sumText(_ entries: [any Entry]) -> String? {
        var order: [CurrencyCode] = []
        var sums: [CurrencyCode: Decimal] = [:]
        for money in entries.compactMap(\.money) {
            if sums[money.currency] == nil { order.append(money.currency) }
            sums[money.currency, default: 0] += money.amount
        }
        guard !order.isEmpty else { return nil }
        return order
            .map { HomeFormat.entryAmount(sums[$0] ?? 0,
                                          symbol: AddVehicleSupport.moneySymbol(for: $0)) }
            .joined(separator: " · ")
    }
}
