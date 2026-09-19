import SwiftUI
import TankbookCore
import UIKit

// MARK: - Home display formatting

/// Plain display helpers for Home figures. Numbers in DIN, units subordinate
/// (hard rule 6); the decimal separator is pinned to the input's raw dot via
/// `ManualFillUpFormat` (en_US_POSIX), exactly as P1.3 established.
enum HomeFormat {
    /// "390 €" - the month spend tile and the log's month dividers (0 fraction
    /// digits).
    ///
    /// Symbol **after** the amount, like every other money figure in the app.
    /// It printed "€390" until 2026-08-25, which put two conventions on one
    /// screen: "€390" in the spend tile and the month divider, "68.46 €" on the
    /// rows directly beneath them. `docs/DESIGN.md` shows `71.02 €` and
    /// `1.679 €`, and `HomeA.dc.html` draws amount-then-symbol five times
    /// against one "€212" - so the outlier was the one to fix.
    ///
    /// The separator is a **no-break space (U+00A0)**: DIN Alternate has no
    /// glyph for the thin space the artboard writes as `&thinsp;` (see
    /// `OdometerFormat`), and a plain space would let the figure break.
    static func spend(_ amount: Decimal, symbol: String) -> String {
        "\(ManualFillUpFormat.decimal(amount, fractionDigits: 0))\u{00A0}\(symbol)"
    }

    /// "1.679 €" - the last price per the vehicle's display volume unit (3
    /// fraction digits). The stored figure is per litre; a gallons car reads the
    /// price it actually pays at the pump (RV.234).
    static func unitPrice(_ amount: Decimal, symbol: String, volumeUnit: VolumeUnit) -> String {
        "\(unitPriceValue(amount, volumeUnit: volumeUnit))\u{00A0}\(symbol)"
    }

    /// The bare figure for a `StatTile` that renders its own unit. The
    /// litre-to-display factor is `ManualFillUpMath.displayUnitPrice` - the one
    /// per-litre price converter - never a second copy (RV.274).
    static func unitPriceValue(_ amount: Decimal, volumeUnit: VolumeUnit) -> String {
        ManualFillUpFormat.decimal(
            ManualFillUpMath.displayUnitPrice(fromPerLitre: amount, unit: volumeUnit),
            fractionDigits: 3)
    }

    /// "71.02 €" - a recent-entry amount (2 fraction digits).
    static func entryAmount(_ amount: Decimal, symbol: String) -> String {
        "\(ManualFillUpFormat.decimal(amount, fractionDigits: 2))\u{00A0}\(symbol)"
    }

    /// "0.15 €" - the all-in cost per the vehicle's display distance unit (2
    /// fraction digits; per-unit costs live below one unit and must not round to
    /// "€0"). The stored figure is per kilometre; a miles car reads cost per mile
    /// (RV.234).
    static func costPerKm(_ value: Double, symbol: String, distanceUnit: DistanceUnit) -> String {
        "\(costPerDistanceValue(value, distanceUnit: distanceUnit))\u{00A0}\(symbol)"
    }

    /// The bare figure for a `StatTile` that renders its own currency unit. The
    /// kilometre-to-display-unit factor is `DistanceMath` - the codebase's one
    /// distance converter - never a second copy.
    static func costPerDistanceValue(_ value: Double, distanceUnit: DistanceUnit) -> String {
        ManualFillUpFormat.decimal(
            DistanceMath.perDisplayUnit(fromPerKilometre: value, unit: distanceUnit),
            fractionDigits: 2)
    }

    /// "Aug 17" in the current year, "Aug 17, 15" otherwise - the one
    /// formatter behind every dated-entry surface (RV.89; core `EntryDateText`).
    static func day(_ date: Date) -> String {
        EntryDateText.dayMonth(date)
    }

