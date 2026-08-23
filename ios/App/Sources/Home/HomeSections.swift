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

    /// The month's name for the stream dividers ("August"), localized by the
    /// device locale - the divider's total is composed separately (see the
    /// divider in `HomeRecentEntries`).
    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
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

// MARK: - Log stream (recent entries)

/// The recent-entries preview (HomeA artboard's monthly section), now the real
/// log stream (P1.5): the flat list became `LogStream`'s derived sections.
///
/// - Entries group by calendar month, newest first, one divider each; the
///   divider carries the month's total spend in DIN (docs/DESIGN.md).
/// - Card content follows docs/DESIGN.md "Entry card content": title is the
///   station or vendor, the trailing figure the amount in DIN, and the subtitle
///   is quantity · fuel kind? · odometer · 📎? · date. The odometer uses
///   `OdometerFormat` and is OMITTED when the entry has none; the attachment is
///   a glyph with an accessibility label, never a word.
/// - Entries sharing a `purchaseGroupId` render as ONE receipt (hard rule 4 /
///   docs/SCHEMA.md CHECK 3): the group shows the grand total, the fuel row
///   inside it shows the fuel amount.
///
/// This is the Home preview, not the full Log stream screen (P1.6): the newest
/// `previewLimit` rows.
struct HomeRecentEntries: View {
    let entries: [any Entry]
    let stations: [Station]
    let vehicle: Vehicle
    let excludedEntryCount: Int

    /// Home is a preview: the newest rows before the full-stream screen (P1.6)
    /// takes over.
    private static let previewLimit = 20

    @State private var collapsedGroupIDs: Set<UUID> = []

    private var stream: LogStream {
        LogStream(vehicle: vehicle, entries: entries)
            .previewRows(Self.previewLimit)
    }

    private var volumeUnit: VolumeUnit { vehicle.units.volume }
    private var distanceUnit: DistanceUnit { vehicle.units.distance }

    private var currencySymbol: String {
        AddVehicleSupport.currencySymbol(for: vehicle.homeCurrency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if excludedEntryCount > 0 {
                excludedFootnote
            }
            ForEach(stream.sections) { section in
                monthSection(section)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Month sections

    private func monthSection(_ section: LogStream.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            monthDivider(section)
            ForEach(section.rows) { row in
                rowCard(row)
            }
        }
    }

    /// The month's divider: name on the left, the month's total spend in DIN on
    /// the right (docs/DESIGN.md). One accessibility element - the composed
    /// label is a full localized phrase per language, never concatenation.
    private func monthDivider(_ section: LogStream.Section) -> some View {
        let monthName = HomeFormat.monthName(section.monthStart)
        let spend = HomeFormat.spend(section.totalSpend, symbol: currencySymbol)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(monthName)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Text(spend)
                .font(.custom(AppFonts.dinAlternateBold, size: 16))
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L10n.localize("%@ · %@"), monthName, spend))
        .accessibilityIdentifier("logMonthDivider")
    }

    private var excludedFootnote: some View {
        Text("1 entry excluded")
            .font(.caption2)
            .foregroundStyle(Theme.Palette.warn)
            .accessibilityIdentifier("homeExcludedFootnote")
    }

    // MARK: Rows

    @ViewBuilder
    private func rowCard(_ row: LogStream.Row) -> some View {
        switch row {
        case .entry(let entry):
            entryCard(entry)
        case .group(let group):
            groupCard(group)
        }
    }

    // MARK: Entry card

