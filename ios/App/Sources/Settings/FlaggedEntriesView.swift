import SwiftUI
import TankbookCore

/// The Log filtered to flagged entries (docs/SCREENMAP.md: Settings -->|"N
/// entries need a look"| Log). Reached from Settings' flagged row and, since
/// RV.66, directly from the sync chip's body when the account-wide flagged
/// count is non-zero.
///
/// This is a **view** of the entries carrying a `ConflictState` - the count is
/// derived and the screen resolves nothing (hard rule 8): tapping an entry
/// opens Edit entry, where the F9a inline discrepancy and its ranked fixes
/// live. A conflict is decidable only with the entry in front of the user.
///
/// RV.104 adds the row's SECOND door: Accept. A flag on an entry from years
/// back can be a gap nobody remembers - a missing fill, a sold-and-rebought
/// car - that no fix can heal without inventing history. Accept records the
/// user's deliberate per-entry judgement (`FlagAcceptance`, keyed on the
/// entry's odometer + date) and clears the derived flag; the acceptance rides
/// the record's payload to the next device and the validator takes it as INPUT,
/// so a UI-only dismissal is never undone by the next sync. Editing the entry
/// later re-checks it (hard rule 8), and the acceptance stays visible and
/// reversible in Edit entry.
///
/// The list is ACCOUNT-wide (it iterates every live vehicle), which is exactly
/// why each row names its car: a list reached from an account-wide signal mixes
/// entries from several cars, and a row whose title is a station name shared by
/// two cars tells the user nothing about WHERE the problem is (RV.66). The car
/// name is the first thing the row says.
struct FlaggedEntriesView: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppSync.self) private var sync
    @State private var rows: [Row] = []
    @State private var didLoad = false
    @State private var pendingAccept: Row?
    @State private var pendingDelete: Row?
    @State private var acceptReason = ""
    /// The row whose swipe tray is open (RV.133). At most one row is open at a
    /// time; a second swipe closes the first. Kept here, not per row, so the
    /// DEBUG screenshot seam can open a tray without synthesizing a gesture.
    @State private var revealedRowID: UUID?
    /// The edit door a row tap pushes. This is NOT a `NavigationLink`: the link
    /// is a SwiftUI button, and a button that a swipe starts on fires its
    /// action on release-inside even after the finger moved - a horizontal
    /// swipe silently navigated into the editor (RV.133 fact 2). Pushing
    /// programmatically lets the row's own pan gesture own the swipe.
    @State private var pushedEditEntry: Route?

    struct Row: Identifiable, Equatable {
        let id: UUID
        /// The entry's kind, resolved from its concrete type at load. A swipe
        /// Delete must tombstone the RIGHT table and name the RIGHT
        /// `entityType` in its mutation log (RV.133); this is the one place the
        /// row's type is known for free, and it cannot disagree with the title
        /// the same switch just built.
        let kind: LogStream.Kind
        let title: String
        let subtitle: String
        /// The entry's date, kept for ordering (the subtitle is a string that
        /// leads with the car name and cannot be sorted by).
        let date: Date
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows) { row in
                        rowCard(row)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        // The row tap's push (see `pushedEditEntry`): reuses the SAME
        // DestinationView the stack's `navigationDestination(for: Route.self)`
        // renders, so the pushed Edit entry gets identical chrome and title.
        .navigationDestination(item: $pushedEditEntry) { DestinationView(route: $0) }
        .task { await load() }
        // RV.72: this list is a resolution surface (hard rule 8) - the row a
        // user fixes in Edit entry must leave the list when they come back. A
        // save bumps the toast-center revision (Edit entry, Inbox, Recently
        // deleted - every place that resolves or retires an entry), exactly as
        // Home/Trends/Garage reload on it; the .task one-shot cannot see that
        // pop-back because the pushed destination stays alive in the stack.
        .onChange(of: toastCenter.revision) { _, _ in
            Task { await reload() }
        }
        // RV.104: the Accept confirmation. The reason is OPTIONAL and kept - it
        // is what makes the decision readable a year later (the
        // `AnomalyDismissal` precedent). The accept itself is per entry and
        // deliberate; there is deliberately no bulk accept.
        .alert("Accept this entry?", isPresented: acceptAlertBinding) {
            TextField("Reason (optional)", text: $acceptReason)
            Button("Accept") { performAccept() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will stop needing a look. Editing its odometer or date will re-check it.")
        }
        // RV.133: the swipe Delete's one confirmation (closed design: a swipe
        // delete is confirmed once, like every delete in the app, and goes
        // through the soft-delete path - the tombstone lands in Recently
        // deleted for the 30-day window, hard rule 8). The copy is Edit
        // entry's own delete confirmation, reused so the two surfaces say the
        // same thing about the same act.
        .alert("Delete this entry?",
               isPresented: deleteAlertBinding) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently deleted for 30 days.")
        }
        #if DEBUG
        // RV.72 test seam: resolves one flagged entry and bumps the revision
        // WHILE THE LIST STAYS ON SCREEN - the case the pop-back test cannot
        // reach, because a pop-back also fires `.onAppear` and would pass
        // against an appear-only reload. Found by the orchestrator's mutation:
        // swapping the revision observation for `.onAppear` left the whole suite
        // green, so the reason this fix is the right one was untested.
        .task { await FlaggedEntriesTestSeed.resolveOneInPlaceIfRequested(toastCenter) }
        // RV.133 screenshot seam: `-openFlaggedSwipeTray` opens the first
        // row's tray once the list has loaded, because `simctl` cannot
        // synthesize the swipe that reveals it. Screenshot-only, like every
        // `-open*` pose in this codebase; the reveal runs on the rows change
        // so it cannot race the first async load.
        .onChange(of: rows) { _, newRows in
            if ProcessInfo.processInfo.arguments.contains("-openFlaggedSwipeTray"),
               revealedRowID == nil,
               let first = newRows.first {
                revealedRowID = first.id
            }
            // RV.117b screenshot seam: `-openFirstFlaggedEdit` pushes the
            // first flagged row's Edit entry once the list has loaded - the
            // state a row tap reaches, which `simctl` cannot synthesize.
            // Screenshot-only; it reuses the row's own push so the destination
            // and chrome are identical to a real tap.
            if ProcessInfo.processInfo.arguments.contains("-openFirstFlaggedEdit"),
               pushedEditEntry == nil,
               let first = newRows.first {
                pushedEditEntry = .editEntry(first.id)
            }
        }
        #endif
    }

    /// A flagged row, now a swipe-to-reveal surface (RV.133). The two standing
    /// doors are untouched - the whole-row tap on the left (the F9a fix
    /// surface, same as before RV.104) and the RV.104 Accept-with-reason
    /// button on the right - and a leftward swipe opens a second pair: a fast
    /// Accept (no dialog, no reason) and a Delete that asks once. All four lead
    /// to the row's two honest resolutions: fix the facts, or say the facts are
    /// fine - or delete an entry that never belonged here.
    private func rowCard(_ row: Row) -> some View {
        FlaggedSwipeRow(
            row: row,
            isRevealed: Binding(
                get: { revealedRowID == row.id },
                set: { revealedRowID = $0 ? row.id : nil }),
            onOpen: { pushedEditEntry = .editEntry(row.id) },
            onAcceptWithReason: {
                acceptReason = ""
                pendingAccept = row
            },
            onQuickAccept: { applyAccept(row, reason: nil) },
            onDelete: { pendingDelete = row })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Nothing needs a look")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Any entry that needs your attention shows up here.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityIdentifier("flaggedEntriesEmptyState")
    }

    /// The alert binds through a separate bool so clearing `pendingAccept`
    /// dismisses it and cancelling needs no bookkeeping of its own.
    private var acceptAlertBinding: Binding<Bool> {
        Binding(get: { pendingAccept != nil },
                set: { if !$0 { pendingAccept = nil } })
    }

    /// The swipe-Delete confirmation binds the same way as the accept alert:
    /// clearing `pendingDelete` dismisses it, and Cancel needs no bookkeeping.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    /// The deliberate per-entry accept: stores the `FlagAcceptance` keyed to
    /// the entry's current facts and clears the derived conflict. The flagged
    /// count is derived (hard rule 2), so it drops by exactly this one row, and
    /// Settings' copy of it refreshes through `AppSync`.
    private func performAccept() {
        guard let row = pendingAccept else { return }
        pendingAccept = nil
        let reason = acceptReason.trimmingCharacters(in: .whitespacesAndNewlines)
        applyAccept(row, reason: reason.isEmpty ? nil : reason)
    }

    /// The one accept path, shared by the reason dialog and the swipe tray
    /// (the tray passes `nil`: a closed decision - the fast door needs neither
    /// confirmation nor a reason, the acceptance stays reversible and is
    /// re-checked later, hard rule 8).
    private func applyAccept(_ row: Row, reason: String?) {
        do {
            let repository = try AppStore.repository()
            if try repository.acceptFlag(id: row.id, reason: reason) {
                toastCenter.noteEntryChanged()
                Task { await sync.refresh() }
            }
        } catch {
            AppLog.error(operation: "flaggedEntries.accept", category: .ui, error: error)
        }
    }

    /// The swipe Delete, confirmed once and tombstoned, never hard-deleted: the
    /// row carries its kind so the RIGHT table is tombstoned and the OB.2
    /// mutation pair names the right `entityType` - the same per-kind dispatch
    /// Edit entry's delete performs (docs/SYNC.md -> 30-day undo, hard rule 8).
    private func performDelete() {
        guard let row = pendingDelete else { return }
        pendingDelete = nil
        do {
            let repository = try AppStore.repository()
            switch row.kind {
            case .fuel:
                try loggedWrite(AppLog.shared, op: .delete, entityType: FillUp.entityType,
                                entityId: row.id, source: .manual) {
                    try repository.softDeleteFillUp(id: row.id)
                }
            case .charge:
                try loggedWrite(AppLog.shared, op: .delete, entityType: ChargeSession.entityType,
                                entityId: row.id, source: .manual) {
                    try repository.softDeleteChargeSession(id: row.id)
                }
            case .service:
                try loggedWrite(AppLog.shared, op: .delete, entityType: ServiceRecord.entityType,
                                entityId: row.id, source: .manual) {
                    try repository.softDeleteServiceRecord(id: row.id)
                }
            case .expense:
                try loggedWrite(AppLog.shared, op: .delete, entityType: Expense.entityType,
                                entityId: row.id, source: .manual) {
                    try repository.softDeleteExpense(id: row.id)
                }
            }
            toastCenter.noteEntryChanged()
            Task { await sync.refresh() }
        } catch {
            AppLog.error(operation: "flaggedEntries.delete", category: .ui, error: error)
        }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        // RV.133 pose: `-presentScreen flaggedEntries` shows this screen
        // directly (simctl cannot tap through Settings), so a direct present
        // seeds the list's own data before the first query. Harmless when the
        // list was reached through Settings - the seed is idempotent.
        await FlaggedEntriesTestSeed.seedForDirectPresentIfRequested()
        #endif
        await reload()
    }

    /// The query, unguarded - called on the first appearance by `load()` and on
    /// every revision bump since (RV.72). Account-wide, live rows only.
    private func reload() async {
        do {
            let repository = try AppStore.repository()
            let stations = try repository.liveStations()
            let vehicles = try repository.liveVehicles()
            var flagged: [Row] = []
            for vehicle in vehicles {
                for entry in try repository.liveEntries(forVehicle: vehicle.id)
                where entry.conflict != .none {
                    flagged.append(Row(id: entry.id,
                                       kind: LogStream.Kind(entry),
                                       title: Self.title(entry, stations: stations),
                                       subtitle: Self.subtitle(entry, vehicleName: vehicle.name),
                                       date: entry.date))
                }
            }
            rows = flagged.sorted { $0.date > $1.date }
        } catch {
            rows = []
        }
    }

    /// "Volvo V60 · Sep 3" - the car name first, so a list that mixes cars says
    /// where each problem lives before the date does. The list sorts by the
    /// entry's date (never this string), so the leading car name cannot disturb
    /// the order.
    private static func subtitle(_ entry: any Entry, vehicleName: String) -> String {
        "\(vehicleName) · \(HomeFormat.day(entry.date))"
    }

    private static func title(_ entry: any Entry, stations: [Station]) -> String {
        switch entry {
        case let fill as FillUp:
            if let stationID = fill.stationId,
               let name = stations.first(where: { $0.id == stationID })?.name {
                return name
            }
            return fill.fuelKind.fuelKindLabel
        case let charge as ChargeSession:
            return charge.provider ?? L10n.localize("Charge")
        case let service as ServiceRecord:
            return service.vendor ?? L10n.localize("Service")
        case let expense as Expense:
            return expense.title.isEmpty ? L10n.localize("Expense") : expense.title
        default:
            return L10n.localize("Entry")
        }
    }
}

