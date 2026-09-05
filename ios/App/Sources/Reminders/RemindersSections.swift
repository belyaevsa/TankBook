import SwiftUI
import TankbookCore

// MARK: - Category icon

extension ReminderCategory {
    /// The leading glyph for a reminder row. Colour is never the only channel
    /// (docs/DESIGN.md accessibility floor): the icon differs by category, the
    /// amber tint by attention group.
    var symbolName: String {
        switch self {
        case .oil: "drop.fill"
        case .brakes: "minus.circle"
        case .tires: "arrow.triangle.2.circlepath"
        case .battery: "battery.50"
        case .filters: "line.3.horizontal.decrease.circle"
        case .inspection: "checkmark.shield"
        case .repair: "wrench.and.screwdriver"
        case .parts: "gearshape"
        case .wash: "drop.triangle"
        case .insurance: "doc.text"
        case .custom, .other: "bell"
        }
    }
}

// MARK: - The row card

/// One reminder card (design/screens/Reminders.dc.html and, on the merged list
/// RV.75, RemindersAll.dc.html): the leading icon, the title + due line (+
/// recurrence caption), the trailing attention chip on a "Needs attention" row,
/// the complete affordance (P3.5 routes it through the completion sheet), and a
/// menu holding edit/reschedule, dismiss-with-reason and delete. The progress
/// bar echoes the artboard's how-far-through-the-cycle line. `vehicleName` is
/// the merged list's per-row car chip - a merged row that does not say which
/// car it is about is unreadable; the per-car list passes nil and draws none.
struct ReminderRow: View {
    let reminder: Reminder
    let currentOdometer: Int?
    /// The row's car name, rendered as the chip the merged list's artboard
    /// draws next to the title; nil on the per-car screen (which already names
    /// its car in context).
    var vehicleName: String?
    let group: ReminderGroup
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onDelete: () -> Void

    private var isAttention: Bool { group == .attention }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                NavigationLink(value: Route.reminderForm(reminderID: reminder.id, vehicleID: nil)) {
                    HStack(spacing: 10) {
                        Image(systemName: reminder.category.symbolName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isAttention ? Theme.Palette.warn : Theme.Palette.inkSoft)
                            .frame(width: 19, height: 19)
                        VStack(alignment: .leading, spacing: 2) {
                            titleLine
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminderRowEdit")

                if let chipText {
                    Text(chipText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.warn)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.warn.opacity(0.12)))
                        .accessibilityIdentifier("reminderChip")
                }

                completeButton
                menu
            }
            .padding(14)
            .padding(.bottom, 4)

            progressBar
        }
        .formCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(isAttention ? Theme.Palette.warn.opacity(0.45) : Theme.Palette.hairline,
                        lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var completeButton: some View {
        Button(action: onComplete) {
            Image(systemName: isAttention ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isAttention ? Theme.Palette.warn : Theme.Palette.inkSoft)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Complete")
        .accessibilityIdentifier("reminderCompleteButton")
    }

    private var menu: some View {
        Menu {
            NavigationLink(value: Route.reminderForm(reminderID: reminder.id, vehicleID: nil)) {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                onDismiss()
            } label: {
                Label("Dismiss", systemImage: "hand.raised")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Reminder actions")
        .accessibilityIdentifier("reminderRowMenu")
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(isAttention ? Theme.Palette.warn.opacity(0.16) : Theme.Palette.ink.opacity(0.10))
                Capsule()
                    .fill(isAttention ? Theme.Palette.warn : Theme.Palette.inkSoft.opacity(0.45))
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Derived

    /// The title with, on the merged list, the car chip the artboard draws
    /// beside it.
    ///
    /// **The TITLE holds the width, not the chip.** Both are user data, but the
    /// title is what the user is scanning for - the chip only says which car,
    /// and a car is still identifiable from a scaled or clipped chip while
    /// "Oil change" clipped to "Oi..." says nothing at all. The first version of
    /// this row gave the chip the higher layout priority, and on an attention
    /// row - where the countdown pill, the complete button and the menu also
    /// compete - the titles rendered as "Oi..." and "In-su...", in BOTH
    /// languages. No test saw it; the screenshots did.
    /// Giving the title the priority instead only moved the damage: the chip
    /// then rendered as "Sko..." and, on the longest row, as a bare "...",
    /// which fails this row's own requirement that every row name its car.
    /// Neither element can win outright, so the layout adapts - `ViewThatFits`
    /// keeps the chip beside the title while both fit whole, and drops it to
    /// its own line underneath when they do not. Both stay readable at every
    /// width, in both languages, which is the only acceptable outcome.
    private var titleLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 7) {
                titleText
                carChip
            }
            VStack(alignment: .leading, spacing: 4) {
                titleText
                carChip
            }
        }
    }

    private var titleText: some View {
        Text(reminder.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(2)
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
                .accessibilityIdentifier("reminderCarChip")
        }
    }

    private var caption: String {
        ReminderRowFormat.caption(for: reminder,
                                  currentOdometer: currentOdometer)
    }

    private var chipText: String? {
        isAttention ? ReminderRowFormat.chip(for: reminder, currentOdometer: currentOdometer) : nil
    }

    /// How far through the current cycle the reminder is, 0...1 - the artboard's
    /// progress line. A date-based cycle spans created -> due; an odometer-only
    /// cycle spans the current reading -> the due reading (the fraction of the
    /// road to due already travelled).
    private var progress: Double {
        let now = Date()
        if let dueDate = reminder.dueDate {
            let total = dueDate.timeIntervalSince(reminder.createdAt)
            guard total > 0 else { return 0 }
            return min(1, max(0, now.timeIntervalSince(reminder.createdAt) / total))
        }
        guard let dueOdometer = reminder.dueOdometer, dueOdometer > 0 else { return 0 }
        return min(1, max(0, Double(currentOdometer ?? 0) / Double(dueOdometer)))
    }
}
