import SwiftUI
import TankbookCore

// MARK: - RV.38 the inbox screen (docs/JOURNEYS.md F4, amended); RV.45 the
// per-field ask (amended 2026-09-04).
//
// The list of work that finished after the user moved on. The first producer is
// the cloud-reading gateway: an answer that landed after the entry was saved
// becomes an item here, and the user decides per FIELD what to take. RV.45
// replaced the blank-fields-only "update" (a guaranteed no-op on the commonest
// item, the disagreement) with a comparison: every field the receipt read that
// differs from or fills what the user saved is shown as "yours vs the receipt",
// and the user ticks per field what to take. A field that agrees is not shown
// (agreement is not a decision), and a card with nothing to change says so and
// offers no update. "Leave it as it is" remains the default while nothing is
// ticked (hard rule 13); RV.64 (2026-09-05) made the WEIGHT follow the state -
// once a field is ticked the update takes the prominent filled treatment and
// leave-as-is dims, with the ORDER never changing.
//
// Hard rule 8: the inbox is a SECOND route to the entry, never the only place a
// problem is visible - the entry keeps its own badge (the Log's
// `inboxEntryBadge`), and this list routes to the entry, never resolves
// centrally while the entry shows nothing.

struct InboxView: View {
    @Environment(AppInbox.self) private var inbox
    @Environment(AppToastCenter.self) private var toastCenter

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if inbox.items.isEmpty {
                    emptyState
                } else {
                    ForEach(inbox.items) { item in
                        InboxItemCard(item: item)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.Palette.midnight)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(L10n.inboxEmpty)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("inboxEmptyState")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .formCard()
    }
}

// MARK: - One item, its comparison, and its actions

private struct InboxItemCard: View {
    let item: GatewayInboxItem

    @Environment(AppInbox.self) private var inbox
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var ticked: Set<FieldRef>

    init(item: GatewayInboxItem) {
        self.item = item
        // RV.64 screenshot seam: `-inboxScreenshotTick` pre-ticks the offered
        // volume field so a simctl launch (which cannot tap) can shoot the
        // ticked state - the whole point of the row is which button is loud.
        _ticked = State(initialValue: Self.screenshotTicks())
    }

