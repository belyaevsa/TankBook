import SwiftUI
import UIKit
import TankbookCore

/// The Reminders screen (P3.4) - design/screens/Reminders.dc.html. A pushed
/// route reached from the Home banner, Vehicle detail and push notifications
/// (docs/SCREENMAP.md).
///
/// The list draws two groups the artboard specifies - "Needs attention" then
/// "Scheduled" - and the rows carry the complete affordance whose status
/// transition P3.5 will route through the completion sheet. Until P3.5 the
/// checkmark completes directly as `.done(nil)` (declining the cost log is a
/// first-class path, docs/SCHEMA.md). The row's other exits (edit/reschedule,
/// dismiss-with-reason, delete) live in the trailing menu so the card itself
/// stays close to the artboard.
struct RemindersView: View {
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator

    /// PJ.5: the reminder a tapped notification named. When set, the screen
    /// surfaces that reminder's completion flow once its list has loaded; when
    /// the reminder no longer exists (deleted since the notification was
    /// scheduled), it is simply the plain list - a stale tap is a landing, not
    /// a dead end (hard rule 7). `nil` from the ordinary navigation links
    /// (Home banner, Vehicle detail).
    var reminderToComplete: UUID?

    @State private var reminders: [Reminder] = []
    @State private var vehicle: Vehicle?
    @State private var currentOdometer: Int?
    @State private var didLoad = false
    @State private var dismissTarget: Reminder?
    @State private var dismissReason = ""
    @State private var deleteTarget: Reminder?
    /// The reminder being completed (P3.5): presents the ReminderComplete sheet.
    @State private var completeTarget: ReminderSheetTarget?
    /// An edit request handed off across the sheet's dismissal (Edit /
    /// Reschedule instead): dismiss the sheet, then push the form once it is
    /// gone so the sheet-dismiss and the push never race.
    @State private var pendingEditID: UUID?
    @State private var editReminderID: UUID?
    @State private var isPresentingEdit = false

    private var attention: [Reminder] {
        reminders.filter { ReminderLifecycle.isAttentionDue($0, currentOdometer: currentOdometer, now: Date()) }
    }

