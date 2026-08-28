import SwiftUI
import TankbookCore

/// J9's anomaly card in the Log (P6.1b): a gentle `warn`-amber card, never a
/// push, never a modal, never mid-capture (docs/JOURNEYS.md J9, docs/ERRORS.md
/// -> Home). This is the ONE place amber is right: genuine attention with a
/// next step, not a disclosure.
///
/// The engine's verdict is rendered verbatim - the card adds no arithmetic
/// (hard rule 2). It states the drift in the vehicle's own consumption unit and
/// names BOTH windows the engine compared (the trailing 90 days vs the same 90
/// days one year earlier), so the figure is falsifiable: the reader can see
/// exactly what "up 21%" was measured against.
///
/// Tap expands the evidence: the drift as a chart (rolling vs baseline, the
/// engine's two values), the possible causes (J9), and the two next steps
/// (hard rule 7): **Create reminder** (act) and **Dismiss with reason** (teaches
/// the model). A card with only dismiss teaches nothing; a card with only act
/// is a nag - both are always present. Dismissal records an `AnomalyDismissal`
/// (persisted by `AnomalyInsightStore`); act additionally creates a service
/// reminder. Never an alert (hard rule 8).
struct AnomalyInsightCard: View {
    let anomaly: ConsumptionAnomaly
    /// The vehicle's consumption unit ("L/100km", "kWh/100") - the same label
    /// the headline on this screen renders, so the card and the hero cannot
    /// disagree about a unit.
    let unitLabel: String
    /// "Act": create the service reminder. The parent owns the repository.
    var onAct: () -> Void = {}
    /// "Dismiss with reason": remember what the user said. The parent owns the
    /// persistence.
    var onDismiss: (AnomalyDismissal) -> Void = { _ in }

    @State private var isExpanded = false
    @State private var showingDismissSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isExpanded {
                evidence
            }
        }
        .padding(14)
        .background(Theme.Palette.warn.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.warn.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeAnomalyCard")
        .task {
            #if DEBUG
            // Screenshot hooks (the same precedent as `-presentReminderComplete`,
            // docs/SCREENMAP.md): simctl cannot tap, so a launch argument drives
            // the state a capture needs.
            // `-presentAnomalyEvidence`: the card expanded (chart + causes +
            // actions). `-presentAnomalyDismissal`: additionally the dismiss
            // sheet on top. Both require a live anomaly - the seed that renders
            // the card also drives the screenshot.
            if ProcessInfo.processInfo.arguments.contains("-presentAnomalyEvidence") {
                isExpanded = true
            }
            if ProcessInfo.processInfo.arguments.contains("-presentAnomalyDismissal") {
                isExpanded = true
                showingDismissSheet = true
            }
            #endif
        }
        .sheet(isPresented: $showingDismissSheet) {
            AnomalyDismissalSheet(cause: anomaly.cause) { dismissal in
                onDismiss(dismissal)
            }
        }
    }

    // MARK: Header (the statement)

    /// The collapsed card: the drift in the vehicle's unit and the window it
    /// was compared against. Tap toggles the evidence.
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.anomalyTitle(percent: L10n.anomalyPercent(anomaly.magnitude)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("homeAnomalyTitle")
                    Text(L10n.anomalyCaption(rolling: valueLabel(anomaly.rollingValue),
                                             baseline: valueLabel(anomaly.baselineValue)))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("homeAnomalyCaption")
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeAnomalyToggle")
    }

    // MARK: Evidence (the drift made visible)

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            chart
            Text(L10n.anomalyCauses)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("homeAnomalyCauses")
            actions
        }
    }

    /// The drift as a chart: the rolling value against the seasonally-aligned
    /// baseline, both exactly as the engine reported them. Amber is the rolling
    /// (what the user should notice); `inkSoft` is the reference year.
    private var chart: some View {
        let maxValue = max(anomaly.rollingValue, anomaly.baselineValue)
        let barHeight: CGFloat = 58
        return HStack(alignment: .bottom, spacing: 24) {
            bar(value: anomaly.rollingValue,
                label: L10n.anomalyRollingLabel,
                color: Theme.Palette.warn,
                height: barHeight * barRatio(anomaly.rollingValue, max: maxValue))
            bar(value: anomaly.baselineValue,
                label: L10n.anomalyBaselineLabel,
                color: Theme.Palette.inkSoft,
                height: barHeight * barRatio(anomaly.baselineValue, max: maxValue))
        }
        .frame(height: 96, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeAnomalyChart")
    }

    /// The fraction of the tallest bar this value reaches (0-1). Both values
    /// are the engine's, so this is presentation scaling, not arithmetic on the
    /// drift itself.
    private func barRatio(_ value: Double, max: Double) -> CGFloat {
        max > 0 ? CGFloat(value / max) : 0
    }

    private func bar(value: Double, label: String, color: Color, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            Text(ManualFillUpFormat.decimal(value, fractionDigits: 1))
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .foregroundStyle(Theme.Palette.ink)
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 44, height: max(6, height))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The two next steps (hard rule 7)

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: onAct) {
                Text("Create reminder")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.Palette.warn)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeAnomalyActButton")

            Button {
                showingDismissSheet = true
            } label: {
                Text("Dismiss with reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeAnomalyDismissButton")
        }
    }

    // MARK: Derived strings

    /// "6.5 L/100km" - a window's value in the vehicle's own unit (the number
    /// is the engine's; the unit is the same label the headline renders).
    private func valueLabel(_ value: Double) -> String {
        "\(ManualFillUpFormat.decimal(value, fractionDigits: 1))\u{00A0}\(unitLabel)"
    }
}

