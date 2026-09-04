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
// offers no update. "Leave it as it is" remains the default (hard rule 13).
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
    @State private var ticked: Set<FieldRef> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let entry = inbox.fillUp(for: item) {
                let offers = GatewayInboxPolicy.offers(extraction: item.extraction, entry: entry)
                if offers.isEmpty {
                    nothingToChange
                    leaveAsIsAction
                    replaceReceiptLink
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

    // MARK: The actions - ORDER AND WEIGHT are the rule, not decoration

    /// "Leave it as it is" is the DEFAULT (hard rule 13), so it comes FIRST and
    /// carries the prominent filled treatment; the update is the secondary,
    /// taken only on an explicit tap - and only when at least one field is
    /// ticked (a disabled update names its own no-op).
    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            leaveAsIsAction
            updateAction
            replaceReceiptLink
        }
    }

    private var leaveAsIsAction: some View {
        Button {
            inbox.resolve(item, as: .leaveAsIs)
        } label: {
            Text(L10n.inboxLeaveAsIs)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.Palette.midnight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.Palette.taillight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inboxLeaveButton")
    }

    private var updateAction: some View {
        Button {
            inbox.resolve(item, as: .update(fields: ticked))
            toastCenter.noteEntryChanged()
        } label: {
            Text(L10n.inboxUpdateFromReceipt)
                .font(.body.weight(.semibold))
                .foregroundStyle(ticked.isEmpty ? Theme.Palette.inkSoft : Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.Palette.dash)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(ticked.isEmpty)
        .accessibilityIdentifier("inboxUpdateButton")
    }

    private var replaceReceiptLink: some View {
        NavigationLink(value: Route.editEntry(item.entryId)) {
            Text(L10n.inboxReplaceReceipt)
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
