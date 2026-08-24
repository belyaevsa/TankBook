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
            FieldRow("Current odometer") {
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
