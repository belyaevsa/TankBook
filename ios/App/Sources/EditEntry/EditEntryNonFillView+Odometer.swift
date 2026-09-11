import SwiftUI
import TankbookCore

// RV.230: the non-fill odometer card split out of `EditEntryNonFillView.swift`
// for the linter's file/type-body ceilings - the `EditEntryView+Neighbourhood`
// precedent. The card is where the F9a warn row lives, so the split keeps that
// subject in one named file.

extension EditEntryNonFillView {
    /// The odometer card: the field plus, when the form flags, the shared F9a
    /// warn row. The warning sits INSIDE the card, exactly as it does on the
    /// fill-up odometer card, so the amber row and its next step read as one
    /// object with the field they are about.
    var odometerCard: some View {
        VStack(spacing: 0) {
            odometerRow
            if let odometerConflict {
                F9aWarningRow(
                    conflict: odometerConflict,
                    warningIdentifier: "editEntryNonFillOdometerWarning",
                    onFixOdometer: { focus = .odometer },
                    // A non-fill conflict is never a CHECK 5 consumption
                    // outlier (no non-fill entry closes a fuel segment), so
                    // `F9aFixPresentation` never yields `checkVolume` here.
                    onFixLiters: {},
                    onFixDate: { showDatePicker = true },
                    odometerFixIdentifier: "editEntryNonFillOdometerFixButton")
            }
        }
        .formCard()
    }

    private var odometerRow: some View {
        FocusableFieldRow("Odometer", $focus, equals: .odometer,
                          rowIdentifier: "editEntryOdometerRow") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $form.odometer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 24))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .odometer)
                    .accessibilityIdentifier("editEntryOdometerField")
                    .numericInput($form.odometer, kind: .integer)
                    .onChange(of: focus) { oldValue, newValue in
                        if newValue == .odometer {
                            form.odometer = OdometerFormat.ungrouped(form.odometer)
                        } else if oldValue == .odometer, let value = form.odometerValue {
                            form.odometer = OdometerFormat.grouped(value)
                        }
                    }
                Text(L10n.distanceUnit(distanceUnit))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }
}
