import SwiftUI
import TankbookCore

/// One History row's resolved display content (RV.248): the terminal reminder,
/// the entry a `.done` completion logged (named through the shared
/// `EntryTitle`, never a second title rule), and the honest completion count.
/// Built once per load so the view body performs no repository reads.
struct ReminderHistoryItem: Identifiable {
    let reminder: Reminder
    let entryTitle: String?
    let completionCount: Int

    var id: UUID { reminder.id }

    /// Resolves the entry title for each terminal reminder. The entry is the
    /// completion's bookkeeping (a service record or expense, docs/SCHEMA.md ->
    /// Reminder lifecycle); a `.done(nil)` skip and a dismissal carry none.
    static func items(_ terminal: [Reminder],
                      repository: TankbookRepository) -> [ReminderHistoryItem] {
        ReminderHistory.rows(terminal).map { row in
            var entryTitle: String?
            if let entryId = ReminderHistory.completedEntryId(of: row.reminder),
               let entry = try? repository.liveEntry(id: entryId) {
                entryTitle = EntryTitle.text(entry, stations: [])
            }
            return ReminderHistoryItem(reminder: row.reminder,
                                       entryTitle: entryTitle,
                                       completionCount: row.completionCount)
        }
    }
}

/// The composed display strings of a History row. Kept beside `ReminderRowFormat`
/// and following the same rule: every phrase is a full localised catalogue
/// phrase per language, never concatenation.
enum ReminderHistoryFormat {
    /// The row's caption: a dismissal's reason, "Dismissed" when it carried
    /// none, "Completed · <entry>" for a completion that logged one, and
    /// "Completed" for a skipped cost. The entry title is user data, so it is
    /// interpolated into the localized phrase, never localized itself.
    static func caption(for item: ReminderHistoryItem) -> String {
        switch item.reminder.status {
        case .dismissed:
            return ReminderHistory.dismissalReason(of: item.reminder)
                ?? L10n.localize("Dismissed")
        case .done:
            guard let entryTitle = item.entryTitle, !entryTitle.isEmpty else {
                return L10n.localize("Completed")
            }
            return String(format: L10n.localize("Completed · %@"), entryTitle)
        case .scheduled, .attention:
            return ""
        }
    }
}

/// The History section at the foot of the reminders list (RV.248): terminal
/// rows with their reasons and the entries their completions produced. It uses
/// the live list's own card vocabulary, names each row's car on the merged list
/// exactly as live rows do, and offers no delete affordance - a terminal row is
/// history (hard rule 8), and the 30-day undo for the ones that were deleted
/// lives in Recently deleted, not here.
struct ReminderHistorySection: View {
    let items: [ReminderHistoryItem]
    /// The merged list's per-row car chip; nil on the per-car list, which
    /// already names its car in context.
    let vehicleName: (UUID) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("History", identifier: "remindersHistoryHeader")
            ForEach(items) { item in
                ReminderHistoryRowView(item: item,
                                       vehicleName: vehicleName(item.reminder.vehicleId))
            }
        }
    }
}

/// One History row. A completion that logged an entry is a link to that entry
/// (the user can see the record the reminder became); a skipped cost and a
/// dismissal are read-only history.
private struct ReminderHistoryRowView: View {
    let item: ReminderHistoryItem
    let vehicleName: String?

    var body: some View {
        Group {
            // Link only when the entry still resolves: a completion whose entry
            // was later deleted stays readable history, never a tap into a
            // not-found edit screen (hard rule 7).
            if let entryId = ReminderHistory.completedEntryId(of: item.reminder),
               item.entryTitle != nil {
                NavigationLink(value: Route.editEntry(entryId)) {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminderHistoryEntryLink")
            } else {
                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminderHistoryRow")
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: item.reminder.category.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 19, height: 19)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 7) {
                    Text(item.reminder.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(2)
                    carChip
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("reminderHistoryCaption")
            }
            Spacer(minLength: 0)
            if item.completionCount > 1 {
                Text(String(localized: "\(item.completionCount) times"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Palette.midnight))
                    .accessibilityIdentifier("reminderHistoryCount")
            }
        }
        .padding(14)
        .formCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var caption: String {
        ReminderHistoryFormat.caption(for: item)
    }

    @ViewBuilder
    private var carChip: some View {
        if let vehicleName {
            Text(vehicleName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.Palette.midnight))
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
                .accessibilityIdentifier("reminderHistoryCarChip")
        }
    }
}
