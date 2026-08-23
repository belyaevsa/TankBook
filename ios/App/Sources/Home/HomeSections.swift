import SwiftUI
import TankbookCore
import UIKit

// MARK: - Home display formatting

/// Plain display helpers for Home figures. Numbers in DIN, units subordinate
/// (hard rule 6); the decimal separator is pinned to the input's raw dot via
/// `ManualFillUpFormat` (en_US_POSIX), exactly as P1.3 established.
enum HomeFormat {
    /// "€212" - the month spend tile (0 fraction digits, symbol first).
    static func spend(_ amount: Decimal, symbol: String) -> String {
        "\(symbol)\(ManualFillUpFormat.decimal(amount, fractionDigits: 0))"
    }

    /// "1.679 €" - the last price per litre tile (3 fraction digits).
    static func unitPrice(_ amount: Decimal, symbol: String) -> String {
        "\(ManualFillUpFormat.decimal(amount, fractionDigits: 3)) \(symbol)"
    }

    /// "71.02 €" - a recent-entry amount (2 fraction digits).
    static func entryAmount(_ amount: Decimal, symbol: String) -> String {
        "\(ManualFillUpFormat.decimal(amount, fractionDigits: 2)) \(symbol)"
    }

    /// "0.15 €" - the per-km cost (2 fraction digits; per-km costs live below
    /// one unit and must not round to "€0").
    static func costPerKm(_ value: Double, symbol: String) -> String {
        let amount = NSDecimalNumber(value: value).decimalValue
        return "\(ManualFillUpFormat.decimal(amount, fractionDigits: 2)) \(symbol)"
    }

    /// "Aug 17" for the "updated <date>" caption.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The current month's name for the vitals and the entries section header.
    static func currentMonth(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.month(.wide))
    }
}

// MARK: - Garage card

/// The compact garage card (design/DESIGN.md: Home leads with the car card -
/// photo, name, odometer). Odometer is grouped with a thin space
/// (HANDOVER.md open item 0) and the date line is honest: "updated" once an
/// entry exists, "added" from the vehicle's createdAt before that.
struct HomeGarageCard: View {
    let vehicle: Vehicle
    let odometer: Int?
    let updatedAt: Date?
    let photoData: Data?

    var body: some View {
        HStack(spacing: 12) {
            photo
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                if let odometer {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(OdometerFormat.grouped(odometer))
                            .font(.custom(AppFonts.dinAlternateBold, size: 22))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(L10n.distanceUnit(vehicle.units.distance))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .accessibilityIdentifier("homeOdometer")
                }
                Text(dateCaption)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .formCard()
    }

    @ViewBuilder
    private var photo: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.midnight)
                    Image(systemName: "camera")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Palette.headlight)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var dateCaption: String {
        if let updatedAt {
            return String(format: L10n.localize("Updated %@"), HomeFormat.day(updatedAt))
        }
        return String(format: L10n.localize("Added %@"), HomeFormat.day(vehicle.createdAt))
    }
}

// MARK: - Headline block

/// The hero: average consumption in DIN Condensed, with the honest label line
/// below - "Best this year", a "first estimate" label, or the D4 hint when no
/// segment has closed yet (docs/ERRORS.md -> Home, row D4).
struct HomeHeadlineBlock: View {
    let stats: HomeStats
    let vehicle: Vehicle
    let onCapture: () -> Void

    var body: some View {
        if let headline = stats.headline {
            VStack(alignment: .leading, spacing: 6) {
                Text("Average consumption")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("homeHeadlineEyebrow")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ManualFillUpFormat.decimal(headline.value, fractionDigits: 1))
                        .font(.custom(AppFonts.dinCondensedBold, size: 68))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("homeHeadlineValue")
                    Text(L10n.consumptionUnit(vehicle.units.consumption))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .tracking(0.4)
                }
                labelLine(headline)
            }
        } else if stats.needsAnotherFullTank {
            d4Hint
        }
    }

    @ViewBuilder
    private func labelLine(_ headline: Headline) -> some View {
        if stats.isFirstEstimate, case .firstEstimate(let cycles) = headline.label {
            Text(String(format: L10n.localize("first estimate · %d fill cycle"), cycles))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("homeFirstEstimateLabel")
        } else if let best = stats.bestThisYear {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.bold))
                Text("Best this year")
                    .font(.caption.weight(.semibold))
                Text(ManualFillUpFormat.decimal(best, fractionDigits: 1))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .foregroundStyle(Theme.Palette.taillight)
            .accessibilityIdentifier("homeBestThisYear")
        }
    }

    private var d4Hint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One more full tank and your consumption appears")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("homeD4Hint")
            Button("Type it", action: onCapture)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.headlight)
                .accessibilityIdentifier("homeD4CaptureButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
    }
}

// MARK: - Vitals row

/// The two vital tiles (HomeA artboard: "August spend", "Last price/L"). A tile
/// with nothing honest to show is OMITTED, never rendered as "N/A", "–" or
/// "0.0" (docs/ERRORS.md -> Home; the L4 no-N/A-tiles assertion).
struct HomeVitalsRow: View {
    let stats: HomeStats
    let vehicle: Vehicle

    private var symbol: String { AddVehicleSupport.currencySymbol(for: vehicle.homeCurrency) }

