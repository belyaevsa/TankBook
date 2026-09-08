import SwiftUI
import TankbookCore

// MARK: - S2 combined duplicate card (expanded)

/// One unresolved S2 duplicate pair (docs/SYNC.md S2) as a single card that
/// shows BOTH members instead of hiding them: the detector pairs on sameness
/// (same vehicle, dates within 30 minutes, volume within 5%), so the rows show
/// what DIFFERS - the time of day (the whole reason they were paired), the
/// odometer, the total, and which one carries the attachment (the Merge
/// survivor: docs/SYNC.md "the one with an attachment wins", so the paperclip
/// explains why Merge keeps the entry it keeps). Each member opens its own
/// editor through `Route.editEntry`, never less reachable than the two ordinary
/// rows the card replaced. Counting is untouched: only the counted member feeds
/// any figure until the user decides (docs/SYNC.md S2).
struct HomeDuplicateCard: View {
    let group: LogStream.DuplicateGroup
    let stations: [Station]
    let volumeUnit: VolumeUnit
    let distanceUnit: DistanceUnit
    let onKeepBoth: (LogStream.DuplicateGroup) -> Void
    let onMerge: (LogStream.DuplicateGroup) -> Void

    /// The pair, newest first - the order the two ordinary rows the card
    /// replaced would have appeared in.
    private var members: [LogStream.LogEntry] {
        [group.counted, group.excluded].sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    /// A pair that spans a midnight boundary shows each member's day too - 30
    /// minutes apart can still be two calendar days, and the time alone would
    /// then be ambiguous ("23:47" vs "00:05").
    private var pairSpansDays: Bool {
        !Calendar.current.isDate(group.counted.date, inSameDayAs: group.excluded.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(members) { member in
                CardDivider()
                memberRow(member)
            }
            CardDivider()
            actions
        }
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeDuplicateCard")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Text(String(format: L10n.localize("Possible duplicate – %@, %@ logged twice"),
                        titleText(group.counted), countedVolumeText))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 18) {
            Button("Merge") { onMerge(group) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("homeMergeButton")
            Button("Keep both") { onKeepBoth(group) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("homeKeepBothButton")
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: Member rows

    private func memberRow(_ member: LogStream.LogEntry) -> some View {
        NavigationLink(value: Route.editEntry(member.id)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    titleLine(member)
                    detailsLine(member)
                }
                Spacer(minLength: 8)
                if let amount = amountText(member) {
                    Text(amount)
                        .font(.custom(AppFonts.dinAlternateBold, size: 16))
                        .foregroundStyle(Theme.Palette.ink)
                        .monospacedDigit()
                        .accessibilityIdentifier("homeDuplicateAmount")
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeDuplicateMemberButton")
    }

    private func titleLine(_ member: LogStream.LogEntry) -> some View {
        HStack(spacing: 5) {
            Text(titleText(member))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
            if member.hasAttachment {
                Image(systemName: "paperclip")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityLabel(L10n.localize("Has attachment"))
                    .accessibilityIdentifier("homeDuplicateAttachment")
            }
        }
    }

    private func detailsLine(_ member: LogStream.LogEntry) -> some View {
        SubtitleFlow(spacing: 3, lineSpacing: 2) {
            Text(timeText(member.date))
                .monospacedDigit()
            if let odometer = member.odometer {
                Text("·")
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                Text("\(OdometerFormat.grouped(odometer)) \(L10n.distanceUnit(distanceUnit))")
                    .monospacedDigit()
                    .accessibilityIdentifier("homeDuplicateOdometer")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.Palette.inkSoft)
    }

    // MARK: Formatting

    /// The pair's two entries are 30 minutes apart, so a day shown for one is
    /// shown for both only when the pair straddles a calendar boundary.
    private func timeText(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard pairSpansDays else { return time }
        return "\(HomeFormat.day(date)), \(time)"
    }

    private var countedVolumeText: String {
        guard case .volumeL(let litres) = group.counted.quantity else { return "" }
        return "\(ManualFillUpFormat.decimal(litres, fractionDigits: 1)) \(L10n.volumeUnit(volumeUnit))"
    }

    /// The member's station or fuel kind - the same title the ordinary log row
    /// the pair replaced would have carried.
    private func titleText(_ entry: LogStream.LogEntry) -> String {
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

    private func amountText(_ entry: LogStream.LogEntry) -> String? {
        guard let money = entry.money, let homeAmount = money.homeAmount else { return nil }
        let symbol = AddVehicleSupport.currencySymbol(for: money.homeCurrency)
        return HomeFormat.entryAmount(homeAmount, symbol: symbol)
    }
}
