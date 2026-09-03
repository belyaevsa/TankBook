import SwiftUI
import TankbookCore

// MARK: - RV.38 the inbox screen (docs/JOURNEYS.md F4, amended)
//
// The list of work that finished after the user moved on. The first producer is
// the cloud-reading gateway: an answer that landed after the entry was saved
// becomes an item here, and the user decides - update from the receipt, leave
// it as it is (the default), or replace the receipt. The decision lives in core
// (`GatewayInboxPolicy`); this view only renders the ask and hands the answer
// to `AppInbox.resolve`.
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

// MARK: - One item and its three actions

private struct InboxItemCard: View {
    let item: GatewayInboxItem

    @Environment(AppInbox.self) private var inbox
    @Environment(AppToastCenter.self) private var toastCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            // The three actions, and their ORDER AND WEIGHT are the rule, not
            // decoration. "Leave it as it is" is the DEFAULT (hard rule 13, and
            // the same default RV.37's re-read ask already ships), so it comes
            // FIRST and carries the prominent treatment; the update is the
            // secondary, taken only on an explicit tap.
            //
            // The first draft had these inverted - the data-CHANGING action
            // wore the filled taillight and the safe one sat beneath it in an
            // outline. That is the app nudging the user to let it overwrite
            // what they already saved, which is precisely what rule 13 forbids,
            // and it is invisible to the L4 suite: the tests assert the actions
            // exist and that declining preserves every value, never which one
            // the eye is pulled to. Caught by opening the screenshot.
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

            Button {
                inbox.resolve(item, as: .update)
                toastCenter.noteEntryChanged()
            } label: {
                Text(L10n.inboxUpdateFromReceipt)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inboxUpdateButton")

            // "Replace the receipt" routes to the entry, where the receipt
            // lives (hard rule 8), and clears the item.
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
        .padding(Theme.Spacing.cardPadding)
        .formCard()
        // `.contain`, never `.combine`: the card must keep its three action
        // buttons as separate accessibility elements (an identifier on a
        // container otherwise collapses them into one leaf and the buttons stop
        // resolving - the same trap as the duplicate card's `.contain`).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inboxItemCard")
    }
}