    private func entryCard(_ entry: LogStream.LogEntry) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.editEntry) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(dotColor(entry.kind))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        titleLine(entry)
                        subtitleLine(entry)
                    }
                    Spacer(minLength: 8)
                    if let amount = amountText(entry) {
                        Text(amount)
                            .font(.custom(AppFonts.dinAlternateBold, size: 16))
                            .foregroundStyle(Theme.Palette.ink)
                            .accessibilityIdentifier("homeEntryAmount")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("logEntryButton")

            if entry.isConflicted {
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
        .formCard()
    }

    private func titleLine(_ entry: LogStream.LogEntry) -> some View {
        HStack(spacing: 5) {
            Text(title(entry))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
            if entry.isConflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.warn)
            }
        }
    }

    /// The subtitle: `quantity · fuelKind? · odometer? · 📎? · date`. Every
    /// segment the stream decided to show, in order (docs/DESIGN.md). Inside a
    /// purchase group the attachment is omitted - the shared receipt is already
    /// marked once on the group header, and three paperclips on one slip would
    /// be noise.
    private func subtitleLine(_ entry: LogStream.LogEntry,
                              includeAttachment: Bool = true) -> some View {
        let segments = includeAttachment
            ? entry.subtitleSegments
            : entry.subtitleSegments.filter { segment in
                if case .attachment = segment { return false } else { return true }
            }
        return HStack(spacing: 3) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                }
                segmentView(segment)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.Palette.inkSoft)
        .lineLimit(1)
    }

    @ViewBuilder
    private func segmentView(_ segment: LogStream.SubtitleSegment) -> some View {
        switch segment {
        case .quantity(.volumeL(let litres)):
            Text("\(ManualFillUpFormat.decimal(litres, fractionDigits: 1)) \(L10n.volumeUnit(volumeUnit))")
        case .quantity(.energyKWh(let kWh)):
            Text("\(ManualFillUpFormat.decimal(kWh, fractionDigits: 0)) \(L10n.kWh)")
        case .fuelKind(let kind):
            Text(kind.fuelKindLabel)
                .accessibilityIdentifier("logEntryFuelKind")
        case .odometer(let value):
            Text("\(OdometerFormat.grouped(value)) \(L10n.distanceUnit(distanceUnit))")
        case .attachment:
            Image(systemName: "paperclip")
                .font(.caption2)
                .accessibilityLabel(L10n.localize("Has attachment"))
                .accessibilityIdentifier("logEntryAttachment")
        case .date(let date):
            Text(HomeFormat.day(date))
        }
    }

    private func amountText(_ entry: LogStream.LogEntry) -> String? {
        guard let money = entry.money, let homeAmount = money.homeAmount else { return nil }
        let symbol = AddVehicleSupport.currencySymbol(for: money.homeCurrency)
        return HomeFormat.entryAmount(homeAmount, symbol: symbol)
    }

    private func dotColor(_ kind: LogStream.Kind) -> Color {
        switch kind {
        case .fuel: return Theme.Palette.taillight
        case .charge: return Theme.Palette.headlight
        case .service, .expense: return Theme.Palette.inkSoft
        }
    }

    private func title(_ entry: LogStream.LogEntry) -> String {
        switch entry.kind {
        case .fuel:
            if let stationID = entry.stationId,
               let name = stations.first(where: { $0.id == stationID })?.name {
                return name
            }
            return entry.fuelKind?.fuelKindLabel ?? L10n.localize("Fuel")
        case .charge:
            return entry.provider ?? L10n.localize("Charge")
        case .service:
            return entry.vendor ?? L10n.localize("Service")
        case .expense:
            return entry.entryTitle ?? L10n.localize("Expense")
        }
    }

    // MARK: Purchase group card

    /// One physical purchase from a single receipt (docs/SCHEMA.md CHECK 3).
    /// The group's trailing figure is the grand total; the fuel row inside it
    /// shows the FUEL amount - never the other way around (hard rule 4).
    private func groupCard(_ group: LogStream.LogGroup) -> some View {
        let collapsed = collapsedGroupIDs.contains(group.id)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsed {
                        collapsedGroupIDs.remove(group.id)
                    } else {
                        collapsedGroupIDs.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(dotColor(group.members.first?.kind ?? .fuel))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(groupTitle(group))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            if group.hasAttachment {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .accessibilityLabel(L10n.localize("Has attachment"))
                                    .accessibilityIdentifier("logEntryAttachment")
                            }
                        }
                        Text(collapsed ? groupCountLabel(group) : L10n.localize("Tap to hide items"))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Text(HomeFormat.entryAmount(group.grandTotal, symbol: currencySymbol))
                        .font(.custom(AppFonts.dinAlternateBold, size: 16))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("logGroupGrandTotal")
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("logGroupToggle")

            if !collapsed {
                ForEach(group.members) { member in
                    CardDivider()
                    groupMemberRow(member)
                }
            }
        }
        .formCard()
    }

    private func groupCountLabel(_ group: LogStream.LogGroup) -> String {
        String(format: L10n.localize("%d items on this receipt"), group.members.count)
    }

    private func groupTitle(_ group: LogStream.LogGroup) -> String {
        group.members.first.map(title) ?? L10n.localize("Purchase")
    }

    /// A member row inside an expanded group. The fuel member shows its FUEL
    /// amount, never the receipt's grand total (hard rule 4).
    private func groupMemberRow(_ member: LogStream.LogEntry) -> some View {
        NavigationLink(value: Route.editEntry) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    titleLine(member)
                    subtitleLine(member, includeAttachment: false)
                }
                Spacer(minLength: 8)
                if let amount = amountText(member) {
                    Text(amount)
                        .font(.custom(AppFonts.dinAlternateBold, size: 16))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("logGroupMemberButton")
    }
}

// MARK: - Fuel kind label

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