    /// The DEBUG-only launch-argument pre-tick; empty in every real session and
    /// in the L4 suite, which drives the tick buttons by tap.
    private static func screenshotTicks() -> Set<FieldRef> {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-inboxScreenshotTick") {
            return [.volume]
        }
        #endif
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let entry = inbox.fillUp(for: item) {
                let offers = GatewayInboxPolicy.offers(extraction: item.extraction, entry: entry)
                if offers.isEmpty {
                    nothingToChange
                    leaveAsIsAction
                    useDifferentReceiptLink
                } else {
                    comparisonTable(entry: entry, offers: offers)
                    actions
                }
            } else {
                entryGone
                leaveAsIsAction
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inboxItemCard")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.warn)
                Text(L10n.inboxReceiptReady)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            Text(L10n.inboxFinishedAfterSave)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    // MARK: The comparison table (yours vs the receipt)

    private func comparisonTable(entry: FillUp, offers: [GatewayInboxPolicy.FieldOffer]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Color.clear.frame(width: 20, height: 1)
                Text(L10n.inboxYouEntered)
                    .columnHeader()
                    .gridColumnAlignment(.trailing)
                Text(L10n.inboxReceiptColumn)
                    .columnHeader()
                    .gridColumnAlignment(.trailing)
                Color.clear.frame(width: 24, height: 1)
            }
            ForEach(offers) { offer in
                GridRow {
                    fieldCell(offer)
                    Text(InboxValueFormat.yours(offer.field, entry: entry))
                        .valueStyle(emphasis: .muted)
                        .gridColumnAlignment(.trailing)
                    Text(InboxValueFormat.receipt(offer.field, entry: entry, extraction: item.extraction))
                        .valueStyle(emphasis: offer.disposition == .differs ? .attention : .normal)
                        .gridColumnAlignment(.trailing)
                    tickButton(offer)
                }
            }
        }
    }

    private func fieldCell(_ offer: GatewayInboxPolicy.FieldOffer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(InboxValueFormat.label(offer.field))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text(verb(for: offer))
                .font(.caption2)
                .foregroundStyle(offer.disposition == .differs ? Theme.Palette.warn : Theme.Palette.inkSoft)
        }
        .gridColumnAlignment(.leading)
    }

    private func tickButton(_ offer: GatewayInboxPolicy.FieldOffer) -> some View {
        let isOn = ticked.contains(offer.field)
        return Button {
            if isOn { ticked.remove(offer.field) } else { ticked.insert(offer.field) }
        } label: {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isOn ? Theme.Palette.taillight : Theme.Palette.inkSoft)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(verb(for: offer))
        .accessibilityValue(isOn ? "selected" : "unselected")
        .accessibilityIdentifier(Self.tickID(offer.field))
    }

    private func verb(for offer: GatewayInboxPolicy.FieldOffer) -> String {
        switch offer.disposition {
        case .differs: return L10n.inboxReplaces
        case .fillsBlank: return L10n.inboxFills
        }
    }

    static func tickID(_ field: FieldRef) -> String {
        switch field {
        case .date: return "inboxTick_date"
        case .fuelKind: return "inboxTick_fuelKind"
        case .volume: return "inboxTick_volume"
        case .unitPrice: return "inboxTick_unitPrice"
        case .total: return "inboxTick_total"
        case .currency: return "inboxTick_currency"
        default: return "inboxTick_other"
        }
    }

    // MARK: States with nothing to decide

    private var nothingToChange: some View {
        Text(L10n.inboxNothingToChange)
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.inkSoft)
            .accessibilityIdentifier("inboxNothingToChange")
    }

    private var entryGone: some View {
        Text(L10n.inboxEntryGone)
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.inkSoft)
            .accessibilityIdentifier("inboxEntryGone")
    }

    // MARK: The actions - ORDER never changes; WEIGHT follows the ticks (RV.64)

    /// The two acts keep their ORDER (a button moving under a finger already in
    /// motion is its own hazard) but the WEIGHT follows the state, and the rule
    /// is not the same in both states. While NOTHING is ticked, "leave it as it
    /// is" is the right default (hard rule 13 - the app suggests, the user
    /// decides, and the suggestion while nothing is decided is that the entry
    /// stays untouched), so it comes FIRST and carries the prominent filled
    /// treatment. A ticked field IS the user deciding, and the loudest control
    /// must then be the act that HONOURS those ticks - the update - not the act
    /// that throws them away: leave-as-is dims to the secondary treatment. That
    /// is hard rule 8 as much as rule 13 - the ticks are user work, and a
    /// prominent control that discards them with no confirmation and no undo is
    /// "lost silently". The prominence decision lives in core
    /// (`GatewayInboxPolicy.recommendedAction`, RV.64), in ONE place, so the two
    /// buttons cannot drift apart.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            leaveAsIsAction
            updateAction
            useDifferentReceiptLink
        }
    }

    /// The single decision both action buttons read: which act is prominent.
    /// Derived from the tick count in core, never restated here.
    private var recommendedAction: GatewayInboxPolicy.RecommendedInboxAction {
        GatewayInboxPolicy.recommendedAction(tickedCount: ticked.count)
    }

    private var leaveAsIsAction: some View {
        cardActionButton(
            title: L10n.inboxLeaveAsIs,
            isProminent: recommendedAction == .leaveAsIs,
            enabled: true,
            identifier: "inboxLeaveButton"
        ) {
            inbox.resolve(item, as: .leaveAsIs)
        }
    }

    private var updateAction: some View {
        cardActionButton(
            title: L10n.inboxUpdateFromReceipt,
            isProminent: recommendedAction == .update,
            enabled: !ticked.isEmpty,
            identifier: "inboxUpdateButton"
        ) {
            inbox.resolve(item, as: .update(fields: ticked))
            toastCenter.noteEntryChanged()
        }
    }

    /// ONE treatment for both acts, so "prominent" and "secondary" are defined
    /// in exactly one place (RV.64). Prominent = filled `taillight` with bold
    /// `midnight` text (docs/DESIGN.md P6.19: text on an accent fill is
    /// `midnight`, never white). Secondary = `dash` + hairline stroke with `ink`
    /// text - `inkSoft` while the act is a disabled no-op. The accessible VALUE
    /// carries the treatment ("primary" / "secondary") so the L4 suite can
    /// assert WHICH act is loud, never a colour literal and never mere presence.
    private func cardActionButton(title: String,
                                  isProminent: Bool,
                                  enabled: Bool,
                                  identifier: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(isProminent ? .bold : .semibold))
                .foregroundStyle(actionTextColor(isProminent: isProminent, enabled: enabled))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isProminent ? Theme.Palette.taillight : Theme.Palette.dash)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay {
                    if !isProminent {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .stroke(Theme.Palette.hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isProminent ? "primary" : "secondary")
    }

    private func actionTextColor(isProminent: Bool, enabled: Bool) -> Color {
        if isProminent { return Theme.Palette.midnight }
        return enabled ? Theme.Palette.ink : Theme.Palette.inkSoft
    }

    private var useDifferentReceiptLink: some View {
        NavigationLink(value: Route.editEntry(item.entryId)) {
            Text(L10n.inboxUseDifferentReceipt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            inbox.resolve(item, as: .replaceReceipt)
        })
        .accessibilityIdentifier("inboxReplaceButton")
    }
}

// MARK: - Value and header text styles

private extension Text {
    /// A column header: caption, uppercase-feel, subdued.
    func columnHeader() -> some View {
        self.font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
    }

    /// A comparison value: DIN numerals, right-aligned by the grid column.
    /// `emphasis` colours the receipt's differing value amber (attention only)
    /// and leaves a blank fill in ink.
    func valueStyle(emphasis: InboxValueEmphasis) -> some View {
        self.font(.custom(AppFonts.dinAlternateBold, size: 16))
            .foregroundStyle(emphasis.color)
    }
}

private enum InboxValueEmphasis {
    case muted
    case normal
    case attention

    var color: Color {
        switch self {
        case .muted: return Theme.Palette.inkSoft
        case .normal: return Theme.Palette.ink
        case .attention: return Theme.Palette.warn
        }
    }
}
