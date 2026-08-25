import SwiftUI
import TankbookCore

/// The ReminderComplete sheet (P3.5) - design/screens/ReminderComplete.dc.html,
/// docs/JOURNEYS.md J7c. A bottom sheet over the Reminders list: what was
/// completed ("Oil change – done", "Completed today at 119 486 km"), the
/// "Log the cost?" prompt with **Type amount** and **Skip – just mark done**,
/// the next-cycle line when recurrence is set, and the secondary actions.
///
/// Two doors (hard rule 15): Type amount opens the entry pre-filled; Skip
/// declines the cost log - `.done(nil)`, completion never forces bookkeeping.
/// The next occurrence, when recurrence is set, is anchored at the COMPLETION
/// date/odometer (never the original due - no drift), so the line previews what
/// `ReminderLifecycle.complete` will persist.
struct ReminderCompleteSheet: View {
    let reminder: Reminder
    let currentOdometer: Int?

    /// Dismiss this sheet and edit the reminder (Edit / Reschedule instead).
    var onEdit: () -> Void
    /// Dismiss this sheet and delete the reminder (with confirmation).
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderCompletionSession.self) private var completionSession

    /// The entry sheet opened by "Type amount" (nested over this one).
    @State private var entrySheet: SheetRoute?

    /// The completion moment: "now" - the sheet always completes the reminder
    /// as of the tap, so the next cycle counts from today, not the old due.
    private var completionDate: Date { Date() }

    /// The next occurrence this completion would create (preview only - it is
    /// not persisted until the user skips or saves). Used for the next-cycle
    /// line; `complete` is pure, so computing it twice changes nothing.
    private var previewNext: Reminder? {
        ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: completionDate,
            completionOdometer: currentOdometer).nextOccurrence
    }

    private var entryKind: ReminderCompletion.EntryKind {
        ReminderCompletion.entryKind(for: reminder.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dragHandle
            header
            logTheCostCard
            if let previewNext {
                nextCycleCard(previewNext)
            }
            secondaryActions
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(Theme.Palette.dash)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.Palette.dash)
        .sheet(item: $entrySheet) { route in
            SheetDestinationView(route: route)
        }
        .onChange(of: entrySheet) { _, newValue in
            // The entry sheet dismissed. If it saved, the reminder is now
            // `.done` - close this sheet too (the list shows it as history).
            if newValue == nil, reminderIsDone() {
                dismiss()
            }
        }
    }

    // MARK: - Pieces

    private var dragHandle: some View {
        Capsule()
            .fill(Theme.Palette.inkSoft.opacity(0.45))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 16)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.taillight.opacity(0.14))
                    .frame(width: 46, height: 46)
                Circle()
                    .stroke(Theme.Palette.taillight, lineWidth: 1.5)
                    .frame(width: 46, height: 46)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Palette.taillight)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(completionTitle)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(completionSubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("reminderCompleteHeader")
    }

    private var logTheCostCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log the cost?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            // `fixedSize(vertical:)` is load-bearing: inside a `.medium`
            // presentation detent SwiftUI compresses flexible content, and this
            // line was clipped to one with an ellipsis in BOTH languages
            // ("... the category, title and t...", "... категорией, н..."). It
            // is the sentence that explains what the button will do, so a
            // truncated version is worse than none - it stops mid-promise.
            Text("Creates an entry pre-filled with the category, title and today's odometer – type a total and save.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            Button(action: typeAmount) {
                Text("Type amount")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityIdentifier("reminderCompleteTypeAmount")

            Button(action: skip) {
                Text("Skip – just mark done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reminderCompleteSkip")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .padding(.top, 18)
    }

    private func nextCycleCard(_ next: Reminder) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.headlight)
            Text(nextCycleLine(next))
                .font(.caption)
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            Button(action: onEdit) {
                Text("Edit")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.headlight)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reminderCompleteEditNextCycle")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Theme.Palette.headlight.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Theme.Palette.headlight.opacity(0.3), lineWidth: 1)
        )
        .padding(.top, 12)
        .accessibilityIdentifier("reminderCompleteNextCycle")
    }

    private var secondaryActions: some View {
        HStack(spacing: 26) {
            Button(action: onEdit) {
                Text("Reschedule instead")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reminderCompleteReschedule")

            Button(action: onDelete) {
                Text("Delete reminder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reminderCompleteDelete")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    // MARK: - Derived strings

    /// "Oil change – done" - the title plus the completion state. One full
    /// localised phrase per language, never concatenation (the RU pass on P1.4
    /// proved composed strings need their own phrase).
    private var completionTitle: String {
        String(format: L10n.localize("%1$@ – done"), reminder.title)
    }

    /// "Completed today at 119 486 km", or "Completed today" when the current
    /// odometer is unknown. The odometer is runtime data; the phrase is one
    /// catalogue key.
    private var completionSubtitle: String {
        if let currentOdometer {
            return String(format: L10n.localize("Completed today at %1$@ km"),
                          OdometerFormat.grouped(currentOdometer))
        }
        return L10n.localize("Completed today")
    }

    /// "Next cycle scheduled: in 15 000 km or Aug 2027 – counted from today,
    /// not the old due date." The due line is the same phrase `ReminderRowFormat`
    /// renders on the list, embedded in one full localised sentence.
    private func nextCycleLine(_ next: Reminder) -> String {
        let due = ReminderRowFormat.dueLine(
            for: next, currentOdometer: currentOdometer, now: completionDate)
        return String(format: L10n.localize("Next cycle scheduled: %1$@ – counted from today, not the old due date."),
                      due)
    }

    // MARK: - Actions

    private func typeAmount() {
        completionSession.pending = ReminderCompletionSession.Pending(
            reminder: reminder,
            completionDate: completionDate,
            completionOdometer: currentOdometer)
        switch entryKind {
        case .expense: entrySheet = .expenseEntry
        case .service: entrySheet = .serviceEntry
        }
    }

    private func skip() {
        ReminderCompletionSession.persistCompletion(
            reminder: reminder, entryId: nil,
            completionDate: completionDate,
            completionOdometer: currentOdometer)
        dismiss()
    }

    /// Whether the reminder is now `.done` on disk (the entry saved). Reads the
    /// repository so the sheet closes only when completion actually happened.
    private func reminderIsDone() -> Bool {
        guard let repository = try? AppStore.repository() else { return false }
        let live = try? repository.liveReminders(forVehicle: reminder.vehicleId)
        guard let row = live?.first(where: { $0.id == reminder.id }) else { return false }
        if case .done = row.status { return true }
        return false
    }
}
