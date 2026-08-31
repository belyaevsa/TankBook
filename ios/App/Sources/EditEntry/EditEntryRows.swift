import SwiftUI
import TankbookCore

/// Rows shared by the fill-up and non-fill edit forms (P1.6). Static builders
/// so both `EditEntryView` and `EditEntryNonFillView` reuse the same surfaces
/// without forking a second copy of any card.
@MainActor
enum EditEntryRows {

    /// The artboard's receipt strip. The first attachment renders as a photo
    /// chip from its inline thumbnail (zero blob fetches); while the full
    /// rendition blob is still syncing, the chip shimmers - the entry stays
    /// openable and editable throughout (hard rule 1). With no attachment the
    /// strip shows the empty state (a `doc.text` placeholder) and, when the
    /// caller hands an `onAddReceipt` closure, the "Add receipt" affordance -
    /// the PJ.48 door that lets a typed entry carry its paper after the fact.
    static func receiptCard(attachments: [Attachment], entry: any Entry,
                            pendingBlobIDs: Set<UUID> = [],
                            onAddReceipt: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            if let first = attachments.first {
                AttachmentPhotoChip(
                    attachment: first,
                    blobAvailable: !pendingBlobIDs.contains(first.id)
                )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Palette.dash)
                    .frame(width: 44, height: 56)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt photo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                if let caption = scannedLine(attachments: attachments, entry: entry) {
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
    }

    /// The strip's caption line: "Scanned <timestamp>" when the photo carries an
    /// extraction timestamp, "Added <date>" otherwise. Nil with no attachment -
    /// the empty state's "Add receipt" affordance is the whole message there.
    private static func scannedLine(attachments: [Attachment], entry: any Entry) -> String? {
        guard let first = attachments.first else { return nil }
        guard let timestamp = first.extractedTimestamp else {
            return String(format: L10n.localize("Added %@"),
                          entry.date.formatted(.dateTime.month(.abbreviated).day()))
        }
        let stamp = timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return String(format: L10n.localize("Scanned %@"), stamp)
    }

    static func noteRow(text: Binding<String>, identifier: String) -> some View {
        FieldRow("Note") {
            TextField("Add a note", text: text, axis: .vertical)
                .multilineTextAlignment(.trailing)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1 ... 3)
                .accessibilityIdentifier(identifier)
        }
        .formCard()
    }

    /// The S1 sync state (docs/ERRORS.md -> Edit entry, row 2), built from the
    /// real `syncOverwrite` log (PR.14): the device whose version won, the
    /// moment the local edit lost, and the "Restore my version" action that
    /// round-trips the losing version back (hard rule 8 - the badge lives where
    /// the data lives). `deviceName` is runtime data (docs/LOCALIZATION.md) and
    /// nil when the transport did not attribute the overwrite, in which case the
    /// row names only the date - never an invented device.
    static func changedBySyncRow(deviceName: String?, replacedAt: Date,
                                 onRestore: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(Self.changedBySyncText(deviceName: deviceName, replacedAt: replacedAt))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Button("Restore my version", action: onRestore)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("editSyncRestoreButton")
        }
        .padding(12)
        .background(Theme.Palette.dash.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editChangedBySyncRow")
    }

    /// "Changed by sync · <device>, <date>" with a device, "Changed by sync ·
    /// <date>" without one. The device name is runtime data sharing a sentence
    /// behind a separator, so no case governs it (docs/LOCALIZATION.md); the
    /// date is app-formatted and never declines.
    private static func changedBySyncText(deviceName: String?, replacedAt: Date) -> String {
        let stamp = replacedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        if let deviceName {
            return String(format: L10n.localize("Changed by sync · %@, %@"), deviceName, stamp)
        }
        return String(format: L10n.localize("Changed by sync · %@"), stamp)
    }

    static var footer: some View {
        Text("Edits recalculate consumption for this and the next fill-up.")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .accessibilityIdentifier("editRecalcFooter")
    }

    /// The honest empty state when the entry cannot be loaded: no fabricated
    /// fields, just the next step (it may have been deleted on another device).
    static var entryNotFound: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Entry not found")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("It may have been deleted on another device.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }
}
