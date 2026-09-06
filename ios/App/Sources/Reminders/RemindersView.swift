import SwiftUI
import UIKit
import TankbookCore

/// Which Reminders list a pushed route draws (docs/SCREENMAP.md -> "Reminders
/// across cars").
enum RemindersScope {
    /// The per-car screen (design/screens/Reminders.dc.html): the selected
    /// car's reminders, reached from the Home banner and Vehicle detail. The
    /// right screen when the user is looking AT a car.
    case selectedVehicle
    /// The merged "all cars" screen (RV.75, RemindersAll.dc.html): every active
    /// car's live reminders in one list, each row naming its car, grouped as
    /// the per-car list is - the question is "what needs me", never "which
    /// car"; each row's km half is judged against ITS OWN car's odometer
    /// (`ReminderListRow`). Reached from the DEBUG `-presentScreen remindersAll`
    /// hook, RV.76's Home row and, since RV.74, the notification deep link
    /// (`.reminderDeepLink` maps here too) - not car-scoped, never the wrong car.
    case allCars
}

    /// The Reminders screen (P3.4). A pushed route reached from the Home banner,
    /// Vehicle detail and push notifications (docs/SCREENMAP.md), and since RV.75
    /// also the merged "all cars" list.
    ///
    /// The list draws two groups the artboard specifies - "Needs attention" then
    /// "Scheduled" - and the rows carry the complete affordance whose status
    /// transition P3.5 routes through the completion sheet. Grouping and ordering
    /// are decided once, in `ReminderListGroups.grouped` (core), so the per-car
    /// and merged lists cannot drift apart and the lifecycle rules are never
    /// duplicated: attention, sorting and completion all come from the existing
    /// core types.
struct RemindersView: View {
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator

    /// PJ.5: the reminder a tapped notification named. When set, the screen
    /// surfaces that reminder's completion flow once its list has loaded; when
    /// the reminder no longer exists (deleted since the notification was
    /// scheduled), it is simply the plain list - a stale tap is a landing, not
    /// a dead end (hard rule 7). `nil` from the ordinary navigation links
    /// (Home banner, Vehicle detail). Since RV.74 the deep link lands on the
    /// merged scope; an ARCHIVED-car reminder is absent from its rows by
    /// decision, and `load()` resolves the id and surfaces it anyway.
    var reminderToComplete: UUID?

    /// Which list this route draws; `.selectedVehicle` unless the merged
    /// `.remindersAll` route says otherwise.
    var scope: RemindersScope = .selectedVehicle

    @State private var rows: [ReminderListRow] = []
    @State private var vehicles: [Vehicle] = []
    @State private var vehicle: Vehicle?
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

