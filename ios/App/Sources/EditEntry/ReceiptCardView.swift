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
struct ReceiptCardView: View {
    let attachments: [Attachment]
    let entry: any Entry
    let pendingBlobIDs: Set<UUID>
    let onAddReceipt: (() -> Void)?

    @State private var showViewer = false

    private var first: Attachment? { attachments.first }

    var body: some View {
        HStack(spacing: 12) {
            if let first {
                chipButton(first)
            } else {
                emptyChip
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
            if attachments.isEmpty, let onAddReceipt {
                Button(action: onAddReceipt) {
                    Text("Add receipt")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editAddReceiptButton")
            }
        }
        .padding(12)
        .formCard()
        .onAppear {
            #if DEBUG
            // Screenshot seam: `simctl` can launch and shoot, but it cannot tap,
            // so the committed viewer screenshots need a way in that is not a
            // gesture. DEBUG-only, and it opens the same sheet the chip opens.
            if ProcessInfo.processInfo.arguments.contains("-openAttachmentViewer")
                || ProcessInfo.processInfo.arguments.contains("-openAttachmentViewerRecognised") {
                showViewer = true
            }
            #endif
        }
        .sheet(isPresented: $showViewer) {
            if let first {
                AttachmentViewerView(attachment: first)
            }
        }
    }

    /// The chip, now a real control. The identifiers that used to sit on the
    /// decorative chip live on the button, so "the receipt chip" a UI test
    /// queries is the thing the user can actually hit - `isHittable`, not just
    /// present in the hierarchy.
    private func chipButton(_ attachment: Attachment) -> some View {
        let syncing = AttachmentPhotoChip.isSyncing(attachment,
                                                    blobAvailable: !pendingBlobIDs.contains(attachment.id))
        return Button {
            showViewer = true
        } label: {
            AttachmentPhotoChip(attachment: attachment,
                                blobAvailable: !pendingBlobIDs.contains(attachment.id))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(syncing ? Text("Photo syncing") : Text("Receipt photo"))
        .accessibilityHint(Text("Opens the receipt full size"))
        .accessibilityIdentifier(syncing ? "attachmentPhotoSyncing" : "attachmentPhotoChip")
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

    /// The strip's caption line: "Scanned <timestamp>" when the photo carries an
    /// extraction timestamp, "Added <date>" otherwise. Nil with no attachment -
    /// the empty state's "Add receipt" affordance is the whole message there.
    static func scannedLine(attachments: [Attachment], entry: any Entry) -> String? {
        guard let first = attachments.first else { return nil }
        guard let timestamp = first.extractedTimestamp else {
            return String(format: L10n.localize("Added %@"),
                          entry.date.formatted(.dateTime.month(.abbreviated).day()))
        }
        let stamp = timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return String(format: L10n.localize("Scanned %@"), stamp)
    }
}
