import SwiftUI
import TankbookCore

// The Add-car-only cards. The controls both screens share (photo tile,
// powertrain picker, fuel pills, capacity field, home-currency menu, odometer
// field) live in Shared/VehicleFormControls.swift - lifted out in P1.12 so the
// Add car and Vehicle detail screens cannot drift apart.

// MARK: - Odometer + currency card

/// Odometer row with its warn (error-state 2, "Fix · confirm it's right" -
/// never blocks) and the locale-defaulted home currency row.
struct AddVehicleOdometerCard: View {
    @Binding var form: AddVehicleFormState
    @FocusState.Binding var focus: AddVehicleFocus?
    let units: Vehicle.Units

    var body: some View {
        VStack(spacing: 0) {
            odometerRow
            if form.showOdometerWarning {
                odometerWarningRow
            }
            CardDivider()
            homeCurrencyRow
        }
        .formCard()
    }

    private var odometerRow: some View {
        FieldRow("Current odometer") {
            VehicleOdometerField(odometer: $form.odometer, focus: $focus,
                                 distanceUnit: units.distance, warn: false,
                                 idPrefix: "addVehicle") {
                form.odometerTouched = true
            }
        }
    }

    private var odometerWarningRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 8) {
                Text("That's the total distance the car has driven – check the dashboard.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("addVehicleOdometerWarning")
                HStack(spacing: 14) {
                    Button("Fix") {
                        focus = .odometer
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.headlight)
                    .accessibilityIdentifier("addVehicleOdometerFixButton")
                    Button("It's right") {
                        form.odometerConfirmed = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.headlight)
                    .accessibilityIdentifier("addVehicleOdometerConfirmButton")
                }
                .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.bottom, 12)
    }

    private var homeCurrencyRow: some View {
        FieldRow("Home currency") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                VehicleHomeCurrencyMenu(currency: $form.homeCurrency, idPrefix: "addVehicle")
                Text("· stats shown in this")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }
}

// MARK: - Improves accuracy card (capacity + units)

/// Tank/battery capacity (the "Improves accuracy · optional" section) and the
/// units row. For EV the single capacity field is battery kWh, else tank L.
struct AddVehicleAccuracyCard: View {
    @Binding var form: AddVehicleFormState
    @FocusState.Binding var focus: AddVehicleFocus?
    let units: Vehicle.Units

    var body: some View {
        VStack(spacing: 0) {
            capacityRow
            CardDivider()
            unitsRow
        }
        .formCard()
    }

    private var capacityRow: some View {
        let isElectric = form.powertrain == .ev
        return VehicleCapacityField(capacity: $form.capacity, isElectric: isElectric,
                                    volumeUnit: units.volume, focus: $focus,
                                    idPrefix: "addVehicle")
    }

    private var unitsRow: some View {
        FieldRow("Units") {
            Text(unitsLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("addVehicleUnitsRow")
        }
    }

    private var unitsLabel: String {
        let distance = L10n.distanceUnit(units.distance)
        let volume = L10n.volumeUnit(units.volume)
        let consumption = L10n.consumptionUnit(units.consumption)
        return "\(distance) · \(volume) · \(consumption)"
    }
}