// MARK: - The dismissal sheet

/// "Dismiss with reason" (J9: dismiss teaches the model): the sheet asks why
/// the consumption is up, offers the reasons a user would actually pick plus a
/// free-text path, and records an `AnomalyDismissal` carrying that reason. The
/// recorded reason is the localized label the user chose (the same shape as
/// `ReminderLifecycle.dismiss(reason:)` - the reason is data, never a
/// pre-computed verdict, hard rule 2).
struct AnomalyDismissalSheet: View {
    let cause: AnomalyCause
    var onDismiss: (AnomalyDismissal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCustom = false
    @State private var customReason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dragHandle
            header
            reasons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(Theme.Palette.dash)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.Palette.dash)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anomalyDismissalSheet")
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Theme.Palette.inkSoft.opacity(0.45))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.anomalyDismissTitle)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("anomalyDismissTitle")
            Text(L10n.anomalyDismissSubtitle)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("anomalyDismissHeader")
    }

    private var reasons: some View {
        VStack(spacing: 10) {
            reasonButton(title: L10n.localize("It's winter"),
                         identifier: "anomalyDismissReasonWinter") {
                record(L10n.localize("It's winter"))
            }
            reasonButton(title: L10n.localize("Changed tyres"),
                         identifier: "anomalyDismissReasonTyres") {
                record(L10n.localize("Changed tyres"))
            }
            reasonButton(title: L10n.localize("Towing"),
                         identifier: "anomalyDismissReasonTowing") {
                record(L10n.localize("Towing"))
            }
            if showingCustom {
                customEntry
            } else {
                reasonButton(title: L10n.localize("Other"),
                             identifier: "anomalyDismissReasonOther") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCustom = true
                    }
                }
            }
        }
        .padding(.top, 18)
    }

    private func reasonButton(title: String, identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Theme.Palette.midnight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// The free-text path: a reason of the user's own, saved explicitly.
    private var customEntry: some View {
        VStack(spacing: 10) {
            TextField(L10n.localize("Other"), text: $customReason)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.Palette.midnight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Palette.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier("anomalyDismissCustomField")
            Button {
                let trimmed = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                record(trimmed)
            } label: {
                Text("Save")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(customSaveEnabled ? Color.white : Theme.Palette.inkSoft.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(customSaveEnabled ? Theme.Palette.warn : Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!customSaveEnabled)
            .accessibilityIdentifier("anomalyDismissSaveButton")
        }
    }

    private var customSaveEnabled: Bool {
        !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func record(_ reason: String) {
        onDismiss(AnomalyDismissal(cause: cause, reason: reason, dismissedAt: Date()))
        dismiss()
    }
}
