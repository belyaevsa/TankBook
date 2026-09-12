import SwiftUI
import TankbookCore

// RV.230: the non-fill odometer card split out of `EditEntryNonFillView.swift`
// for the linter's file/type-body ceilings - the `EditEntryView+Neighbourhood`
// precedent. The card is where the F9a warn row lives, so the split keeps that
// subject in one named file.

extension EditEntryNonFillView {
    /// The odometer card: the field alone. The F9a warn that belongs with it is
    /// PINNED above the save bar by `EditEntryView` (RV.235), because on this
    /// form the card sits below the fold at rest and an in-card warn would put
    /// its only next step under the bar when it first appeared. It is still the
    /// shared `F9aWarningRow`, so the two edit surfaces cannot drift.
    var odometerCard: some View {
        odometerRow.formCard()
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