    /// The two display groups, each sorted so a date and an odometer reminder
    /// interleave by urgency (ReminderListGroups - the one place the order is
    /// decided).
    private var groups: (attention: [ReminderListRow], scheduled: [ReminderListRow]) {
        ReminderListGroups.grouped(rows)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if notificationCoordinator.showsDeniedCard {
                    deniedCard
                }
                if rows.isEmpty {
                    emptyState
                } else {
                    if !groups.attention.isEmpty {
                        SectionEyebrow("Needs attention")
                            .accessibilityIdentifier("remindersAttentionHeader")
                        ForEach(groups.attention, id: \.id) { row in rowView(row, group: .attention) }
                    }
                    if !groups.scheduled.isEmpty {
                        SectionEyebrow("Scheduled")
                            .accessibilityIdentifier("remindersScheduledHeader")
                        ForEach(groups.scheduled, id: \.id) { row in rowView(row, group: .scheduled) }
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
            // PJ.7: deletion tombstones the row (`softDeleteReminder`), so the
            // 30-day undo holds for reminders exactly as for entries - the
            // alert states that truth (a confirmation, never a warning), and
            // the Recently deleted screen is where the user can act on it.
            Text("Deleted reminders stay here for 30 days, in case you change your mind.")
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
                currentOdometer: target.currentOdometer,
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
            DestinationView(route: .reminderForm(reminderID: editReminderID, vehicleID: nil))
        }
    }

    // MARK: - Rows

    private func rowView(_ row: ReminderListRow, group: ReminderGroup) -> some View {
        NavigationLink(value: Route.reminderForm(reminderID: row.reminder.id, vehicleID: nil)) {
            ReminderRow(reminder: row.reminder,
                        currentOdometer: row.currentOdometer,
                        // The merged list's rows must name their car - a merged
                        // row that does not is unreadable (docs/SCREENMAP.md).
                        vehicleName: scope == .allCars ? vehicleName(for: row.reminder.vehicleId) : nil,
                        group: group,
                        onComplete: {
                            completeTarget = ReminderSheetTarget(reminder: row.reminder,
                                                                 currentOdometer: row.currentOdometer)
                        },
                        onDismiss: { presentDismiss(row.reminder) },
                        onDelete: { deleteTarget = row.reminder })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(group == .attention ? "reminderRowAttention" : "reminderRowScheduled")
    }

    private func vehicleName(for vehicleId: UUID) -> String? {
        vehicles.first { $0.id == vehicleId }?.name
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
            // Deletion tombstones the row out of the live queries, so the plan
            // cannot see it - cancel its pending notifications directly.
            Task { await notificationCoordinator.cancelNotifications(for: target) }
            reload()
        } catch {
            AppLog.error(operation: "reminders.delete", category: .notifications, error: error)
        }
    }

    // MARK: - Denied card

    private var deniedCard: some View {
        ReminderDeniedCard(onEnable: openSettings,
                           onFine: { notificationCoordinator.dismissDeniedCard() })
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Empty state

    /// The list's empty state. The merged list renders what the per-car screen
    /// renders today; RV.76 replaces it with the filled action of
    /// `RemindersEmpty.dc.html` (out of RV.75's scope by agreement, so the two
    /// tasks do not fight over one view).
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
        NavigationLink(value: createRoute) {
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
        .accessibilityIdentifier(scope == .allCars
                                 ? "remindersAllNewReminderButton"
                                 : "remindersNewReminderButton")
    }

    /// Where "New reminder" opens. The opener decides what the form's car field
    /// arrives with (docs/SCREENMAP.md -> "the car as its first field"): a
    /// car's own list names its car; the merged list names none - defaulting
    /// silently to the selected car is the quiet guess hard rule 13 forbids.
    private var createRoute: Route {
        if case .allCars = scope {
            return .reminderForm(reminderID: nil, vehicleID: nil)
        }
        return .reminderForm(reminderID: nil, vehicleID: vehicle?.id)
    }

    private var footer: some View {
        Text(scope == .allCars
             ? "Every car you have, one list. New reminder asks which car."
             : "Reminders track the date, the odometer, or both – whichever comes first.")
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
        #if DEBUG
        ReminderTestSeed.seedIfRequested()
        #endif
        await refresh()
        // PJ.5: a tapped notification named this reminder - surface its
        // completion flow. Works in release (the deep link is product
        // behavior), and a reminder that no longer exists falls back to the
        // plain list rather than a dead end (hard rule 7).
        if let id = reminderToComplete {
            if let target = rows.first(where: { $0.reminder.id == id }) {
                completeTarget = ReminderSheetTarget(reminder: target.reminder,
                                                     currentOdometer: target.currentOdometer)
            } else if let resolved = resolveDeepLinkedReminder(id) {
                // RV.74 archived landing: the reminder's car is archived (rows
                // excluded by decision, J13), so surface its completion here,
                // selection untouched. `nil` (deleted/terminal) keeps the
                // plain-list landing.
                completeTarget = resolved
            }
        } else {
            #if DEBUG
            // `-presentReminderComplete`: open the completion sheet for the first
            // active reminder, so simctl-driven screenshots can capture the sheet
            // without a UI test driving a tap (simctl cannot tap).
            if ProcessInfo.processInfo.arguments.contains("-presentReminderComplete"),
               let target = rows.first {
                completeTarget = ReminderSheetTarget(reminder: target.reminder,
                                                     currentOdometer: target.currentOdometer)
            }
            // PJ.7: `-presentReminderDeleteAlert`: open the delete confirmation
            // for the first reminder, so the corrected alert (the 30-day truth,
            // not a permanent-delete claim) can be captured by simctl, which
            // cannot tap the row's menu.
            if ProcessInfo.processInfo.arguments.contains("-presentReminderDeleteAlert"),
               let target = rows.first {
                deleteTarget = target.reminder
            }
            #endif
        }
    }

    /// RV.74 archived-landing resolve: the completion target for a deep-linked
    /// reminder that is NOT among the loaded rows - on the merged list, exactly
    /// an ARCHIVED car's reminder (excluded by decision). `nil` for a deleted
    /// or terminal reminder keeps the plain-list landing (hard rule 7).
    private func resolveDeepLinkedReminder(_ id: UUID) -> ReminderSheetTarget? {
        guard scope == .allCars,
              let repository = try? AppStore.repository(),
              let reminder = try? repository.liveReminder(id: id),
              ReminderLifecycle.isActive(reminder) else { return nil }
        let odometer = (try? Self.currentOdometer(for: reminder.vehicleId, repository: repository)) ?? nil
        return ReminderSheetTarget(reminder: reminder, currentOdometer: odometer)
    }

    private func reload() {
        Task { await refresh() }
    }

    /// Loads the scope's vehicles, their current odometers and the reconciled
    /// active reminders. The stored `.attention` transition and the notification
    /// arming both live in the coordinator: it persists the transition (so an
    /// odometer crossing arms once) and applies the plan (schedule + cancel).
    /// The merged list reconciles every active car, so a `.scheduled ->
    /// .attention` crossing on a car the user has not opened this session still
    /// arms exactly once.
    private func refresh() async {
        do {
            let repository = try AppStore.repository()
            let live = try repository.liveVehicles()
            self.vehicles = live
            switch scope {
            case .selectedVehicle:
                guard let selected = carSelection.selectedVehicle(live) else {
                    rows = []
                    vehicle = nil
                    return
                }
                self.vehicle = selected
                let odometer = try Self.currentOdometer(for: selected.id, repository: repository)
                let reconciled = await notificationCoordinator.reconcile(vehicleId: selected.id)
                rows = reconciled
                    .filter { ReminderLifecycle.isActive($0) }
                    .map { ReminderListRow(reminder: $0, currentOdometer: odometer) }
            case .allCars:
                // The displayed rows come from the cross-vehicle query - the one
                // query that cannot silently fall back to one car - then each
                // active car is reconciled for its stored transitions and its
                // notifications.
                let across = try repository.liveRemindersAcrossVehicles()
                var merged: [ReminderListRow] = []
                for car in live where !car.archived {
                    let odometer = try Self.currentOdometer(for: car.id, repository: repository)
                    let carRows = across
                        .filter { $0.vehicleId == car.id && ReminderLifecycle.isActive($0) }
                        .map { ReminderListRow(reminder: $0, currentOdometer: odometer) }
                    merged.append(contentsOf: carRows)
                    await notificationCoordinator.reconcile(vehicleId: car.id)
                }
                rows = merged
            }
        } catch {
            AppLog.error(operation: "reminders.load", category: .notifications, error: error)
        }
    }

    /// The vehicle's current odometer: the latest entry's reading, else its
    /// initial odometer - the same derivation the per-car list used.
    private static func currentOdometer(for vehicleId: UUID,
                                        repository: TankbookRepository) throws -> Int? {
        let entries = try repository.liveEntries(forVehicle: vehicleId)
        if let reading = entries.compactMap(\.odometer).max() { return reading }
        return try repository.vehicle(id: vehicleId)?.initialOdometer
    }
}

/// The one-time notification-permission card (docs/ERRORS.md -> Reminders:
/// "Reminders can't notify you - they'll only show here."). Shown once while
/// permission is denied and reminders exist; "Fine as is" dismisses it for
/// good, "Enable" deep-links to Settings. Never a nag loop.
private struct ReminderDeniedCard: View {
    let onEnable: () -> Void
    let onFine: () -> Void

    var body: some View {
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
                             action: onEnable)
                deniedAction("Fine as is", identifier: "remindersPermissionFineButton",
                             action: onFine)
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
}

/// Which group a reminder renders in (docs/SCHEMA.md: .attention is derived at
/// read time; terminal rows are history and never render here).
enum ReminderGroup {
    case attention
    case scheduled
}

/// `Reminder` is an `Entity`, not `Identifiable` - so a `.sheet(item:)` needs
/// this wrapper to carry the reminder being completed (P3.5), with the odometer
/// of the reminder's OWN car (the merged list carries several).
struct ReminderSheetTarget: Identifiable {
    let reminder: Reminder
    let currentOdometer: Int?
    var id: UUID { reminder.id }
}