    var body: some View {
        HStack(spacing: 10) {
            if let monthSpend = stats.monthSpend {
                tile(title: String(format: L10n.localize("%@ spend"), HomeFormat.currentMonth()),
                     value: HomeFormat.spend(monthSpend, symbol: symbol),
                     identifier: "homeMonthSpendTile")
            }
            if let lastPrice = stats.lastUnitPrice {
                tile(title: L10n.localize("Last price/L"),
                     value: HomeFormat.unitPrice(lastPrice, symbol: symbol),
                     identifier: "homeLastPriceTile")
            }
        }
    }

    private func tile(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(value)
                .font(.custom(AppFonts.dinAlternateBold, size: 22))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .formCard()
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Recent entries

/// The recent-entries preview (HomeA artboard's monthly section). This is the
/// Home preview, not the full Log stream (P1.5): newest few entries, each a
/// route to Edit entry. A conflicting entry carries the amber F9a/S3 badge and
/// the section footnotes the excluded count (docs/ERRORS.md -> Home).
struct HomeRecentEntries: View {
    let entries: [any Entry]
    let stations: [Station]
    let vehicle: Vehicle
    let excludedEntryCount: Int

    private var rows: [HomeEntryRow] {
        entries
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            .prefix(6)
            .map { HomeEntryRow(entry: $0, stationName: stationName($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rows.first.map { HomeFormat.currentMonth($0.date) } ?? HomeFormat.currentMonth())
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                if excludedEntryCount > 0 {
                    Text("1 entry excluded")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.warn)
                        .accessibilityIdentifier("homeExcludedFootnote")
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
                    if index < rows.count - 1 { CardDivider() }
                }
            }
            .formCard()
        }
        .padding(.top, 6)
    }

    private func rowView(_ row: HomeEntryRow) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.editEntry) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(row.dotColor)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            if row.isConflicted {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Palette.warn)
                            }
                        }
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let amount = row.amount {
                        Text(amount)
                            .font(.custom(AppFonts.dinAlternateBold, size: 16))
                            .foregroundStyle(Theme.Palette.ink)
                            .accessibilityIdentifier("homeEntryAmount")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editEntryButton")

            if row.isConflicted {
                NavigationLink(value: Route.editEntry) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Palette.warn)
                        .padding(6)
                        .background(Circle().fill(Theme.Palette.warn.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("conflictBadgeButton")
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
    }

    private func stationName(_ entry: any Entry) -> String? {
        guard let stationID = (entry as? FillUp)?.stationId else { return nil }
        return stations.first { $0.id == stationID }?.name
    }
}

/// A single Home entry row, rendered from any `Entry` type (fuel, charge,
/// service, expense). Colors follow DESIGN.md accent semantics: taillight for
/// fuel, headlight for electric, neutral inkSoft for service/expense.
private struct HomeEntryRow: Identifiable {
    let id: UUID
    let date: Date
    let dotColor: Color
    let title: String
    let subtitle: String
    let amount: String?
    let isConflicted: Bool

    init(entry: any Entry, stationName: String?) {
        self.id = entry.id
        self.date = entry.date
        self.isConflicted = entry.conflict != .none

        let symbol = entry.money.map {
            AddVehicleSupport.currencySymbol(for: $0.homeCurrency)
        } ?? ""
        self.amount = entry.money?.homeAmount.map {
            HomeFormat.entryAmount($0, symbol: symbol)
        }

        if let fill = entry as? FillUp {
            self.dotColor = Theme.Palette.taillight
            self.title = stationName ?? fill.fuelKind.fuelKindLabel
            var parts: [String] = []
            parts.append("\(ManualFillUpFormat.decimal(fill.volumeL, fractionDigits: 1)) \(L10n.volumeUnit(.l))")
            parts.append(fill.fuelKind.fuelKindLabel)
            parts.append(HomeFormat.day(fill.date))
            self.subtitle = parts.joined(separator: " · ")
        } else if let charge = entry as? ChargeSession {
            self.dotColor = Theme.Palette.headlight
            self.title = charge.provider ?? "Charge"
            var parts: [String] = []
            parts.append("\(ManualFillUpFormat.decimal(charge.energyKWh, fractionDigits: 0)) \(L10n.kWh)")
            parts.append(charge.chargeType.chargeTypeLabel)
            parts.append(HomeFormat.day(charge.date))
            self.subtitle = parts.joined(separator: " · ")
        } else if let service = entry as? ServiceRecord {
            self.dotColor = Theme.Palette.inkSoft
            self.title = service.vendor ?? "Service"
            self.subtitle = HomeFormat.day(service.date)
        } else if let expense = entry as? Expense {
            self.dotColor = Theme.Palette.inkSoft
            self.title = expense.title
            self.subtitle = HomeFormat.day(expense.date)
        } else {
            self.dotColor = Theme.Palette.inkSoft
            self.title = "Entry"
            self.subtitle = HomeFormat.day(entry.date)
        }
    }
}

private extension FuelKind {
    var fuelKindLabel: String {
        switch self {
        case .diesel: return L10n.localize("Diesel")
        case .petrol95: return L10n.localize("95")
        case .petrol98: return L10n.localize("98")
        case .lpg: return L10n.localize("LPG")
        case .cng: return L10n.localize("CNG")
        case .e85: return L10n.localize("E85")
        case .electricity: return L10n.localize("Electricity")
        }
    }
}

private extension ChargeType {
    var chargeTypeLabel: String {
        switch self {
        case .acHome: return "Home"
        case .acPublic: return "AC"
        case .dcPublic: return "DC"
        }
    }
}
