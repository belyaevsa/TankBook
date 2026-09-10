import SwiftUI
import TankbookCore

// Vehicle-detail-only sections (P1.12). The controls and rows shared with Add
// car live in Shared/VehicleFormControls.swift; this file is the detail
// screen's own glue - the one-row header (docs/DESIGN.md), the odometer +
// currency card, the units editor section and the archived banner (J13).

// MARK: - One-row header (title and actions on the same line)

/// The detail header, docs/DESIGN.md: ONE row - the car's title on the left,
/// the actions (Archive/Unarchive, Delete) on the same line on the right. Not
/// a stacked large title with a toolbar above it. The archived subtitle
/// renders honestly from `archivedAt` (J13: "Archived · sold Mar 2026 · history
/// kept").
struct VehicleDetailHeader: View {
    let vehicle: Vehicle
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if vehicle.archived {
                    Text(L10n.archivedSubtitle(archivedAt: vehicle.archivedAt))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("vehicleDetailArchivedStatus")
                }
            }
            Spacer(minLength: 8)
            Button(vehicle.archived ? "Unarchive" : "Archive") {
                onArchive()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.dash))
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            .accessibilityIdentifier("vehicleDetailArchiveButton")

            Button("Delete") {
                onDelete()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.dash))
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            .accessibilityIdentifier("vehicleDetailDeleteButton")
        }
        .padding(.top, 4)
    }
}

// MARK: - Odometer + currency card

/// The odometer (initialOdometer, the "current odometer" captured on Add car)
/// and the home-currency row - the same card shape as Add car, bound to the
/// detail form.
struct VehicleDetailOdometerCard: View {
    @Binding var form: VehicleDetailFormState
    @FocusState.Binding var focus: AddVehicleFocus?
    let units: Vehicle.Units

    var body: some View {
        VStack(spacing: 0) {
            // RV.47: whole row (label + gap) focuses the field.
            FocusableFieldRow("Current odometer", $focus, equals: .odometer,
                              rowIdentifier: "vehicleDetailOdometerRow") {
                VehicleOdometerField(odometer: $form.odometer, focus: $focus,
                                     distanceUnit: units.distance, warn: false,
                                     idPrefix: "vehicleDetail")
            }
            CardDivider()
            FieldRow("Home currency") {
                VehicleHomeCurrencyMenu(currency: $form.homeCurrency, idPrefix: "vehicleDetail")
            }
        }
        .formCard()
    }
}

// MARK: - Pace limit (PJ.45)

/// The per-car pace limit (PJ.45). `paceLimitKmPerDay` is the threshold CHECK 2
/// compares an implied daily pace against; a flag lands the entry in "Needs a
/// look" and excludes its segment from consumption (docs/SCHEMA.md, Validation).
/// The field is a suggestion the user owns (hard rule 13): pre-filled from the
/// car, editable here, and the caption states the consequence - the same
/// structure PJ.55's favourite row uses. Editing it re-derives the stored flags
/// on save (`VehicleDetailView.commit` calls `revalidateTimeline`), so raising
/// the limit clears a flag that only existed under the old one.
struct VehiclePaceLimitRow: View {
    /// The ScrollViewReader id the row carries, so the `-scrollToPaceLimit`
    /// screenshot pose can bring it into view (the RV.117b pattern).
    static let scrollTarget = "vehicleDetailPaceLimitScrollTarget"

    @Binding var paceLimit: String
    @FocusState.Binding var focus: AddVehicleFocus?
    var idPrefix: String = "vehicleDetail"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FocusableFieldRow("Pace limit", $focus, equals: .paceLimit,
                              rowIdentifier: "\(idPrefix)PaceLimitRow") {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    TextField("", text: $paceLimit)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .focused($focus, equals: .paceLimit)
                        .accessibilityIdentifier("\(idPrefix)PaceLimitField")
                        .numericInput($paceLimit, kind: .integer)
                    Text("km/day")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            Text("Entries whose daily pace exceeds this are marked “Needs a look”.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.bottom, 12)
        }
        .accessibilityIdentifier("\(idPrefix)PaceLimitCard")
        .id(Self.scrollTarget)
    }
}

// MARK: - Archive / delete banner

/// The archived-car banner (J13): the car is out of active stats, its history
/// is kept. Rendered above the form for an archived car.
struct VehicleDetailArchivedBanner: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "archivebox.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)
            Text("This car is archived – it stays out of your active stats, and its history is kept.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .formCard()
        .accessibilityIdentifier("vehicleDetailArchivedBanner")
    }
}
