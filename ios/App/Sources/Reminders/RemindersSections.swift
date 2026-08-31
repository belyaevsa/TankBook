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

/// One reminder card (design/screens/Reminders.dc.html): the leading icon, the
/// title + due line (+ recurrence caption), the trailing attention chip on a
/// "Needs attention" row, the complete affordance (P3.5 routes it through the
/// completion sheet; until then it completes directly as `.done(nil)`), and a
/// menu holding edit/reschedule, dismiss-with-reason and delete. The progress
/// bar echoes the artboard's how-far-through-the-cycle line.
struct ReminderRow: View {
    let reminder: Reminder
    let currentOdometer: Int?
    let group: ReminderGroup
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onDelete: () -> Void

    private var isAttention: Bool { group == .attention }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                NavigationLink(value: Route.reminderForm(reminder.id)) {
                    HStack(spacing: 10) {
                        Image(systemName: reminder.category.symbolName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isAttention ? Theme.Palette.warn : Theme.Palette.inkSoft)
                            .frame(width: 19, height: 19)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(2)
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
            NavigationLink(value: Route.reminderForm(reminder.id)) {
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
