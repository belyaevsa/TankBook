import SwiftUI
import TankbookCore

/// The scanned invoice's page strip (design/screens/ServiceEntry.dc.html): a
/// horizontal row of page thumbnails, each removable, with the "Page N of M"
/// counter and "+ add page" (the scanner re-opens, or a page is chosen from
/// Photos - an invoice that is already an image). Removing a page deletes its
/// file - no orphan. Only present on the scanned path; the typed path (P3.1a)
/// shows no strip.
struct ServiceEntryPageStrip: View {
    let pages: [InvoicePage]
    @Binding var selectedIndex: Int
    let onAddPage: () -> Void
    let onAddPageFromPhotos: () -> Void
    let onRemovePage: (InvoicePage) -> Void
    /// A page opened full size (`PagePhotoViewer`).
    var onOpenPage: (Int) -> Void = { _ in }

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
        // The page and its remove control are two sibling buttons: an
        // identifier on a view with an overlay also lands on the overlay's
        // button, and a tap meant to open the page could remove it.
        return ZStack(alignment: .topTrailing) {
            Button {
                selectedIndex = index
                onOpenPage(index)
            } label: {
                Image(uiImage: page.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isSelected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.pageOf(current: index + 1, total: pages.count)))
            .accessibilityIdentifier("serviceEntryPage_\(index)")
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
    }

    private var addPageButton: some View {
        AddPageMenu(label: "Add page", identifier: "serviceEntryAddPage",
                    onScan: onAddPage, onPhotos: onAddPageFromPhotos)
    }
}

/// "Add page" / "Add invoice" / "Add receipt": the scanner or a photo already in
/// Photos, side by side (hard rule 15's two doors for a page). The service
/// form's strip, its typed-path invoice door and the expense form all use it.
struct AddPageMenu: View {
    let label: LocalizedStringKey
    let identifier: String
    let onScan: () -> Void
    let onPhotos: () -> Void

    var body: some View {
        Menu {
            Button(action: onScan) {
                Label("Scan a page", systemImage: "doc.viewfinder")
            }
            .accessibilityIdentifier(identifier + "Scan")
            Button(action: onPhotos) {
                Label("Choose from Photos", systemImage: "photo")
            }
            .accessibilityIdentifier(identifier + "Photos")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.dash))
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier + "Button")
    }
}
