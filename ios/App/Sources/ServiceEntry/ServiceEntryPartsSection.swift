import SwiftUI
import TankbookCore

/// The ServiceEntry "Parts on your shelf" section (P3.2, docs/JOURNEYS.md J7b):
/// the install-link offer. Each on-shelf part renders as the artboard's Link
/// row - "Install oil filter from Mar 3?" with a headlight "Link" affordance -
/// and linked parts render below with an "Unlink" affordance. The link is
/// provenance, never a price: accepting it links, it does not re-price.
struct ServiceEntryPartsSection: View {
    let shelfParts: [Expense]
    let linkedParts: [Expense]
    let symbol: String
    let onLink: (Expense) -> Void
    let onUnlink: (Expense) -> Void
    let onViewShelf: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            if !shelfParts.isEmpty {
                sectionHeader
                ForEach(shelfParts, id: \.id) { part in
                    linkRow(part)
                }
            }
            if !linkedParts.isEmpty {
                linkedHeader
                ForEach(linkedParts, id: \.id) { part in
                    linkedRow(part)
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Parts on your shelf")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Button("View shelf", action: onViewShelf)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.headlight)
                .accessibilityIdentifier("serviceEntryViewShelfButton")
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private var linkedHeader: some View {
        HStack {
            Text("Linked")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private func linkRow(_ part: Expense) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(L10n.installPart(title: part.title, day: HomeFormat.day(part.date)))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Link") { onLink(part) }
                .buttonStyle(.plain)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Palette.headlight)
                .accessibilityIdentifier("serviceEntryLinkPartButton")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .formCard()
    }

    private func linkedRow(_ part: Expense) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.taillight)
            VStack(alignment: .leading, spacing: 1) {
                Text(part.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(HomeFormat.entryAmount(part.money?.amount ?? 0, symbol: symbol))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 8)
            Button("Unlink") { onUnlink(part) }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("serviceEntryUnlinkPartButton")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .formCard()
    }
}
