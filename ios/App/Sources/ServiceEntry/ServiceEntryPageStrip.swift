import SwiftUI
import TankbookCore

/// The scanned invoice's page strip (design/screens/ServiceEntry.dc.html): a
/// horizontal row of page thumbnails, each removable, with the "Page N of M"
/// counter and "+ add page" (the scanner re-opens). Removing a page deletes its
/// file - no orphan. Only present on the scanned path; the typed path (P3.1a)
/// shows no strip.
struct ServiceEntryPageStrip: View {
    let pages: [InvoicePage]
    @Binding var selectedIndex: Int
    let onAddPage: () -> Void
    let onRemovePage: (InvoicePage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        thumbnail(page, at: index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .accessibilityIdentifier("serviceEntryPageStrip")

            HStack(spacing: 8) {
                Text(L10n.pageOf(current: selectedIndex + 1, total: pages.count))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("serviceEntryPageCounter")
                Spacer(minLength: 8)
                addPageButton
            }
        }
    }

    private func thumbnail(_ page: InvoicePage, at index: Int) -> some View {
        let isSelected = index == selectedIndex
        return Image(uiImage: page.image)
            .resizable()
            .scaledToFill()
            .frame(width: 58, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Theme.Palette.taillight : Theme.Palette.hairline,
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    onRemovePage(page)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .background(Circle().fill(Theme.Palette.midnight.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove page")
                .accessibilityIdentifier("serviceEntryPageRemove_\(index)")
                .padding(3)
            }
            .onTapGesture {
                selectedIndex = index
            }
    }

    private var addPageButton: some View {
        Button(action: onAddPage) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                Text("Add page")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.dash))
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("serviceEntryAddPageButton")
    }
}