// MARK: - The swipe row (RV.133)

/// One flagged row as a swipe-to-reveal surface. Swiping LEFT slides the card
/// aside to reveal a trailing two-action tray: a fast Accept (no dialog, no
/// reason - a closed decision, RV.133 #1) and a Delete that asks once before
/// it tombstones the entry into Recently deleted (hard rule 8).
///
/// This is NOT a `List`, so `.swipeActions` does not exist here (it is a
/// `List`-only modifier) and the surface stays a ScrollView because the card
/// treatment is deliberate (docs/DESIGN.md -> Cards). The drag is therefore
/// hand-rolled, and the THREE-way conflict decides its shape:
///
/// - The whole-row tap must still open Edit entry: the drag needs a
///   `minimumDistance`, so a tap never starts it.
/// - The vertical ScrollView drag must still scroll: the gesture is attached
///   `.simultaneousGesture`, never `.gesture`, and moves the card only while
///   the horizontal movement dominates - so a vertical or diagonal drag is
///   left to the ScrollView untouched and can never wedge the list.
/// - The horizontal drag reveals the tray: it snaps open past half the tray
///   width or on a leftward flick, and snaps closed on a rightward flick.
///
/// At most one row is open at a time; the open state lives on the parent so a
/// second swipe closes the first and the screenshot seam can open a tray
/// without synthesizing a gesture. Both tray actions are also reachable as
/// accessibility actions on the row (docs/DESIGN.md accessibility floor - a
/// swipe-only affordance is unreachable for VoiceOver and Switch Control).
private struct FlaggedSwipeRow: View {
    let row: FlaggedEntriesView.Row
    @Binding var isRevealed: Bool
    let onOpen: () -> Void
    let onAcceptWithReason: () -> Void
    let onQuickAccept: () -> Void
    let onDelete: () -> Void

