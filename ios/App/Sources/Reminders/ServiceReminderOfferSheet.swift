import SwiftUI
import TankbookCore

/// The post-save "Remind you next time?" offer (RV.77, docs/JOURNEYS.md J7d
/// "Just did it"; artboard `design/screens/ServiceReminderOffer.dc.html`).
///
/// The sheet the tab roots present once a ServiceRecord or Expense has saved
/// and the entry sheet has gone: it names the reminder it would create, shows
/// the interval as TWO EDITABLE fields (a suggestion, never a fact - hard rule
/// 13), previews the due moment counted from the RECORD (never from today), and
/// asks the user to create it or not. Nothing is created by appearing; only
/// "Create the reminder" persists. "Not this time" is a peer button, not a
/// dismissal X - declining costs nothing (the record is already saved).
struct ServiceReminderOfferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator

    let proposal: ReminderOffer.Proposal
    @State private var form: ServiceReminderOfferFormState

    init(proposal: ReminderOffer.Proposal) {
        self.proposal = proposal
        _form = State(initialValue: ServiceReminderOfferFormState(proposal: proposal))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                savedLine
                headline
                anchorLine
                intervalCard
                if let caption = dueCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("serviceReminderOfferDueCaption")
                }
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("serviceReminderOfferSheet")
    }

    // MARK: - Header

    /// The green check + the driving record's title, confirming what saved.
    private var savedLine: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Palette.ok)
            Text(String(format: L10n.localize("%1$@ saved"), proposal.title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(2)
                .accessibilityIdentifier("serviceReminderOfferSavedLine")
        }
    }

    private var headline: some View {
        Text("Remind you next time?")
            .font(.custom(AppFonts.dinAlternateBold, size: 22))
            .foregroundStyle(Theme.Palette.ink)
            .accessibilityIdentifier("serviceReminderOfferHeadline")
    }

    /// "Counted from this record, not from today – 123 600 km, Sep 5." The
    /// anchor is the record's OWN date/odometer; the reminder must never count
    /// from today (the no-drift rule).
    private var anchorLine: some View {
        let date = ReminderRowFormat.dateString(proposal.date)
        let text: String
        if let odometer = proposal.odometer {
            text = ReminderRowFormat.endingSentence(
                String(format: L10n.localize("Counted from this record, not from today – %1$@ km, %2$@."),
                       OdometerFormat.grouped(odometer), date))
        } else {
            text = ReminderRowFormat.endingSentence(
                String(format: L10n.localize("Counted from this record, not from today – %1$@."), date))
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("serviceReminderOfferAnchor")
    }

    // MARK: - The interval card

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminderTitle)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineLimit(2)
                .accessibilityIdentifier("serviceReminderOfferEyebrow")
            HStack(spacing: 8) {
                intervalField(value: $form.everyKm,
                              unit: L10n.localize("km"),
                              identifier: "serviceReminderOfferKmField",
                              accessibilityLabel: L10n.localize("km"))
                Text("or")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                intervalField(value: $form.everyMonths,
                              unit: L10n.localize("months"),
                              identifier: "serviceReminderOfferMonthsField",
                              accessibilityLabel: L10n.localize("months"))
            }
            .padding(.top, 4)
            Text("A suggested interval, not a fact: change it here or later.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("serviceReminderOfferIntervalNote")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .padding(.top, 2)
    }

    private func intervalField(value: Binding<String>,
                               unit: String,
                               identifier: String,
                               accessibilityLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 20))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
                .numericInput(value, kind: .integer)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: createReminder) {
                Text("Create the reminder")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canCreate ? Theme.Palette.taillight : Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
            .accessibilityIdentifier("serviceReminderOfferCreateButton")

            if !canCreate, let hint = saveHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("serviceReminderOfferCreateHint")
            }

            Button {
                decline()
            } label: {
                Text("Not this time")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Palette.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("serviceReminderOfferNotThisTimeButton")
        }
        .padding(.top, 2)
    }

    // MARK: - Derived

    private var reminderTitle: String {
        let trimmed = proposal.title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? proposal.category.rawLabel : trimmed
    }

    private var canCreate: Bool {
        ReminderOffer.acceptance(everyKm: form.kmValue,
                                 everyMonths: form.monthsValue,
                                 odometer: proposal.odometer) == .ready
    }

    private var saveHint: String? {
        guard !canCreate else { return nil }
        if form.monthsValue == nil, proposal.odometer == nil {
            return L10n.localize("A km interval needs an odometer on the record – use months, or edit the record.")
        }
        return L10n.localize("Set a distance or a number of months to create the reminder.")
    }

    /// The live "Whichever comes first – around 138 600 km or Sep 2027" preview,
    /// recomputed from the two editable fields. Mirrors the acceptance rule so
    /// the caption can never promise a due the Create button cannot build.
    private var dueCaption: String? {
        let months = form.monthsValue
        let km = form.kmValue
        if let months, let km, let odometer = proposal.odometer {
            return ReminderRowFormat.endingSentence(
                String(format: L10n.localize("Whichever comes first – around %1$@ km or %2$@."),
                       OdometerFormat.grouped(odometer + km),
                       ReminderRowFormat.dateString(monthsFromNow(months))))
        }
        if let months {
            return ReminderRowFormat.endingSentence(
                String(format: L10n.localize("Around %1$@."),
                       ReminderRowFormat.dateString(monthsFromNow(months))))
        }
        if let km, let odometer = proposal.odometer {
            return String(format: L10n.localize("Around %1$@ km."),
                          OdometerFormat.grouped(odometer + km))
        }
        return nil
    }

    private func monthsFromNow(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: proposal.date) ?? proposal.date
    }

    // MARK: - Accept

    /// Persists the accepted reminder - the ONE action that creates anything.
    /// Anchored at the record by `ReminderOffer.reminder(accepting:)`, then
    /// armed exactly as the Reminder form arms a new reminder.
    private func createReminder() {
        guard canCreate,
              let reminder = ReminderOffer.reminder(accepting: proposal,
                                                    everyKm: form.kmValue,
                                                    everyMonths: form.monthsValue) else { return }
        do {
            let repository = try AppStore.repository()
            try repository.upsertReminder(reminder)
            // A swap proposal's acceptance is its own signal: the reminder is
            // now on disk, so "was a swap reminder proposed, and was it
            // accepted?" has an answer in the field (hard rule 12 - outcome
            // only).
            if proposal.category == .tires {
                AppLog.shared.emit(SwapReminderProposal(outcome: .accepted))
            }
            let vehicleId = reminder.vehicleId
            Task {
                await notificationCoordinator.requestPermissionIfFirstReminder(vehicleId: vehicleId)
                await notificationCoordinator.reconcile(vehicleId: vehicleId)
            }
            dismiss()
        } catch {
            AppLog.error(operation: "serviceReminderOffer.create", category: .notifications, error: error)
        }
    }

    /// "Not this time": the record is already saved and nothing is written. A
    /// swap proposal's decline is recorded for the same reason its acceptance
    /// is - the two outcomes together say whether the seasonal loop is
    /// reaching users at all (hard rule 12).
    private func decline() {
        if proposal.category == .tires {
            AppLog.shared.emit(SwapReminderProposal(outcome: .declined))
        }
        dismiss()
    }
}

/// The offer sheet's editable interval state (km + months). Mirrors
/// `ReminderFormState`: raw strings, parsed on accept.
struct ServiceReminderOfferFormState: Equatable {
    var everyKm = ""
    var everyMonths = ""

    init(proposal: ReminderOffer.Proposal? = nil) {
        guard let proposal else { return }
        everyKm = proposal.everyKm.map(OdometerFormat.grouped) ?? ""
        everyMonths = proposal.everyMonths.map(String.init) ?? ""
    }

    var kmValue: Int? {
        Self.integer(from: everyKm)
    }

    var monthsValue: Int? {
        Self.integer(from: everyMonths)
    }

    private static func integer(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(OdometerFormat.ungrouped(trimmed))
    }
}
