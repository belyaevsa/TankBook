import SwiftUI
import TankbookCore

// The per-car units editor and its cascade (P1.12), in its own file so
// VehicleFormControls.swift stays under the linter's file-length limit.

// MARK: - Units editor (Vehicle detail only)

/// The per-car units editor (docs/DESIGN.md: units live on each car in the
/// Garage, never in Settings). Each of the four unit axes is its own menu;
/// changing one cascades the coherent companions (picking MPG implies mi + gal,
/// picking L/100 implies km + L - the app suggests, the user decides: every
/// value stays overridable after the cascade).
struct VehicleUnitsEditor: View {
    @Binding var units: Vehicle.Units

    var body: some View {
        VStack(spacing: 0) {
            FieldRow("Distance") {
                VehicleUnitMenu(label: L10n.distanceUnit(units.distance)) {
                    ForEach(DistanceUnit.allCases, id: \.self) { unit in
                        Button(L10n.distanceUnit(unit)) { units.setDistance(unit) }
                    }
                }
                .accessibilityIdentifier("vehicleDetailDistanceMenu")
            }
            CardDivider()
            FieldRow("Volume") {
                VehicleUnitMenu(label: L10n.volumeLabel(units.volume)) {
                    ForEach(VolumeUnit.allCases, id: \.self) { unit in
                        Button(L10n.volumeLabel(unit)) { units.setVolume(unit) }
                    }
                }
                .accessibilityIdentifier("vehicleDetailVolumeMenu")
            }
            CardDivider()
            FieldRow("Consumption") {
                VehicleUnitMenu(label: L10n.consumptionLabel(units.consumption)) {
                    ForEach(ConsumptionUnit.allCases, id: \.self) { unit in
                        Button(L10n.consumptionLabel(unit)) { units.setConsumption(unit) }
                    }
                }
                .accessibilityIdentifier("vehicleDetailConsumptionMenu")
            }
            CardDivider()
            FieldRow("Energy") {
                VehicleUnitMenu(label: L10n.energyLabel(units.energy)) {
                    ForEach(EnergyUnit.allCases, id: \.self) { unit in
                        Button(L10n.energyLabel(unit)) { units.setEnergy(unit) }
                    }
                }
                .accessibilityIdentifier("vehicleDetailEnergyMenu")
            }
        }
    }
}

/// A labelled unit picker row: the menu's selected value on the right.
private struct VehicleUnitMenu<Content: View>: View {
    let label: String
    @ViewBuilder let menu: () -> Content

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }
}

// MARK: - Units cascade (the coherent companions)

extension Vehicle.Units {
    /// Distance drives the whole system: miles imply imperial volume/consumption
    /// and mi/kWh energy; kilometres imply metric everywhere.
    mutating func setDistance(_ newValue: DistanceUnit) {
        distance = newValue
        if newValue == .mi {
            if volume == .l { volume = .galUS }
            if consumption == .lPer100 || consumption == .kmPerL { consumption = .mpgUS }
            if energy == .kWhPer100 { energy = .miPerKWh }
        } else {
            if volume == .galUS || volume == .galUK { volume = .l }
            if consumption == .mpgUS || consumption == .mpgUK { consumption = .lPer100 }
            if energy == .miPerKWh { energy = .kWhPer100 }
        }
    }

    /// Volume keeps its consumption unit coherent (a litre car can't report
    /// MPG) and pulls distance/energy along when it becomes imperial.
    mutating func setVolume(_ newValue: VolumeUnit) {
        volume = newValue
        switch newValue {
        case .l:
            if consumption == .mpgUS || consumption == .mpgUK { consumption = .lPer100 }
        case .galUS:
            if consumption == .lPer100 || consumption == .mpgUK { consumption = .mpgUS }
        case .galUK:
            if consumption == .lPer100 || consumption == .mpgUS { consumption = .mpgUK }
        }
        applyCompanions(for: newValue)
    }

    mutating func setConsumption(_ newValue: ConsumptionUnit) {
        consumption = newValue
        switch newValue {
        case .lPer100:
            distance = .km
            volume = .l
            if energy == .miPerKWh { energy = .kWhPer100 }
        case .mpgUS:
            distance = .mi
            volume = .galUS
            if energy == .kWhPer100 { energy = .miPerKWh }
        case .mpgUK:
            distance = .mi
            volume = .galUK
            if energy == .kWhPer100 { energy = .miPerKWh }
        case .kmPerL:
            distance = .km
            volume = .l
            if energy == .miPerKWh { energy = .kWhPer100 }
        }
    }

    mutating func setEnergy(_ newValue: EnergyUnit) {
        energy = newValue
        if newValue == .miPerKWh {
            if distance == .km { distance = .mi }
        } else {
            if distance == .mi && consumption != .mpgUS && consumption != .mpgUK { distance = .km }
        }
    }

    /// The distance/energy half of the volume cascade (extracted so `setVolume`
    /// stays under the linter's complexity limit).
    private mutating func applyCompanions(for volume: VolumeUnit) {
        if volume == .galUS || volume == .galUK {
            if distance == .km { distance = .mi }
            if energy == .kWhPer100 { energy = .miPerKWh }
        } else if volume == .l {
            if distance == .mi && consumption == .mpgUS { distance = .km }
            if energy == .miPerKWh && consumption != .mpgUS && consumption != .mpgUK { energy = .kWhPer100 }
        }
    }
}
