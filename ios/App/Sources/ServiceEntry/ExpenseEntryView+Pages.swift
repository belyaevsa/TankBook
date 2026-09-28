import SwiftUI
import TankbookCore
import UIKit

// RV.333: the expense form shows the receipt it was scanned from and takes one
// more page - the second half of a long shop receipt, the back of a parts bill
// - from the scanner or from Photos, on the scanned and the typed form alike.
// Every page is written as an attachment when Save runs (`writeExpense`).

extension ExpenseEntryView {
    /// The scanned photo (when there is one), then the pages added here.
    var shownPages: [UIImage] {
        (scanImage.map { [$0] } ?? []) + extraPages
    }

    /// The page strip: each page opens full size; a page added here can be
    /// removed again (the scanned one is the capture - a re-take is its door).
    var pagesCard: some View {
        HStack(spacing: 12) {
            if shownPages.isEmpty {
                Image(systemName: "doc.text")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text("Receipt photo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(shownPages.enumerated()), id: \.offset) { index, image in
                            pageThumbnail(image, at: index)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            AddPageMenu(label: shownPages.isEmpty ? "Add receipt" : "Add page",
                        identifier: "expenseEntryAddPage",
                        onScan: { showPageCamera = true }, onPhotos: addPageFromPhotos)
        }
        .padding(12)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("expenseEntryPagesCard")
    }

    private func pageThumbnail(_ image: UIImage, at index: Int) -> some View {
        let isExtra = index >= shownPages.count - extraPages.count
        // Sibling buttons, as in the service strip: the page opens, the × removes.
        return ZStack(alignment: .topTrailing) {
            Button {
                pageViewer = PageViewerTarget(index: index)
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.pageOf(current: index + 1, total: shownPages.count)))
            .accessibilityIdentifier("expenseEntryPage_\(index)")
            if isExtra {
                Button {
                    extraPages.remove(at: index - (shownPages.count - extraPages.count))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .background(Circle().fill(Theme.Palette.midnight.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove page"))
                .accessibilityIdentifier("expenseEntryPageRemove_\(index)")
                .padding(2)
            }
        }
    }

    /// The Photos door. Under the `-attachReceiptFixtureImage` test double
    /// (`ReceiptAttachFixture`) the fixture is the pick - the out-of-process
    /// picker cannot be driven; production never passes the argument.
    func addPageFromPhotos() {
        if let fixture = ReceiptAttachFixture.image() {
            extraPages.append(fixture)
        } else {
            showPagePicker = true
        }
    }
}

/// The expense form's page sheets: the scanner, the Photos picker and the
/// full-size page viewer.
struct ExpensePageSheets: ViewModifier {
    @Binding var extraPages: [UIImage]
    @Binding var showCamera: Bool
    @Binding var showPicker: Bool
    @Binding var viewer: PageViewerTarget?
    let pages: [UIImage]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showCamera) {
                DocumentCamera(onCancel: { showCamera = false },
                               onResult: { images in
                                   showCamera = false
                                   extraPages.append(contentsOf: images)
                               })
            }
            .sheet(isPresented: $showPicker) {
                PhotoPickerView(isPresented: $showPicker) { image in
                    if let image { extraPages.append(image) }
                }
            }
            .sheet(item: $viewer) { target in
                PagePhotoViewer(images: pages, index: target.index)
            }
    }
}
