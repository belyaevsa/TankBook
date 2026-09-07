import SwiftUI
import TankbookCore

// RV.104: Edit entry's stored-acceptance strip, split out of EditEntryView.swift
// so that file stays under the 700-line lint ceiling - the same reason
// EditEntryView+EntryResolution.swift exists. The acceptance is the user's
// recorded judgement that a timeline flag is fine (docs/SCHEMA.md -> Validation);
// showing it here, with Undo, is what keeps it from being a silent hole in the
// data (hard rule 8).

extension EditEntryView {

    // MARK: - RV.104 the stored acceptance (visible + reversible)

    /// The "Marked as fine" strip above the form. The acceptance is a fact the
    /// user deliberately recorded (RV.104); showing it here is what keeps it
    /// from being a silent hole in the data (hard rule 8). The row names the
    /// reason when one was given, and Undo clears the acceptance - the timeline
    /// validator then re-derives the flag from the entries alone, so a still-
    /// broken entry is flagged again immediately.
    func acceptedBanner(_ acceptance: FlagAcceptance) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Marked as fine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(acceptance.reason
                        ?? L10n.localize("Editing the odometer or date will re-check it."))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Undo", action: undoAcceptance)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("flagAcceptUndoButton")
        }
        .padding(12)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flagAcceptanceBanner")
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    func undoAcceptance() {
        guard let entry = currentEntry else { return }
        do {
            let repository = try AppStore.repository()
            if try repository.undoFlagAcceptance(id: entry.id) {
                toastCenter.noteEntryChanged()
                Task { await reloadData() }
            }
        } catch {
            AppLog.error(operation: "editEntry.undoFlagAcceptance", category: .ui, error: error)
        }
    }
}