    /// "September" this year, "September 2015" otherwise - the month-divider
    /// heading: a header's year is FULL, the rows' two digits (RV.89).
    static func monthHeading(_ date: Date) -> String {
        EntryDateText.monthHeading(date)
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

    /// The car's photo through the one shared tile (RV.275). Home passes its
    /// own size and the camera glyph so the card keeps the look it had; the
    /// tile shows the photo the moment the car has one, exactly like the lists.
    private var photo: some View {
        VehicleTile(photoData: photoData, size: 56, cornerRadius: 10,
                    glyph: "camera", glyphSize: 16)
    }

    private var dateCaption: String {
        if let updatedAt {
            return String(format: L10n.localize("Updated %@"), HomeFormat.day(updatedAt))
        }
        return String(format: L10n.localize("Added %@"), HomeFormat.day(vehicle.createdAt))
    }
}

// MARK: - Vitals row

/// The two vital tiles (HomeA artboard: "August spend", "Last price/L"). Renders
/// through the shared `StatTile` component that Trends' grid also uses, so the
/// two screens can never disagree about a number or its label. A tile with
/// nothing honest to show is OMITTED, never rendered as "N/A", "–" or "0.0"
/// (docs/ERRORS.md -> Home; the L4 no-N/A-tiles assertion).
struct HomeVitalsRow: View {
    let stats: HomeStats
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 10) {
            // The month-spend tile states exactly what the month's divider may
            // print (RV.112): a `.complete` month is the bare figure, a
            // `.partial` one prints its KNOWN sum with the pending phrase
            // beneath it as the tile's caption, and a `.pending` month (no row
            // converted) is OMITTED - a tile slot that would read `0 €` is
            // never built, and the F9 footnote on the log below says why.
            // The figure carries its own currency (RV.145): the tile shows the
            // total with the currency it is denominated in, and a `.mixed`
            // month (known figures spanning home currencies) prints its
            // per-currency breakdown rather than a bare cross-currency sum.
            if let total = stats.monthSpend, let figure = HomeFormat.spend(total) {
                StatTile(title: String(format: L10n.localize("%@ spend"), HomeFormat.currentMonth()),
                         value: figure,
                         identifier: "homeMonthSpendTile",
                         caption: Self.spendTileCaption(total))
            }
            // RV.29 display decision (converted home, never the raw original):
            // the price per litre is a money figure, and every money figure on
            // this screen is home-denominated - a foreign fill is converted by
            // its own immutable rate snapshot (hard rule 3), never shown as its
            // original number under a home symbol. A fill whose rate is pending
            // has no home figure yet: it is skipped exactly as `monthSpend`
            // skips one (the F9 footnote below explains), so this tile shows
            // the most recent price expressible in home currency. `HomeStats`
            // already carried out both the conversion and the currency, so the
            // symbol printed here is the figure's own - never the vehicle's by
            // default.
            if let lastPrice = stats.lastUnitPrice {
                StatTile(title: ManualFillUpUnitCopy.lastPriceLabel(for: vehicle.units.volume),
                         value: HomeFormat.unitPrice(lastPrice.amount,
                                                     symbol: AddVehicleSupport.moneySymbol(for: lastPrice.currency),
                                                     volumeUnit: vehicle.units.volume),
                         identifier: "homeLastPriceTile")
            }
        }
    }

    /// The tile's caption: the pending phrase when rows still wait, `nil`
    /// otherwise (a `.complete` month or a mixed one whose rows all converted).
    private static func spendTileCaption(_ total: LogStream.MonthTotal) -> String? {
        switch total {
        case .partial(_, _, let pendingCount), .mixed(_, let pendingCount):
            return L10n.pendingRates(pendingCount)
        case .complete, .pending:
            return nil
        }
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
/// This is the Log: the Log tab is Home (`AppTabBar.log == 0`) and this list is
/// the whole stream surface - no separate full-stream screen exists. RV.103: it
/// opens with the newest whole months that cover `previewLimit` rows, and a
/// "show N older entries" reveal grows it in whole-month pages to the full
/// history - a divider only ever sums rows shown beneath it, never a partial
/// month, and a purchase group is never split across a reveal step.
struct HomeRecentEntries: View {
    let entries: [any Entry]
    let stations: [Station]
    let vehicle: Vehicle
    let excludedEntryCount: Int
    /// The excluded entries' ids, most recent first - the footnote's destination
    /// needs the concrete entry (N == 1) or the count of them (N > 1, the list).
    let excludedEntryIDs: [UUID]
    /// The F9 pending-rates footnote count (docs/JOURNEYS.md F9) - how many
    /// entries are still waiting on a rate. Derived by `HomeStats` (P5.2a);
    /// the footnote renders beside the excluded one and disappears at zero.
    let pendingRateCount: Int
    /// S2 pairs the user already resolved as "keep both" - the stream renders
    /// them as two normal rows, never as a duplicate card again
    /// (docs/SYNC.md S2).
    let duplicateResolutions: Set<DuplicateDetector.PairKey>
    var pendingInboxEntryIDs: Set<UUID> = []
    /// RV.284: entry rows in the `rejected` sync state (server refused them
    /// structurally) - the "not synced" badge taps through to edit.
    var rejectedEntryIDs: Set<UUID> = []
    /// The two ways an unresolved duplicate card can be decided (docs/SYNC.md
    /// S2; docs/ERRORS.md -> Home). The view renders the affordances; the
    /// resolution is a repository write the parent owns.
    let onKeepBoth: (LogStream.DuplicateGroup) -> Void
    let onMerge: (LogStream.DuplicateGroup) -> Void
    /// RV.106: the footnote's next-step action (hard rule 7) - the demand drain
    /// over the rows actually rate-pending, so an imported row whose rate the
    /// server had not published yet can be asked for now. Async so the shared
    /// footnote can hold its immediate "Checking for rates…" acknowledgement
    /// until the drain returns (RV.132).
    let onCheckRates: () async -> Void

    /// The reveal's first-page floor: the preview opens with the newest whole
    /// months whose combined rows first reach this many rows, and each later
    /// reveal adds whole months covering the same count again. Rows are never
    /// the cut - whole months are - so this is a floor, not a hard cap.
    private static let previewLimit = 20

    @State private var collapsedGroupIDs: Set<UUID> = []
    /// Reveal pages shown: 1 = the preview (newest whole months covering
    /// `previewLimit` rows); the load-more row in `+LogStream` grows it.
    @State var revealedPageCount = 1

    private var volumeUnit: VolumeUnit { vehicle.units.volume }
    private var distanceUnit: DistanceUnit { vehicle.units.distance }
    private var consumptionUnitLabel: String { L10n.consumptionUnit(vehicle.units.consumption) }

    var body: some View {
        let reveal = HomeLogReveal(vehicle: vehicle, entries: entries,
                                   duplicateResolutions: duplicateResolutions,
                                   stations: stations,
                                   pageCount: revealedPageCount,
                                   initialRowCount: Self.previewLimit)
        return VStack(alignment: .leading, spacing: 10) {
            if excludedEntryCount > 0 {
                excludedFootnote
            }
            if pendingRateCount > 0 {
                pendingRatesFootnote
            }
            ForEach(reveal.months) { section in
                monthSection(section)
            }
            // RV.103: the door past the preview, below the last visible month
            // (hard rule 7), only while older entries are hidden.
            if reveal.hiddenEntryCount > 0 {
                loadMoreRow(reveal.hiddenEntryCount)
            }
        }
        .padding(.top, 6)
        .onChange(of: vehicle.id) { _, _ in
            // The reveal belongs to a car's history: a switched car starts from
            // its own preview again, never inheriting another car's expansion.
            revealedPageCount = 1
        }
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

    /// The excluded-count footnote, via the shared component Trends also uses -
    /// one implementation, one wording (docs/ERRORS.md -> Home, F9a/S2). RV.141:
    /// Home gets the same next step as Trends - the footnote opens the excluded
    /// entry when exactly one is out, the excluded-entries list when more are
    /// (a singular route could only ever reach one of N).
    @ViewBuilder
    private var excludedFootnote: some View {
        ExcludedEntriesFootnote(count: excludedEntryCount,
                                identifier: "homeExcludedFootnote",
                                destination: excludedDestination)
            .id(HomeLogRevealAnchor.excludedFootnoteID)
    }

    /// The footnote's destination (hard rule 7): a single excluded entry opens
    /// its editor, several open the list that names all of them and why.
    private var excludedDestination: Route? {
        #if DEBUG
        // DEBUG-only seam: `-homeExcludedFootnotePassive` forces the footnote
        // into its passive-caption branch (no destination) while real excluded
        // entries exist, so the "a passive caption carries no affordance" check
        // has a live subject. No shipping caller renders the footnote passively;
        // compiled out of release.
        if ProcessInfo.processInfo.arguments.contains("-homeExcludedFootnotePassive") {
            return nil
        }
        #endif
        if excludedEntryIDs.count > 1 {
            return .excludedEntries
        }
        return excludedEntryIDs.first.map(Route.editEntry)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowCard(_ row: LogStream.Row) -> some View {
        switch row {
        case .entry(let entry):
            entryCard(entry)
        case .group(let group):
            groupCard(group)
        case .duplicate(let group):
            duplicateCard(group)
        }
    }

    // MARK: S2 combined duplicate card

    /// One physical fill logged twice (docs/SYNC.md S2): a single card showing
    /// BOTH members with their differences (rendered by `HomeDuplicateCard`).
    /// Until the user decides, only the counted member contributes to any
    /// figure - this row never changes what counts, only what is shown.
    private func duplicateCard(_ group: LogStream.DuplicateGroup) -> some View {
        HomeDuplicateCard(group: group, stations: stations,
                          volumeUnit: volumeUnit, distanceUnit: distanceUnit,
                          onKeepBoth: onKeepBoth, onMerge: onMerge)
    }

    // MARK: Entry card

    private func entryCard(_ entry: LogStream.LogEntry) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.editEntry(entry.id)) {
                HStack(spacing: 12) {
                    EntryKindMark(kind: entry.kind)
                    VStack(alignment: .leading, spacing: 1) {
                        titleLine(entry)
                        subtitleLine(entry)
                    }
                    Spacer(minLength: 8)
                    if let money = entry.money {
                        LogEntryAmount(money: money)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("logEntryButton")

            if entry.isConflicted {
                NavigationLink(value: Route.editEntry(entry.id)) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Palette.warn)
                        .padding(6)
                        .background(Circle().fill(Theme.Palette.warn.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("conflictBadgeButton")
            }
            if rejectedEntryIDs.contains(entry.id) {
                RejectedEntryBadge(entryID: entry.id)
            }
            if pendingInboxEntryIDs.contains(entry.id) {
                InboxEntryBadge(entryID: entry.id)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .formCard()
    }

    private func titleLine(_ entry: LogStream.LogEntry) -> some View {
        HStack(spacing: 5) {
            Text(EntryTitle.text(entry, stations: stations))
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
    /// be noise. Rendered through `SubtitleFlow`, which wraps the segments to a
    /// second line at Dynamic Type XL instead of clipping (P6.13).
    private func subtitleLine(_ entry: LogStream.LogEntry,
                              includeAttachment: Bool = true) -> some View {
        let segments = includeAttachment
            ? entry.subtitleSegments
            : entry.subtitleSegments.filter { segment in
                if case .attachment = segment { return false } else { return true }
            }
        return SubtitleFlow(spacing: 3, lineSpacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                // Each segment carries its own trailing "·" so a separator is
                // glued to the segment it follows and never starts a line.
                HStack(spacing: 3) {
                    segmentView(segment)
                    if index < segments.count - 1 {
                        Text("·")
                            .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.Palette.inkSoft)
    }

    @ViewBuilder
    private func segmentView(_ segment: LogStream.SubtitleSegment) -> some View {
        switch segment {
        case .quantity(.volumeL(let litres)):
            Text(VolumeDisplay.text(litres, unit: volumeUnit))
        case .quantity(.energyKWh(let kWh)):
            Text("\(ManualFillUpFormat.decimal(kWh, fractionDigits: 0)) \(L10n.kWh)")
        case .fuelKind(let kind):
            Text(kind.fuelKindLabel)
                .accessibilityIdentifier("logEntryFuelKind")
        case .odometer(let value):
            Text("\(OdometerFormat.grouped(value)) \(L10n.distanceUnit(distanceUnit))")
                .accessibilityIdentifier("logEntryOdometer")
        case .consumption(let per100):
            // RV.142: the segment this fill closes, the engine's own per100
            // figure - the view converts it to the car's unit (RV.296) and
            // never recomputes it (hard rule 2).
            let figure = ConsumptionDisplay.value(per100: per100, unit: vehicle.headlineUnit)
            Text("\(ManualFillUpFormat.decimal(figure, fractionDigits: 1)) \(consumptionUnitLabel)")
                .accessibilityIdentifier("logEntryConsumption")
        case .attachment:
            Image(systemName: "paperclip")
                .font(.caption2)
                .accessibilityLabel(L10n.localize("Has attachment"))
                .accessibilityIdentifier("logEntryAttachment")
        case .date(let date):
            Text(HomeFormat.day(date))
                .accessibilityIdentifier("logEntryDate")
        }
    }

    // MARK: Purchase group card

    /// One physical purchase from a single receipt (docs/SCHEMA.md CHECK 3).
    /// The group's trailing figure states the receipt total exactly as honestly
    /// as the month dividers do (RV.166); the fuel row inside it shows the FUEL
    /// amount - never the other way around (hard rule 4).
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
                    EntryKindMark(kind: group.members.first?.kind ?? .fuel)
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
                    groupTotalFigure(group)
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
        // Plural variations, not `String(format:)` - Russian has three forms
        // for a count, and `%d` substitution into a flat string cannot express
        // them (the same rule as `L10n.entriesExcluded`).
        String(localized: "\(group.members.count) items on this receipt")
    }

    private func groupTitle(_ group: LogStream.LogGroup) -> String {
        group.members.first.map { EntryTitle.text($0, stations: stations) }
            ?? L10n.localize("Purchase")
    }

    /// A member row inside an expanded group. The fuel member shows its FUEL
    /// amount, never the receipt's grand total (hard rule 4).
    private func groupMemberRow(_ member: LogStream.LogEntry) -> some View {
        NavigationLink(value: Route.editEntry(member.id)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    titleLine(member)
                    subtitleLine(member, includeAttachment: false)
                }
                Spacer(minLength: 8)
                if let money = member.money {
                    LogEntryAmount(money: money)
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

/// Shared by the log stream and the Recently deleted rows (P1.7): a fill's
/// kind name ("95", "Diesel", "Electricity") when no station name is available.
extension FuelKind {
    var fuelKindLabel: String {
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
