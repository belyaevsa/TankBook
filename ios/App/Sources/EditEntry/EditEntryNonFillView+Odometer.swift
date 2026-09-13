import SwiftUI
import TankbookCore

// RV.230: the non-fill odometer card split out of `EditEntryNonFillView.swift`
// for the linter's file/type-body ceilings - the `EditEntryView+Neighbourhood`
// precedent. The card is where the F9a warn row lives, so the split keeps that
// subject in one named file. The card itself is the shared `EntryOdometerCard`,
// so the Expense capture door renders the same row.

extension EditEntryNonFillView {
    /// The odometer card: the shared field row. The F9a warn that belongs with
    /// it is PINNED above the save bar by `EditEntryView` (RV.235), because on
    /// this form the card sits below the fold at rest and an in-card warn would
    /// put its only next step under the bar when it first appeared. It is still
    /// the shared `F9aWarningRow`, so the two edit surfaces cannot drift.
    var odometerCard: some View {
        EntryOdometerCard(
            odometer: $form.odometer,
            focus: $focus,
            target: EditEntryNonFillFocus.odometer,
            distanceUnit: distanceUnit,
            rowIdentifier: "editEntryOdometerRow",
            fieldIdentifier: "editEntryOdometerField")
    }
}
