import SwiftUI
import TankbookCore

/// The Edit-entry receipt strip (P4.6, made tappable by RV.9). The chip was
/// decorative - the photo the entry exists to evidence could only be squinted
/// at in 44x56 points. It is now a control: tapping it opens
/// `AttachmentViewerView` full-size over the entry, and the entry underneath is
/// untouched and still editable when the viewer closes (hard rule 1).
///
/// The empty state is unchanged: a `doc.text` placeholder and, when the caller
/// hands an `onAddReceipt` closure, the PJ.48 "Add receipt" affordance.
///
/// RV.331: an entry holds as many pages as the user gave it - the back of a
/// receipt, a second invoice page, the parts bill. Every page is a chip, each
/// opens the viewer on itself and the viewer steps between them; pages added
/// in this edit (`heldPages`) sit after them until Save writes them; and
/// "Add page" stays offered once the entry has a photo.
struct ReceiptCardView: View {
    let attachments: [Attachment]
    let entry: any Entry
    let pendingBlobIDs: Set<UUID>
    let onAddReceipt: (() -> Void)?
    let onAttachmentChanged: (FuelExtraction?) -> Void
    /// The owning car's volume unit, threaded to the viewer's recognised page
    /// (RV.234).
    var volumeUnit: VolumeUnit = .l
    /// Pages added in this edit, written when Save runs.
    var heldPages: [UIImage] = []
    /// A held page's reading is still running.
    var processing = false

    @State private var viewerPage: ViewerPage?

    private struct ViewerPage: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var first: Attachment? { attachments.first }

    var body: some View {
        HStack(spacing: 12) {
            if attachments.isEmpty, heldPages.isEmpty {
                emptyChip
            } else {
                chips
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt photo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                if let caption = Self.scannedLine(attachments: attachments, entry: entry) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
            if processing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.Palette.inkSoft)
            } else if let onAddReceipt {
                let empty = attachments.isEmpty && heldPages.isEmpty
                Button(action: onAddReceipt) {
                    Text(empty ? "Add receipt" : "Add page")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(empty ? "editAddReceiptButton" : "editAddPageButton")
            }
        }
        .padding(12)
        .formCard()
        // While pages are held for Save the card says whether their reading
        // has settled, so a UI test can wait before saving.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(heldPages.isEmpty ? "editReceiptCard"
                                 : processing ? "editAttachProcessing" : "editAttachReady")
        .onAppear {
            #if DEBUG
            // Screenshot seam: `simctl` can launch and shoot, but it cannot tap,
            // so the committed viewer screenshots need a way in that is not a
            // gesture. DEBUG-only, and it opens the same sheet the chip opens.
            if ProcessInfo.processInfo.arguments.contains("-openAttachmentViewer")
                || ProcessInfo.processInfo.arguments.contains("-openAttachmentViewerRecognised"),
               !attachments.isEmpty {
                viewerPage = ViewerPage(index: 0)
            }
            #endif
        }
        .sheet(item: $viewerPage) { page in
            AttachmentPagesViewer(attachments: attachments, index: page.index, entry: entry,
                                  volumeUnit: volumeUnit, onAttachmentChanged: onAttachmentChanged)
        }
    }

    /// Every saved page, then the pages held for Save (marked, not openable -
    /// they have no attachment row yet).
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    chipButton(attachment, at: index)
                }
                ForEach(Array(heldPages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.Palette.hairline, lineWidth: 1))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.taillight)
                                .padding(2)
                                .opacity(processing ? 0 : 1)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(Text("Receipt attached"))
                        .accessibilityIdentifier("editHeldPage_\(index)")
                }
            }
        }
        .frame(maxWidth: CGFloat(attachments.count + heldPages.count) * 50)
    }

    /// The chip, now a real control. The identifiers that used to sit on the
    /// decorative chip live on the button, so "the receipt chip" a UI test
    /// queries is the thing the user can actually hit - `isHittable`, not just
    /// present in the hierarchy.
    private func chipButton(_ attachment: Attachment, at index: Int) -> some View {
        let syncing = AttachmentPhotoChip.isSyncing(attachment,
                                                    blobAvailable: !pendingBlobIDs.contains(attachment.id))
        return Button {
            viewerPage = ViewerPage(index: index)
        } label: {
            AttachmentPhotoChip(attachment: attachment,
                                blobAvailable: !pendingBlobIDs.contains(attachment.id))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(syncing ? Text("Photo syncing") : Text("Receipt photo"))
        .accessibilityHint(Text("Opens the receipt full size"))
        .accessibilityIdentifier(syncing ? "attachmentPhotoSyncing"
                                         : index == 0 ? "attachmentPhotoChip" : "attachmentPhotoChip_\(index)")
    }

    private var emptyChip: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.Palette.dash)
            .frame(width: 44, height: 56)
            .overlay(
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            )
    }

    /// The strip's caption line: "Captured <instant>" for a scanned photo,
    /// "Added <date>" for one attached without a recognition pass. Nil with no
    /// attachment - the empty state's "Add receipt" affordance is the whole
    /// message there.
    ///
    /// Both halves obey one rule (`docs/DESIGN.md` -> Typography): **format at
    /// the precision the value has.** `createdAt` is a real instant, so it
    /// carries a time; `entry.date` is a day, so it does not. The caption
    /// deliberately does NOT read `extractedTimestamp` - that is the date
    /// PRINTED ON the receipt, a date-only fact, and rendering it with a time
    /// produced "Scanned 9 Sep at 00:00" on every scan. The receipt's own
    /// printed date belongs in the recognised-fields list, where it is shown as
    /// a date.
    static func scannedLine(attachments: [Attachment], entry: any Entry) -> String? {
        guard let first = attachments.first else { return nil }
        guard first.extractedTimestamp != nil else {
            return String(format: L10n.localize("Added %@"),
                          entry.date.formatted(.dateTime.month(.abbreviated).day()))
        }
        let stamp = first.createdAt.formatted(
            .dateTime.month(.abbreviated).day().hour().minute())
        return String(format: L10n.localize("Captured %@"), stamp)
    }
}

/// The viewer over an entry's pages (RV.331): the page on screen is one
/// `AttachmentViewerView`, rebuilt for each page so its load, share, delete
/// and replace act on that page alone; "‹ ›" in its toolbar step between them.
struct AttachmentPagesViewer: View {
    let attachments: [Attachment]
    @State var index: Int
    let entry: any Entry
    var volumeUnit: VolumeUnit = .l
    var onAttachmentChanged: (FuelExtraction?) -> Void = { _ in }

    var body: some View {
        let page = attachments[min(index, attachments.count - 1)]
        AttachmentViewerView(attachment: page, entry: entry, volumeUnit: volumeUnit,
                             onAttachmentChanged: onAttachmentChanged,
                             paging: attachments.count > 1
                                ? AttachmentViewerPaging(index: index, count: attachments.count,
                                                         onMove: { index = $0 })
                                : nil)
            .id(page.id)
    }
}

/// Where the viewer is among the entry's pages, and how to move.
struct AttachmentViewerPaging {
    let index: Int
    let count: Int
    let onMove: (Int) -> Void
}
