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
    /// openable and editable throughout (hard rule 1).
    static func receiptCard(attachments: [Attachment], entry: any Entry,
                            pendingBlobIDs: Set<UUID> = []) -> some View {
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
                Text(scannedLine(attachments: attachments, entry: entry))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .formCard()
    }

    private static func scannedLine(attachments: [Attachment], entry: any Entry) -> String {
        guard let timestamp = attachments.first?.extractedTimestamp else {
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

    /// The S1 sync state (docs/ERRORS.md -> Edit entry, row 2). Fixture-driven
    /// until sync lands (P4): there is no real "changed by sync" data yet, so
    /// the row renders under `-forceChangedBySync` and "Restore my version" is
    /// presentational.
    static var changedBySyncRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(String(format: L10n.localize("Changed by sync · %@, %@"), "iPad", "Aug 21"))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Button("Restore my version") {}
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
        .accessibilityIdentifier("editChangedBySyncRow")
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