    private var scheduled: [Reminder] {
        reminders.filter { !ReminderLifecycle.isAttentionDue($0, currentOdometer: currentOdometer, now: Date()) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if notificationCoordinator.showsDeniedCard {
                    deniedCard
                }
                if reminders.isEmpty {
                    emptyState
                } else {
                    if !attention.isEmpty {
                        SectionEyebrow("Needs attention")
                            .accessibilityIdentifier("remindersAttentionHeader")
                        ForEach(sorted(attention), id: \.id) { row in rowView(row, group: .attention) }
                    }
                    if !scheduled.isEmpty {
                        SectionEyebrow("Scheduled")
                            .accessibilityIdentifier("remindersScheduledHeader")
                        ForEach(sorted(scheduled), id: \.id) { row in rowView(row, group: .scheduled) }
                    }
                }
                newReminderCard
                footer
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .task { await load() }
        // Returning from the form (a push) reappears the list; reload so a
        // saved reminder shows without relaunching the app.
        .onAppear { if didLoad { reload() } }
        .alert("Dismiss reminder?",
               isPresented: Binding(
                   get: { dismissTarget != nil },
                   set: { if !$0 { dismissTarget = nil } })) {
            TextField("Reason (optional)", text: $dismissReason)
            Button("Dismiss") { confirmDismiss() }
            Button("Cancel", role: .cancel) { dismissTarget = nil }
        } message: {
            Text("It stays in your history – a reason helps the app learn.")
        }
        .alert("Delete reminder?",
               isPresented: Binding(
                   get: { deleteTarget != nil },
                   set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Deleted reminders are gone – this can't be undone.")
        }
        // The P3.5 completion sheet: what was completed, "Log the cost?",
        // Type amount / Skip, and the next-cycle line. Its Edit/Reschedule
        // exit dismisses the sheet and pushes the form once the sheet is gone
        // (onDismiss), so the two presentations never race.
        .sheet(item: $completeTarget, onDismiss: {
            if let id = pendingEditID {
                editReminderID = id
                isPresentingEdit = true
                pendingEditID = nil
            }
            // The completion (Skip or an entry save) changed the reminder's
            // status on disk; re-read so the list shows it as history.
            reload()
        }, content: { target in
            ReminderCompleteSheet(
                reminder: target.reminder,
                currentOdometer: currentOdometer,
                onEdit: {
                    pendingEditID = target.reminder.id
                    completeTarget = nil
                },
                onDelete: {
                    completeTarget = nil
                    deleteTarget = target.reminder
                })
        })
        // The programmatic push for the sheet's Edit / Reschedule exit. A
        // value-based NavigationLink needs a path binding this pushed view does
        // not own; the boolean-presented form pushes the same `DestinationView`
        // (title + hidden tab bar) without one.
        .navigationDestination(isPresented: $isPresentingEdit) {
            DestinationView(route: .reminderForm(editReminderID))
        }
    }

    // MARK: - Rows

    private func rowView(_ reminder: Reminder, group: ReminderGroup) -> some View {
        NavigationLink(value: Route.reminderForm(reminder.id)) {
            ReminderRow(reminder: reminder,
                        currentOdometer: currentOdometer,
                        group: group,
                        onComplete: { completeTarget = ReminderSheetTarget(reminder: reminder) },
                        onDismiss: { presentDismiss(reminder) },
                        onDelete: { deleteTarget = reminder })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(group == .attention ? "reminderRowAttention" : "reminderRowScheduled")
    }

    private func presentDismiss(_ reminder: Reminder) {
        dismissReason = ""
        dismissTarget = reminder
    }

    private func confirmDismiss() {
        guard let target = dismissTarget else { return }
        do {
            let repository = try AppStore.repository()
            let reason = dismissReason.trimmingCharacters(in: .whitespacesAndNewlines)
            try repository.upsertReminder(
                ReminderLifecycle.dismiss(target, reason: reason.isEmpty ? nil : reason))
            dismissTarget = nil
            reload()
        } catch {
            AppLog.error(operation: "reminders.dismiss", category: .notifications, error: error)
        }
    }

    private func confirmDelete() {
        guard let target = deleteTarget else { return }
        do {
            let repository = try AppStore.repository()
            try repository.softDeleteReminder(id: target.id)
            deleteTarget = nil
            // Deletion tombstones the row out of `liveReminders`, so the plan
            // cannot see it - cancel its pending notifications directly.
            Task { await notificationCoordinator.cancelNotifications(for: target) }
            reload()
        } catch {
            AppLog.error(operation: "reminders.delete", category: .notifications, error: error)
        }
    }

    // MARK: - Denied card

    /// The one-time notification-permission card (docs/ERRORS.md -> Reminders:
    /// "Reminders can't notify you - they'll only show here."). Shown once while
    /// permission is denied and reminders exist; "Fine as is" dismisses it for
    /// good, "Enable" deep-links to Settings. Never a nag loop.
    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.slash")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.taillight)
                Text("Reminders can't notify you – they'll only show here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
            HStack(spacing: 8) {
                deniedAction("Enable", identifier: "remindersPermissionEnableButton",
                             action: openSettings)
                deniedAction("Fine as is", identifier: "remindersPermissionFineButton") {
                    notificationCoordinator.dismissDeniedCard()
                }
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("remindersDeniedCard")
    }

    private func deniedAction(_ label: LocalizedStringKey,
                              identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.midnight))
                .overlay(Capsule().stroke(Theme.Palette.ink.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No reminders yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Reminders track the date, the odometer, or both – whichever comes first.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reminderEmptyState")
    }

    // MARK: - New reminder + footer

    private var newReminderCard: some View {
        NavigationLink(value: Route.reminderForm(nil)) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Text("New reminder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.hairline,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("remindersNewReminderButton")
    }

    private var footer: some View {
        Text("Reminders track the date, the odometer, or both – whichever comes first.")
            .font(.caption2)
            .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .accessibilityIdentifier("remindersFooter")
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        ReminderTestSeed.seedIfRequested()
        await refresh()
        // PJ.5: a tapped notification named this reminder - surface its
        // completion flow. Works in release (the deep link is product
        // behavior), and a reminder that no longer exists falls back to the
        // plain list rather than a dead end (hard rule 7).
        if let id = reminderToComplete {
            if let target = reminders.first(where: { $0.id == id }) {
                completeTarget = ReminderSheetTarget(reminder: target)
            }
        } else {
            #if DEBUG
            // `-presentReminderComplete`: open the completion sheet for the first
            // active reminder, so simctl-driven screenshots can capture the sheet
            // without a UI test driving a tap (simctl cannot tap).
            if ProcessInfo.processInfo.arguments.contains("-presentReminderComplete"),
               let target = reminders.first {
                completeTarget = ReminderSheetTarget(reminder: target)
            }
            #endif
        }
    }

    private func reload() {
        Task { await refresh() }
    }

    /// Loads the vehicle, its current odometer and the reconciled active
    /// reminders. The stored `.attention` transition and the notification arming
    /// both live in the coordinator: it persists the transition (so an odometer
    /// crossing arms once) and applies the plan (schedule + cancel).
    private func refresh() async {
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else {
                reminders = []
                self.vehicle = nil
                currentOdometer = nil
                return
            }
            self.vehicle = vehicle
            let entries = try repository.liveEntries(forVehicle: vehicle.id)
            currentOdometer = entries.compactMap(\.odometer).max() ?? vehicle.initialOdometer

            reminders = await notificationCoordinator.reconcile(vehicleId: vehicle.id)
                .filter { ReminderLifecycle.isActive($0) }
        } catch {
            AppLog.error(operation: "reminders.load", category: .notifications, error: error)
        }
    }

    /// Sorted soonest-first by the whichever-comes-first due point.
    private func sorted(_ group: [Reminder]) -> [Reminder] {
        let now = Date()
        return group.sorted { lhs, rhs in
            let lhsKey = ReminderLifecycle.due(lhs)?.dueSortKey(currentOdometer: currentOdometer, now: now) ?? .max
            let rhsKey = ReminderLifecycle.due(rhs)?.dueSortKey(currentOdometer: currentOdometer, now: now) ?? .max
            if lhsKey == rhsKey { return lhs.createdAt < rhs.createdAt }
            return lhsKey < rhsKey
        }
    }
}

/// Which group a reminder renders in (docs/SCHEMA.md: .attention is derived at
/// read time; terminal rows are history and never render here).
enum ReminderGroup {
    case attention
    case scheduled
}

/// `Reminder` is an `Entity`, not `Identifiable` - so a `.sheet(item:)` needs
/// this wrapper to carry the reminder being completed (P3.5).
struct ReminderSheetTarget: Identifiable {
    let reminder: Reminder
    var id: UUID { reminder.id }
}
