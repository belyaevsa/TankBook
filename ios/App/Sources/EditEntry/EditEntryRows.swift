import SwiftUI
import TankbookCore

/// Rows shared by the fill-up and non-fill edit forms (P1.6). Static builders
/// so both `EditEntryView` and `EditEntryNonFillView` reuse the same surfaces
/// without forking a second copy of any card.
@MainActor
enum EditEntryRows {

    /// The artboard's receipt strip, RV.9's tappable version. Delegates to
    /// `ReceiptCardView`, which owns the chip-as-control and the viewer it
    /// presents; both `EditEntryView` and `EditEntryNonFillView` keep calling
    /// this one builder, so neither form forks a second copy of the card.
    static func receiptCard(attachments: [Attachment], entry: any Entry,
                            pendingBlobIDs: Set<UUID> = [],
                            onAddReceipt: (() -> Void)? = nil,
                            onAttachmentChanged: @escaping (FuelExtraction?) -> Void = { _ in }) -> some View {
        ReceiptCardView(attachments: attachments, entry: entry,
                        pendingBlobIDs: pendingBlobIDs, onAddReceipt: onAddReceipt,
                        onAttachmentChanged: onAttachmentChanged)
    }

    static func noteRow(text: Binding<String>, identifier: String) -> some View {
        EditNoteRow(text: text, identifier: identifier)
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

/// The shared Note row (P1.6) behind `EditEntryRows.noteRow`. RV.47: the whole
/// row is the tap target that focuses the field. A static builder shared by two
/// screens has no screen focus enum to hand out, so the row owns a private
/// focus state of its own - a field that has no siblings is the one case a
/// local enum is honest.
private enum EditNoteFocus: Hashable {
    case note
}

private struct EditNoteRow: View {
    let text: Binding<String>
    let identifier: String
    @FocusState private var focused: EditNoteFocus?

    var body: some View {
        FocusableFieldRow("Note", $focused, equals: .note,
                          rowIdentifier: "\(identifier)Row") {
            TextField("Add a note", text: text, axis: .vertical)
                .multilineTextAlignment(.trailing)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1 ... 3)
                .focused($focused, equals: .note)
                .accessibilityIdentifier(identifier)
        }
    }
}