    @State private var displayOffset: CGFloat = 0

    /// Accept + Delete at a fixed width each, so the reveal width never
    /// depends on text metrics and the snap threshold is stable in both
    /// languages (RU runs longer and the labels must never truncate).
    private let trayWidth: CGFloat = 2 * 88

    var body: some View {
        ZStack(alignment: .trailing) {
            tray
            content
                .formCard()
                .offset(x: displayOffset)
        }
        .simultaneousGesture(drag)
        .onChange(of: isRevealed) { _, revealed in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                displayOffset = revealed ? -trayWidth : 0
            }
        }
    }

    // MARK: The card (the row as it stood before RV.133)

    private var content: some View {
        HStack(spacing: 0) {
            editDoor
            Button {
                onAcceptWithReason()
            } label: {
                Text("Accept")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .accessibilityIdentifier("flagAcceptButton")
        }
    }

    /// The whole-row tap into the editor. Deliberately NOT a NavigationLink
    /// button: the pan below must win the row's horizontal drags, and a button
    /// fires on release-inside even after a swipe started on it (the swipe
    /// silently navigated - the exact feel RV.133 fact 2 forbids). A plain tap
    /// gesture pushes through the parent's `pushedEditEntry` instead, and the
    /// tap never fires on a drag (SwiftUI taps have their own slop).
    private var editDoor: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("flaggedEntrySubtitle")
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        // The row was a button before RV.133; it still IS one for assistive
        // tech and for the UI tests that query it as `flaggedEntryRow`. The
        // children stay reachable (.contain), so the subtitle texts are read
        // and asserted exactly as before.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        // `.contain` leaves the container with no label of its own, and the row
        // carried one while it was a Button: assistive tech announces the row
        // rather than an unnamed group, and the tests identify a specific row
        // by it.
        .accessibilityLabel(Text(verbatim: "\(row.title), \(row.subtitle)"))
        .accessibilityIdentifier("flaggedEntryRow")
        // VoiceOver / Switch Control: the two swipe doors are reachable as
        // custom accessibility actions on the row itself - the tray is
        // swipe-only and therefore invisible to those users (docs/DESIGN.md
        // accessibility floor). Accept acts at once; Delete asks once, the
        // same confirmation the tray shows.
        .accessibilityAction(named: Text("Accept")) { onQuickAccept() }
        .accessibilityAction(named: Text("Delete")) { onDelete() }
    }

    // MARK: The revealed tray

    private var tray: some View {
        HStack(spacing: 0) {
            trayButton(title: "Accept", systemImage: "checkmark",
                       tint: Theme.Palette.ok,
                       identifier: "flagSwipeAcceptButton", action: onQuickAccept)
            traySeparator
            trayButton(title: "Delete", systemImage: "trash",
                       tint: Theme.Palette.warn,
                       identifier: "flagSwipeDeleteButton", action: onDelete)
        }
        .frame(width: trayWidth)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(!isRevealed)
    }

    private func trayButton(title: LocalizedStringKey, systemImage: String,
                            tint: Color, identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)
            .frame(width: trayWidth / 2)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var traySeparator: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    // MARK: The drag

    private var drag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                // Yield the gesture to the ScrollView unless the horizontal
                // movement dominates: the list scrolls and the card never
                // shifts on a vertical drag (the L4 scroll test).
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                let resting = isRevealed ? -trayWidth : 0
                displayOffset = Self.clamp(resting + value.translation.width,
                                           in: -trayWidth...0)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    // A vertical drag (the ScrollView's): snap back to rest.
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        displayOffset = isRevealed ? -trayWidth : 0
                    }
                    return
                }
                let projected = value.predictedEndTranslation.width
                let shouldOpen: Bool
                if projected < -24 {
                    shouldOpen = true          // a leftward flick
                } else if projected > 24 {
                    shouldOpen = false         // a rightward flick
                } else {
                    shouldOpen = displayOffset <= -trayWidth / 2
                }
                isRevealed = shouldOpen
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    displayOffset = shouldOpen ? -trayWidth : 0
                }
            }
    }

    private static func clamp(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
